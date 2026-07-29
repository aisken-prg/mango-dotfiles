#!/usr/bin/env bash
set -e

# Wallpaper manager for Wayland using wofi.
# - Local wallpapers: pick from $LOCAL_DIR and apply via swaybg.
# - Wallhaven: browse (Toplist/Views/Relevance+search), preview, download.
#
# Dependencies: wofi, jq, curl, swaybg, (optional) notify-send

# --- CONFIG ---
CACHE="$HOME/.cache/wofi-wallhaven"
THUMBS="$CACHE/thumbs"
TMP_WALLS="$CACHE/tmp"
SELECTED_FILE="$CACHE/selected_wall.txt"
QUERY_HISTORY_FILE="$CACHE/query_history.txt"
LOCAL_DIR="$HOME/Pictures/Wallpapers"
CURRENT_FILE="$HOME/Pictures/current_wallpaper.txt"

mkdir -p "$THUMBS" "$TMP_WALLS" "$LOCAL_DIR"

# --- NAV ICONS ---
NAV_NEXT="$CACHE/nav_next.svg"
NAV_PREV="$CACHE/nav_prev.svg"

[ ! -f "$NAV_NEXT" ] && cat > "$NAV_NEXT" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="128" height="128">
  <line x1="2" y1="12" x2="22" y2="12" stroke="#cdd6f4" stroke-width="2.5" stroke-linecap="round"/>
  <polyline points="14,4 22,12 14,20" fill="none" stroke="#cdd6f4" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
EOF

[ ! -f "$NAV_PREV" ] && cat > "$NAV_PREV" << 'EOF'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="128" height="128">
  <line x1="22" y1="12" x2="2" y2="12" stroke="#cdd6f4" stroke-width="2.5" stroke-linecap="round"/>
  <polyline points="10,4 2,12 10,20" fill="none" stroke="#cdd6f4" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
EOF

# --- CSS (written to a temp file, deleted on exit) ---
WOFI_CSS="$(mktemp /tmp/wofi-wallpaper-XXXXXX.css)"
trap 'rm -f "$WOFI_CSS"' EXIT

cat > "$WOFI_CSS" << 'EOF'
#window {
    background-color: #1e1e2e;
}

#outer-box {
    padding: 2px;
}

#entry {
    padding: 1px;
    margin: 1px;
    border-radius: 4px;
}

#entry:selected {
    background-color: rgba(255, 255, 255, 0.15);
}

#text {
    font-size:  0px;
    min-height: 0px;
    color:      transparent;
    padding:    0px;
    margin:     0px;
}
EOF

# --- WALLHAVEN API ---
API="https://wallhaven.cc/api/v1/search"
DEFAULT_RATIOS="16x9"
DEFAULT_ATLEAST="1920x1080"
FILTER_PRESET_FILE="$CACHE/filter_preset.txt"

FILTER_RATIOS=""
FILTER_ATLEAST=""

# --- FUNCTIONS ---

uri_encode() {
    jq -nr --arg v "$1" '$v|@uri'
}

build_wallhaven_url() {
    local query sorting top page q url
    query="${1:-}"
    sorting="${2:-relevance}"
    top="${3-}"
    page="${4:-1}"

    q="$(uri_encode "$query")"
    url="$API?q=$q&sorting=$sorting&page=$page"

    if [[ "$sorting" == "toplist" && -n "$top" ]]; then
        url="$url&topRange=$top"
    fi
    if [[ -n "$FILTER_RATIOS" ]]; then
        url="$url&ratios=$FILTER_RATIOS"
    fi
    if [[ -n "$FILTER_ATLEAST" ]]; then
        url="$url&atleast=$FILTER_ATLEAST"
    fi

    printf '%s' "$url"
}

apply_filter_preset() {
    case "${1:-}" in
        desktop-16x9)
            FILTER_RATIOS="$DEFAULT_RATIOS"
            FILTER_ATLEAST=""
            ;;
        screen-fit)
            FILTER_RATIOS="$DEFAULT_RATIOS"
            FILTER_ATLEAST="$DEFAULT_ATLEAST"
            ;;
        any)
            FILTER_RATIOS=""
            FILTER_ATLEAST=""
            ;;
        *)
            FILTER_RATIOS="$DEFAULT_RATIOS"
            FILTER_ATLEAST=""
            ;;
    esac
}

filters_label() {
    if [[ -n "$FILTER_RATIOS" && -n "$FILTER_ATLEAST" ]]; then
        printf '%s @ >=%s' "$FILTER_RATIOS" "$FILTER_ATLEAST"
        return
    fi
    if [[ -n "$FILTER_RATIOS" ]]; then
        printf '%s' "$FILTER_RATIOS"
        return
    fi
    printf 'any'
}

load_filter_preset() {
    local preset=""
    if [[ -f "$FILTER_PRESET_FILE" ]]; then
        preset="$(head -n 1 "$FILTER_PRESET_FILE" 2>/dev/null || true)"
    fi
    apply_filter_preset "$preset"
}

set_wallhaven_filters() {
    local choice preset
    local menu
    menu="$(printf '%s\n' \
        "Desktop (16:9 only)" \
        "Screen-fit (16:9 + >=1080p)" \
        "Web-like (any size/ratio)")"
    choice="$(printf '%s\n' "$menu" \
        | wofi --dmenu --cache-file=/dev/null --prompt "Wallhaven filters" || true)"
    [ -z "$choice" ] && return

    case "$choice" in
        "Desktop (16:9 only)")          preset="desktop-16x9" ;;
        "Screen-fit (16:9 + >=1080p)")  preset="screen-fit"   ;;
        "Web-like (any size/ratio)")    preset="any"           ;;
        *)                              return                 ;;
    esac

    apply_filter_preset "$preset"
    printf '%s\n' "$preset" > "$FILTER_PRESET_FILE" 2>/dev/null || true
}

wofi_error() {
    if command -v notify-send &>/dev/null; then
        notify-send "Wallpaper Manager" "$1" || true
    else
        echo "ERROR: $1" >&2
    fi
}

prompt_wallhaven_query() {
    local history_file="$QUERY_HISTORY_FILE"
    touch "$history_file"
    local suggestions
    suggestions="$(tac "$history_file" 2>/dev/null | awk 'NF && !seen[$0]++ {print} NR>=50 {exit}')"
    printf '%s\n' "$suggestions" \
        | wofi --dmenu --insensitive --cache-file=/dev/null --prompt "Wallhaven search" || true
}

wallhaven_fetch_json() {
    local query="${1:-}"
    local page="${2:-1}"
    local sorting="${3:-relevance}"
    local top="${4-}"
    local url

    url="$(build_wallhaven_url "$query" "$sorting" "$top" "$page")"
    curl -sL --fail "$url" || true
}

wallhaven_validate_json_or_error() {
    local json="$1"
    echo "$json" | jq -e '.data and (.data|type=="array")' >/dev/null 2>&1 || {
        wofi_error "Wallhaven request failed (check network / API)."
        return 1
    }
}

wallhaven_download_thumb() {
    local id="$1"
    local url="$2"
    local file="$THUMBS/$id.jpg"
    [ ! -f "$file" ] && curl -sL "$url" -o "$file"
    echo "$file"
}

wallhaven_wofi_select() {
    local json="$1"
    local query="$2"
    local page="$3"
    local prompt="$4"

    local entries=""

    # Build all wallpaper entries first so wofi opens at the correct height
    while IFS="|" read -r id thumb full; do
        icon="$(wallhaven_download_thumb "$id" "$thumb")"
        entries+="$(printf 'img:%s:text:%s\n' "$icon" "$id")"$'\n'
    done < <(echo "$json" | jq -r '.data[] | "\(.id)|\(.thumbs.small)|\(.path)"')

    # Always emit BOTH nav buttons so their grid position never shifts.
    # The caller guards against going below page 1.
    entries+="$(printf 'img:%s:text:%s\n' "$NAV_PREV" "󰁍 Previous Page")"$'\n'
    entries+="$(printf 'img:%s:text:%s\n' "$NAV_NEXT" "󰁔 Next Page")"$'\n'

    printf '%s' "$entries" \
        | wofi --dmenu --allow-images --cache-file=/dev/null \
               --define dmenu-parse_action=true \
               --define image_size=200 \
               --columns 4 --lines 3 \
               --style "$WOFI_CSS" \
               --prompt "$prompt [$query p$page]" || true
}

wallhaven_full_url_for_id() {
    local json="$1"
    local id="$2"
    echo "$json" | jq -r ".data[] | select(.id==\"$id\") | .path"
}

wallhaven_browse() {
    local mode="$1"
    local query="${2:-}"
    local sorting="${3:-relevance}"
    local top="${4-}"
    local page=1
    local prompt

    prompt="Wallhaven"
    [[ "$mode" == "download" ]] && prompt="Download Wallpaper"

    while true; do
        local json selection wall file

        json="$(wallhaven_fetch_json "$query" "$page" "$sorting" "$top")"
        wallhaven_validate_json_or_error "$json" || return

        selection="$(wallhaven_wofi_select "$json" "$query" "$page" "$prompt")"
        [ -z "$selection" ] && return

        case "$selection" in
            "󰁔 Next Page")
                page=$((page + 1))
                continue
                ;;
            "󰁍 Previous Page")
                [ "$page" -gt 1 ] && page=$((page - 1))
                continue
                ;;
        esac

        wall="$(wallhaven_full_url_for_id "$json" "$selection")"
        [ -z "$wall" ] && return

        if [[ "$mode" == "preview" ]]; then
            file="$TMP_WALLS/wallhaven-$selection.jpg"
            [ ! -f "$file" ] && curl -fL "$wall" -o "$file"
            echo "$selection" > "$SELECTED_FILE"
            pkill swaybg && swaybg -m fill -i "$file" & disown
        else
            file="$LOCAL_DIR/wallhaven-$selection.jpg"
            [ ! -f "$file" ] && curl -fL "$wall" -o "$file"
        fi

        return
    done
}

wallhaven_menu() {
    local mode="$1"
    local query="${2:-}"
    local choice sorting top

    while true; do
        local menu
        menu="$(printf '%s\n' \
            "Relevance/Search" \
            "Toplist / 1 Month" \
            "Toplist / 6 Months" \
            "Toplist / 1 Year" \
            "Views")"
        choice="$(printf '%s\n' "$menu" \
            | wofi --dmenu --insensitive --cache-file=/dev/null \
                   --prompt "Sorting ($(filters_label))" || true)"
        [ -z "$choice" ] && return

        case "$choice" in
            "Relevance/Search")
                sorting="relevance"
                top=""
                query="$(prompt_wallhaven_query)"
                [ -z "$query" ] && continue
                printf '%s\n' "$query" >> "$QUERY_HISTORY_FILE" 2>/dev/null || true
                ;;
            "Toplist / 1 Month")  sorting="toplist"; top="1M"; query="" ;;
            "Toplist / 6 Months") sorting="toplist"; top="6M"; query="" ;;
            "Toplist / 1 Year")   sorting="toplist"; top="1y"; query="" ;;
            "Views")              sorting="views";   top="";   query="" ;;
            *)                    continue                               ;;
        esac

        wallhaven_browse "$mode" "$query" "$sorting" "$top"
    done
}

change_wallpaper() {
    local menu="" file selected

    while IFS= read -r file; do
        menu+="$(printf 'img:%s:text:%s\n' "$file" "$file")"$'\n'
    done < <(find "$LOCAL_DIR" -type f \( -iname "*.jpg" -o -iname "*.png" \) | sort)

    selected="$(
        printf '%s' "$menu" \
            | wofi --dmenu --allow-images --cache-file=/dev/null \
                   --define dmenu-parse_action=true \
                   --define image_size=200 \
                   --columns 4 --lines 3 \
                   --style "$WOFI_CSS" \
                   --prompt "Change Wallpaper" || true
    )"

    if [ -n "$selected" ]; then
        pkill swaybg && swaybg -m fill -i "$selected" & disown
        echo "$selected" > "$CURRENT_FILE"
        exit 0
    fi
}

download_selected() {
    local selection src
    [ ! -f "$SELECTED_FILE" ] && { echo "No wallpaper selected"; return; }
    selection=$(cat "$SELECTED_FILE")
    src="$TMP_WALLS/wallhaven-$selection.jpg"
    [ ! -f "$src" ] && { echo "Selected wallpaper not found"; return; }
    cp "$src" "$LOCAL_DIR/"
    echo "Downloaded: wallhaven-$selection.jpg"
}

main_menu() {
    local menu
    menu="$(printf '%s\n' \
        "Change Wallpaper" \
        "Wallhaven Filters" \
        "Preview Wallpaper" \
        "Download Wallpaper" \
        "Download Selected Wallpaper")"
    printf '%s\n' "$menu" \
        | wofi --dmenu --insensitive --cache-file=/dev/null \
               --prompt "Wallpaper Manager" || true
}

# --- MAIN ---

load_filter_preset

while true; do
    ACTION="$(main_menu)" || true
    [ -z "$ACTION" ] && exit 0

    case "$ACTION" in
        "Wallhaven Filters")           set_wallhaven_filters  ;;
        "Change Wallpaper")            change_wallpaper        ;;
        "Preview Wallpaper")           wallhaven_menu preview  ;;
        "Download Wallpaper")          wallhaven_menu download ;;
        "Download Selected Wallpaper") download_selected       ;;
    esac
done
