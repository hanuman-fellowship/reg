set ai sw=4 ts=4 aw et sm
set viminfo=%,'1000,f1
map X :!clear;/usr/bin/perl %
map K :'a,.w! /tmp/t
map V :r /tmp/t
map Y 0i<h2>A</h2>
" set stl=%o
" set laststatus=2
if has("autocmd")
  au BufReadPost * if line("'\"") > 0 && line("'\"") <= line("$") | exe "normal! g`\"" | endif
endif
