" Source vimrc on vim startup
" autocmd! VimEnter * source ~/.vimrc

" Load rename plugin
" so ~/.vim/Rename.vim

" let g:EclimCompletionMethod = 'omnifunc'
" Java Autocomplete
" let g:acp_behaviorJavaEclimLength=3
" function MeetsForJavaEclim(context)
"   return g:acp_behaviorJavaEclimLength >= 0 &&
"         \ a:context =~ '\k\.\k\{' . g:acp_behaviorJavaEclimLength . ',}$'
" endfunction
" let g:acp_behavior = {
"     \ 'java': [{
"       \ 'command': "\<c-x>\<c-u>",
"       \ 'completefunc' : 'eclim#java#complete#CodeComplete',
"       \ 'meets'        : 'MeetsForJavaEclim',
"     \ }]
"   \ }

" Rezise splits
"nnoremap <C-Left> :vertical resize -20<CR>


" Autoindent html
" autocmd BufWritePre *.html :normal gg=G

" Remove spaces at end of lines
autocmd BufWritePre * %s/\s\+$//e

" Fold all with leader + f
nnoremap <Leader>f :call ToggleFold()<CR>

" Set relative line number and number to see current line number
" set rnu
set number
" Show commands as being written
set showcmd

" Set syntastic settings
set statusline+=%#warningmsg#
if exists("SyntasticStatuslineFlag")
    set statusline+=%{SyntasticStatuslineFlag()}
endif
set statusline+=%*

" Disables syntastic popup window with messages
" Set both to 1 to turn it on
let g:syntastic_always_populate_loc_list = 0
let g:syntastic_auto_loc_list = 0
let g:syntastic_check_on_open = 0
let g:syntastic_python_checkers = ['flake8']

nnoremap <F10> :SyntasticCheck mypy<CR>
" Set xptemplate trigger key to tab
let g:xptemplate_key = '<Tab>'

" Autocomplete with Tab
" inoremap <Tab> <C-x><Space><CR>
"inoremap <Caps> <space><space><space><space>


" Python main method snippet
"let g:xptemplate_brace_complete = '([{<'
let g:xptemplate_minimal_prefix = 1
" let g:xptemplate_vars="$author=viktor.barzin"
" let g:xptemplate_vars="$email=viktor.barzin@samitor.com"

" Rebind <Leader> key
" I like to have it here becuase it is easier to reach than the default and
" it is next to ``m`` and ``n`` which I use for navigating between tabs.
let mapleader = ","

" Swap lines
nnoremap <Leader>k :-1,-1m+0<CR>k
nnoremap <Leader>j :+0,+0m+1<CR>
vnoremap <Leader>k :m '<-2<CR>gv=gv
vnoremap <Leader>j :m '>+1<CR>gv=gv

" Enable folding with spacebar
nnoremap <space> za

" Make surrounding with various characters easier
nmap <Leader>' ysiW'
nmap <Leader>" ysiW"
nmap <Leader>0 ysiW)

" Go to normal mode by tapping jk or kj
inoremap kj <Esc>
inoremap jk <Esc>

" Easier buffer closing
nnoremap <Leader>q :bd<CR>

" Swap to previous buffer
nnoremap <Leader><Tab> :b#<CR>

" Map backspace to delete
nnoremap <BS> h<DEL>
vnoremap <BS> d

" Save with <Leader>s
noremap <silent> <Leader>s :update<CR>
" Sudo save with <Leader>S
noremap <silent> <Leader>S :w !sudo tee % > /dev/null<CR>

" Writes to all buffers when switching to another buffer
set autowrite

" Enable virtualenv
let g:airline#extensions#virtualenv#enabled = 1
" Enable tabs plugin
let g:airline#extensions#tabline#enabled = 1
let g:airline#extensions#tabline#left_sep = ' '
let g:airline#extensions#tabline#left_alt_sep = '|'
" let g:airline_left_sep='>'
" let g:airline_right_sep='<'
" let g:airline_detect_modified=1
let g:airline_powerline_fonts=1
" let g:airline_section_b = '%{strftime("%c")}'
" let g:airline_section_y = 'BN: %{bufnr("%")} FT: %y'

" Enable wildmenu which is an enhanced  command completion
"
set wildmenu
" Better copy & paste
" When you want to paste large blocks of code into vim, press F2 before you
" paste. At the bottom you should see ``-- INSERT (paste) --``.

set pastetoggle=<F2>
set clipboard=unnamed

" Mouse and backspace
set mouse=a  " on OSX press ALT and click
set bs=2     " make backspace behave like normal again

" Remember the cursor last position
if has("autocmd")
    au BufReadPost * if line("'\"") > 1 && line("'\"") <= line("$") | exe "normal! g'\"" | endif
endif

" Set comment string for commentary.vim for python
set commentstring=#%s

" I no longer use that because emmet.vim does all I need
""Auto complete HTLM tags
"function! s:CompleteTags()
"  inoremap <buffer> > ></<C-x><C-o><Esc>:startinsert!<CR><C-O>?</<CR>
"  inoremap <buffer> ><Leader> >
"  inoremap <buffer> ><CR> ></<C-x><C-o><Esc>:startinsert!<CR><C-O>?</<CR><CR><Tab><CR><Up><C-O>$
"endfunction

"autocmd BufRead,BufNewFile *.html,*.js,*.xml call s:CompleteTags()

" Sources $MYVIMRC on changes
" augroup reload_vimrc " {
"     autocmd!
"     autocmd BufWritePost $MYVIMRC source $MYVIMRC
" augroup END " }


" Set VIMHOME
if has('win32') || has ('win64')
        let $VIMHOME = $VIM."/vimfiles"
    else
        let $VIMHOME = $HOME."/.vim"
    endif


" Bind nohl
" Removes highlight of your last search
" ``<C>`` stands for ``CTRL`` and therefore ``<C-n>`` stands for ``CTRL+n``
noremap <F3> :nohl<CR>
vnoremap <F3> :nohl<CR>
"inoremap <C-n> :nohl<CR>
noremap <F5> :syntax sync fromstart<CR>
vnoremap <F5> :syntax sync fromstart<CR>

" Tab switching
noremap<C-tab> :b#
vnoremap <C-tab> :b#
"inoremap <C-n> :b#


" Quicksave command
" noremap <C-Z> :update<CR>
" vnoremap <C-Z> <C-C>:update<CR>
" inoremap <C-Z> <C-O>:update<CR>

" Execute current file with python
noremap <Leader>e :!python %<CR>

" bind Ctrl+<movement> keys to move around the windows, instead of using
" Ctrl+w + <movement>
" Every unnecessary keystroke that can be saved is good for your health :)
map <c-j> <c-w>j
map <c-k> <c-w>k
map <c-l> <c-w>l
map <c-h> <c-w>h

" easier moving between tabs
map <Leader>m <esc>:bn<CR>
map <Leader>n <esc>:bp<CR>

" Create empty buffer and open it
map <Leader>t <esc>:enew<CR>


" map sort function to a key
vnoremap <Leader>s :sort<CR>

" easier moving of code blocks
" Try to go into visual mode (v), thenselect several lines of code here and
" then press ``>`` several times.
vnoremap < <gv  " better indentation
vnoremap > >gv  " better indentation

" Show whitespace
" MUST be inserted BEFORE the colorscheme command
autocmd ColorScheme * highlight ExtraWhitespace ctermbg=red guibg=red
au InsertLeave * match ExtraWhitespace /\s\+$/

" Color scheme
" mkdir -p ~/.vim/colors && cd ~/.vim/colors
" wget -O wombat256mod.vim
"  http://www.vim.org/scripts/download_script.php?src_id=13400
set t_Co=256
color wombat256mod
" color ronakg
" color mayansmoke
" color github

" Spelling
" set spell
" set complete+=kpspell

" Enable syntax highlighting
" You need to reload this file for the change to apply
filetype off
filetype plugin indent on
syntax on

" Ignore flake8 E501 for lines longer than 80 characters
" E128 - visual continuation
" W391 - blank line at end of file
" let g:syntastic_python_flake8_args='--ignore=W391, E501, E701, E702'
" let g:syntastic_python_flake8_show_quickfix=1
let g:pymode_lint_ignore="E501,W601,W391,W0401,E702,E701"
let g:pymode_lint_settingscwindow = 1
let g:pymode_rope = 1
" let g:pymode_rope_autoimport = 0
let g:pymode_rope_regenerate_on_write = 0
let g:pymode_python="python3"
let g:pymode_lint_checkers = ['pep8']
let g:pymode_breakpoint_cmd = 'import ipdb; ipdb.set_trace() # XXX BREAKPOINT'
let g:pymode_rope_completion = 1

" Make quickfix screen smaller
let g:syntastic_loc_list_height=1

" In visual mode searches for the selected word
vnoremap // y/<C-R>"<CR>

" Showing line numbers and length
set tw=79   " width of document (used by gd)
set nowrap  " don't automatically wrap on load
set fo-=t   " don't automatically wrap text when typing
set colorcolumn=120
highlight ColorColumn ctermbg=233

" Useful settings
set history=700
set undolevels=700

" Real programmers don't use TABs but spaces
set tabstop=4
set softtabstop=4
set shiftwidth=4
set shiftround
set expandtab

" Make search case insensitive
set hlsearch
set incsearch
set ignorecase
set smartcase

" Disable stupid backup and swap files - they trigger too many events
" for file system watchers
"set nobackup
"set nowritebackup
"set noswapfile

" Backup files are great so lets keep them in 1 place
" Make sure you have ~/vimtmp/ folder. In the future will
" move /vimtmp/ in $VIMHOME
set backupdir=~/.vim/tmp//,.
set directory=~/.vim/tmp//,.
set dir=~/.vim/tmp//,.
set undodir=~/.vim/tmp/undo//


" Setup Pathogen to manage your plugins
" mkdir -p ~/.vim/autoload ~/.vim/bundle
" curl -so ~/.vim/autoload/pathogen.vim
" https://raw.githubusercontent.com/tpope/vim-pathogen/master/autoload/pathogen.vim
" Now you can install any plugin into a .vim/bundle/plugin-name/ folder

" Pathogen does not work in combatability mode so disable
set nocp
" let g:pathogen_disabled = ["syntastic"]
call pathogen#infect()


"
"============================================================================
" Python IDE Setup
"
"============================================================================


" Settings for vim-powerline
" cd ~/.vim/bundle
" git clone git://github.com/Lokaltog/vim-powerline.git
set laststatus=2


" Settings for ctrlp
" cd ~/.vim/bundle
" git clone https://github.com/kien/ctrlp.vim.git
let g:ctrlp_max_height = 30
let g:ctrlp_working_path_mode = 'ar'
set wildignore+=*.pyc
set wildignore+=*_build/*
set wildignore+=*/coverage/*


" Settings for python-mode
" Note: I'm no longer using this. Leave this commented out
" and uncomment the part about jedi-vim instead
" cd ~/.vim/bundle
" git clone https://github.com/klen/python-mode
"" map <Leader>g :call RopeGotoDefinition()<CR>
"" let ropevim_enable_shortcuts = 1
"" let g:pymode_rope_goto_def_newwin = "vnew"
"" let g:pymode_rope_extended_complete = 1
"" let g:pymode_breakpoint = 0
"" let g:pymode_syntax = 1
"" let g:pymode_syntax_builtin_objs = 0
"" let g:pymode_syntax_builtin_funcs = 0
"" map <Leader>b Oimport ipdb; ipdb.set_trace() # BREAKPOINT<C-c>
" let g:SuperTabDefaultCompletionType = "<c-p>"
" Settings for jedi-vim
" cd ~/.vim/bundle
" git clone git://github.com/davidhalter/jedi-vim.git
" let g:jedi#usages_command = "<leader>z"
" let g:jedi#popup_on_dot = 1
" let g:jedi#popup_select_first = 0
" let g:jedi#force_py_version = 3
" let g:jedi#completions_command = '.'
" let g:jedi#show_call_signatures = 1
" map <Leader>b Oimport ipdb; ipdb.set_trace() # BREAKPOINT<C-c>

" Map C-a to select entire file
"nnoremap <C-a> ggVG

" Real vimmers dont use those
noremap <Up> <NOP>
noremap <Down> <NOP>
noremap <Left> <NOP>
noremap <Right> <NOP>

" Do splits with Leader-\ and Leader--
" nnoremap <silent> <C-Right> :vsp<CR>
" nnoremap <silent> <C-Up> :sp<CR>
noremap <leader>\ :vsp<CR>
noremap <leader>- :sp<CR>

" NERDTree settings
" Open NERDTree by default
"autocmd VimEnter * NERDTree
"autocmd VimEnter * wincmd p
" Toggle NEDRTree plugin
noremap <C-b> :NERDTreeToggle<CR>
let NERDTreeIgnore = ['\.pyc$', '__pycache__']
let NERDTreeShowHidden=1

" Better navigating through omnicomplete option list
" See
"http://stackoverflow.com/questions/2170023/how-to-map-keys-for-popup-menu-in-vim
set completeopt=longest,menuone
function! OmniPopup(action)
    if pumvisible()
        if a:action == 'j'
            return "\<C-N>"
        elseif a:action == 'k'
            return "\<C-P>"
        endif
    endif
    return a:action
endfunction

"inoremap <silent><C-j> <C-R>=OmniPopup('j')<CR>
"inoremap <silent><C-k> <C-R>=OmniPopup('k')<CR>
set omnifunc=jedi#completions
:"py3 import sys; sys.path[2]='/root/.virtualenvs/django/bin/python'
" set omnifunc=syntaxcomplete#Complete

" Python folding
" mkdir -p ~/.vim/ftplugin
" wget -O ~/.vim/ftplugin/python_editing.vim
"http://www.vim.org/scripts/download_script.php?src_id=5492
set foldenable

" Auto activate virtual enviorment
let g:virtualenv_auto_activate = 1

" Keep undo history even after closing file
set undofile

" Setups template files (more on this - https://shapeshed.com/vim-templates/)
if has("autocmd")
  augroup templates
    autocmd BufNewFile *.py 0r ~/.vim/templates/skeleton.py
    autocmd BufNewFile *.sh 0r ~/.vim/templates/skeleton.sh
  augroup END
endif

" comment out highlighted lines according to file type
" put a line like the following in your ~/.vim/filetype.vim file
" and remember to turn on filetype detection: filetype on
" au! BufRead,BufNewFile *.sh,*.tcl,*.php,*.pl let Comment="#"
" if the comment character for a given filetype happens to be @
" then use let Comment="\@" to avoid problems...
function! CommentLines()
  "let Comment="#" " shell, tcl, php, perl
  exe ":s@^@".g:Comment."@g"
  exe ":s@$@".g:EndComment."@g"
endfunction
" map visual mode keycombo 'co' to this function
vmap co :call CommentLines()<CR>

" Encryption algo (vim -x file)
set cm=blowfish2

" Improve perfomance with long lines
set synmaxcol=200

set autoread

" Autosave
" augroup autoSaveAndRead
"     autocmd!
"     autocmd TextChanged,InsertLeave,FocusLost * silent! wall
"     autocmd CursorHold * silent! checktime
" augroup END

" Lion alignment operator config (see https://github.com/tommcdo/vim-lion)
let b:lion_squeeze_spaces = 1

set showmatch
set matchtime=3

" Fold functions in bash
let g:sh_fold_enabled=3


" Recompute syntax highlighting
nnoremap <silent> <F4> :syntax sync fromstart<CR>

autocmd FileType markdown syntax sync fromstart

set cursorline
set scrolloff=3
set sidescrolloff=3

" Easier line joining
if v:version > 703 || v:version == 703 && has('patch541')
  set formatoptions+=j
endif

set relativenumber

nnoremap <leader>Q :qa<CR>

" Remap ; to be : - save 1 key press :P
nnoremap ; :
nnoremap : ;
