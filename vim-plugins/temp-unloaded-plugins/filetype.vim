au BufRead,BufNewFile *.inc,*.ihtml,*.tpl,*.class set filetype=php
        \ | let Comment="<!-- " | let EndComment=" -->"
au BufRead,BufNewFile *.py,*.sh,*.pl,*.tcl let Comment="#" | let EndComment=""
au BufRead,BufNewFile *.js set filetype=html | let Comment="//" | let EndComment=""
au BufRead,BufNewFile *.cc,*.php,*.cxx let Comment="//" | let EndComment=""
au BufRead,BufNewFile *.c,*.h let Comment="/*" | let EndComment="*/"
au BufRead,BufNewFile *.html let Comment="{#" | let EndComment="%}" | set filetype=htmldjango
