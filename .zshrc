HISTFILE=~/.cache/.histfile
HISTSIZE=1000
SAVEHIST=1000
# End of lines configured by zsh-newuser-install


# The following lines were added by compinstall

#zstyle ':completion:*' completer _expand _complete _ignored _correct _approximate
#zstyle :compinstall filename '/home/alex/.zshrc'

autoload -Uz compinit
compinit
# End of lines added by compinstall

source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

autoload -U colors && colors
#PS1="[%{$fg[red]%}%n%{$fg[white]%}@%{$fg[white]%}%M %{$fg[cyan]%}%1~%{$fg[white]%}]%{$reset_color%}$ "
#PS1="%{$(tput setaf 196)%}%n%{$(tput setaf 207)%}@%{$(tput setaf 208)%}%m %{$(tput setaf 220)%}%1~ %{$(tput sgr0)%}> "
PS1="%{$(tput setaf 203)%}%n%{$(tput setaf 255)%}@%{$(tput setaf 6)%}%m %{$(tput setaf 172)%}%1~>%{$(tput sgr0)%} "

alias nano="vim"
alias ls="ls -l -h --color=auto"
alias sx="startx"
alias ani-cli='ani-cli --rofi --dub'
alias weather='curl wttr.in'
alias ff="fastfetch --config examples/10"
alias nervfetch="fastfetch --config examples/31"
alias mangoconf="vim ~/.config/mango/config.conf"
alias m='mango'
