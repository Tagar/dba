" F2 Top of document
nmap <F2> 1G

" F3 Bottom of document
nmap <F3> G

" F4 Show line numbers
nmap <F4> :set number<CR>

" F5 Set Case Insensitive searching
nmap <F5> :set ic<CR>

" F6 Display aditto style column numbers line
nmap <F6> :r /home/abacus/bytes142<CR>

" F7 Make current position the end of the line when in REPLACE mode
inoremap <F7> <ESC>lD

" F8 Quit without writing
nmap <F8> :q!<CR>

" F9 Quit with write
nmap <F9> ZZ<CR>

" F10 Change case of current character
nmap <F10> ~

set showmode

" do not create .swp files
set updatecount=0

" RD - added on 8/27/2014
:color desert

" Do NOT highlight matching pairs of braces, parentheses and brackets
" having this behavior present using cmdtools causes seeming jumps between pairs
" Could be removed once cmdtools no longer available under Solaris10
hi clear MatchParen

" setting mouse=a enables scroll button and point/click positioning plus
" but selecting text puts user in visual mode; must shift-select to copy and paste within vim
" and is awkward to leave visual mode
"if &term=="xterm"
    "set mouse=a
"endif
