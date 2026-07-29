" I didn't make this config, I just copied some stuff that I consider useful.
" The original git repo I got this config off is
" https://github.com/amix/vimrc

set number

" Enable filetype plugins
filetype plugin on
filetype indent on


" Set to auto read when a file is changed from the outside
set autoread
au FocusGained,BufEnter * silent! checktime


" :W sudo saves the file
" (useful for handling the permission-denied error)
command! W execute 'w !sudo tee % > /dev/null' <bar> edit!

" Always show current position
set ruler


" Configure backspace so it acts as it should act
set backspace=eol,start,indent
set whichwrap+=<,>,h,l


" Ignore case when searching
set ignorecase

" When searching try to be smart about cases
set smartcase


" Highlight search results
set hlsearch


" Don't redraw while executing macros (good performance config)
set lazyredraw

" Enable syntax highlighting
syntax enable

" Turn backup off, since most stuff is in SVN, git etc. anyway...
set nobackup
set nowb
set noswapfile


" Use spaces instead of tabs
set expandtab

" Be smart when using tabs ;)
set smarttab



