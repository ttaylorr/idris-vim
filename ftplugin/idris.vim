if bufname('%') == "idris-response"
  finish
endif

if exists("b:did_ftplugin")
  finish
endif

if !has("job")
  echo "Cannot load idris.vim without jobs"
endif

let b:client = job_start("idris --ide-mode")
let b:channel = job_getchannel(b:client)
let b:debug = 1
let b:version = ch_readraw(b:channel)

setlocal shiftwidth=2
setlocal tabstop=2
if !exists("g:idris_allow_tabchar") || g:idris_allow_tabchar == 0
	setlocal expandtab
endif
setlocal comments=s1:{-,mb:-,ex:-},:\|\|\|,:--
setlocal commentstring=--%s
setlocal iskeyword+=?
setlocal wildignore+=*.ibc

let idris_response = 0
let b:did_ftplugin = 1

" Text near cursor position that needs to be passed to a command.
" Refinment of `expand(<cword>)` to accomodate differences between
" a (n)vim word and what Idris requires.
function! s:currentQueryObject()
  let word = expand("<cword>")
  if word =~ '^?'
    " Cut off '?' that introduces a hole identifier.
    let word = strpart(word, 1)
  endif
  return word
endfunction

function! s:IdrisCommand(sexp)
  let str = printf("(%s 1)\n", a:sexp)
  let header = printf("%06x", len(str))

  let msg = printf("%s%s", header, str)
  if b:debug
    echo printf("-> %s", msg)
  endif

  call ch_sendraw(b:channel, msg)
endfunction

function! s:IdrisResponse()
  let responses = [Sexp(ch_read(b:channel)[6:])]

  while responses[len(responses)-1][0] != ':return'
    let responses = responses + [Sexp(ch_read(b:channel)[6:])]
  endwhile
  return responses
endfunction

function! s:IdrisReturn()
  let response = s:IdrisResponse()
  return response[len(response) - 1]
endfunction

function! IdrisDocFold(lineNum)
  let line = getline(a:lineNum)

  if line =~ "^\s*|||"
    return "1"
  endif

  return "0"
endfunction

function! IdrisFold(lineNum)
  return IdrisDocFold(a:lineNum)
endfunction

setlocal foldmethod=expr
setlocal foldexpr=IdrisFold(v:lnum)

function! IdrisResponseWin()
  if (!bufexists("idris-response"))
    botright 10split
    badd idris-response
    b idris-response
    let g:idris_respwin = "active"
    set buftype=nofile
    wincmd k
  elseif (bufexists("idris-response") && g:idris_respwin == "hidden")
    botright 10split
    b idris-response
    let g:idris_respwin = "active"
    wincmd k
  endif
endfunction

function! IdrisHideResponseWin()
  let g:idris_respwin = "hidden"
endfunction

function! IdrisShowResponseWin()
  let g:idris_respwin = "active"
endfunction

function! IWrite(str)
  if (bufexists("idris-response"))
    let save_cursor = getcurpos()
    b idris-response
    %delete
    let resp = split(a:str, '\n')
    call append(1, resp)
    b #
    call setpos('.', save_cursor)
  else
    echo a:str
  endif
endfunction

function! IdrisReload(q)
  silent w

  let file = expand("%:p")

  call s:IdrisCommand(printf("(:load-file \"%s\")", file))
  let tc = s:IdrisReturn()

  if tc[1][0] == ":ok"
    if (a:q==0)
       echo "Successfully reloaded " . file
       call IWrite("")
    endif
  else
    call IWrite(tc)
  endif

  return ""
endfunction

function! IdrisReloadToLine(cline)
  return IdrisReload(1)
  "w
  "let file = expand("%:p")
  "let tc = s:IdrisCommand(":lto", a:cline, file)
  "if (! (tc is ""))
  "  call IWrite(tc)
  "endif
  "return tc
endfunction

function! Sexp(str)
  let str = a:str
  let str = substitute(str, "(", " ( ", "g")
  let str = substitute(str, ")", " ) ", "g")

  return Parenthesize(split(str, '\s\+'), [])[0]
endfunction

function! Parenthesize(input, list)
  if len(a:input) == 0
    return a:list
  endif

  let token = remove(a:input, 0)

  if token == "("
    call add(a:list, Parenthesize(a:input, []))
    return Parenthesize(a:input, a:list)
  elseif token == ")"
    return a:list
  else
    return Parenthesize(a:input, a:list + [token])
  endif
endfunction

function! IdrisShowType()
  silent w

  let word = s:currentQueryObject()
  let cline = line(".")

  let tc = IdrisReloadToLine(cline)
  if (! (tc is ""))
    echo tc
    return tc
  endif

  call s:IdrisCommand(printf("(:type-of \"%s\")", word))
  echo s:IdrisResponse()
  " echo s:IdrisReturn()

  return
endfunction

function! IdrisShowDoc()
  w
  let word = expand("<cword>")
  let ty = s:IdrisCommand("docs-for", word)
  call IWrite(ty)
endfunction

function! IdrisProofSearch(hint)
  let view = winsaveview()
  w
  let cline = line(".")
  let word = s:currentQueryObject()
  let tc = IdrisReload(1)

  if (a:hint==0)
     let hints = ""
  else
     let hints = input ("Hints: ")
  endif

  if (tc is "")
    let result = s:IdrisCommand("proof-search", printf("%s %s %s", cline, word, hints))
    if (! (result is ""))
       call IWrite(result)
    else
      e
      call winrestview(view)
    endif
  endif
endfunction

function! IdrisMakeLemma()
  let view = winsaveview()
  w
  let cline = line(".")
  let word = s:currentQueryObject()
  let tc = IdrisReload(1)

  if (tc is "")
    let result = s:IdrisCommand("make-lemma", printf("%s %s", cline, word))
    if (! (result is ""))
       call IWrite(result)
    else
      e
      call winrestview(view)
      call search(word, "b")
    endif
  endif
endfunction

function! IdrisRefine()
  let view = winsaveview()
  w
  let cline = line(".")
  let word = expand("<cword>")
  let tc = IdrisReload(1)

  let name = input ("Name: ")

  if (tc is "")
    let result = s:IdrisCommand(":ref!", cline, word, name)
    if (! (result is ""))
       call IWrite(result)
    else
      e
      call winrestview(view)
    endif
  endif
endfunction

function! IdrisAddMissing()
  let view = winsaveview()
  w
  let cline = line(".")
  let word = expand("<cword>")
  let tc = IdrisReload(1)

  if (tc is "")
    let result = s:IdrisCommand("add-missing", printf("%s %s", cline, word))
    if (! (result is ""))
       call IWrite(result)
    else
      e
      call winrestview(view)
    endif
  endif
endfunction

function! IdrisCaseSplit()
  let view = winsaveview()
  let cline = line(".")
  let word = expand("<cword>")
  let tc = IdrisReloadToLine(cline)

  if (tc is "")
    let result = s:IdrisCommand("case-split", printf("%s %s", cline, word))
    if (! (result is ""))
       call IWrite(result)
    else
      e
      call winrestview(view)
    endif
  endif
endfunction

function! IdrisMakeWith()
  let view = winsaveview()
  w
  let cline = line(".")
  let word = s:currentQueryObject()
  let tc = IdrisReload(1)

  if (tc is "")
    let result = s:IdrisCommand("make-with", printf("%s %s", cline, word))
    if (! (result is ""))
       call IWrite(result)
    else
      e
      call winrestview(view)
      call search("_")
    endif
  endif
endfunction

function! IdrisMakeCase()
  let view = winsaveview()
  w
  let cline = line(".")
  let word = s:currentQueryObject()
  let tc = IdrisReload(1)

  if (tc is "")
    let result = s:IdrisCommand("make-case", printf("%s %s", cline, word))
    if (! (result is ""))
       call IWrite(result)
    else
      e
      call winrestview(view)
      call search("_")
    endif
  endif
endfunction

function! IdrisAddClause(proof)
  let view = winsaveview()
  w
  let cline = line(".")
  let word = expand("<cword>")
  let tc = IdrisReloadToLine(cline)

  if (tc is "")
    if (a:proof==0)
      let fn = "add-clause"
    else
      let fn = "add-proof-clause"
    endif

    let result = s:IdrisCommand(fn, printf("%s %s", cline, word))
    if (! (result is ""))
       call IWrite(result)
    else
      e
      call winrestview(view)
      call search(word)

    endif
  endif
endfunction

function! IdrisVersion()
  call s:IdrisCommand(":version")
  echo s:IdrisResponse()
endfunction

" function! IdrisEval()
"   w
"   let tc = IdrisReload(1)
"   if (tc is "")
"      let expr = input ("Expression: ")
"      let result = s:IdrisCommand(expr)
"      call IWrite(" = " . result)
"   endif
" endfunction

nnoremap <buffer> <silent> <LocalLeader>t :call IdrisShowType()<ENTER>
nnoremap <buffer> <silent> <LocalLeader>r :call IdrisReload(0)<ENTER>
nnoremap <buffer> <silent> <LocalLeader>c :call IdrisCaseSplit()<ENTER>
nnoremap <buffer> <silent> <LocalLeader>d 0:call search(":")<ENTER>b:call IdrisAddClause(0)<ENTER>w
nnoremap <buffer> <silent> <LocalLeader>b 0:call IdrisAddClause(0)<ENTER>
nnoremap <buffer> <silent> <LocalLeader>m :call IdrisAddMissing()<ENTER>
nnoremap <buffer> <silent> <LocalLeader>md 0:call search(":")<ENTER>b:call IdrisAddClause(1)<ENTER>w
nnoremap <buffer> <silent> <LocalLeader>f :call IdrisRefine()<ENTER>
nnoremap <buffer> <silent> <LocalLeader>o :call IdrisProofSearch(0)<ENTER>
nnoremap <buffer> <silent> <LocalLeader>p :call IdrisProofSearch(1)<ENTER>
nnoremap <buffer> <silent> <LocalLeader>l :call IdrisMakeLemma()<ENTER>
nnoremap <buffer> <silent> <LocalLeader>e :call IdrisEval()<ENTER>
nnoremap <buffer> <silent> <LocalLeader>w 0:call IdrisMakeWith()<ENTER>
nnoremap <buffer> <silent> <LocalLeader>mc :call IdrisMakeCase()<ENTER>
nnoremap <buffer> <silent> <LocalLeader>i 0:call IdrisResponseWin()<ENTER>
nnoremap <buffer> <silent> <LocalLeader>h :call IdrisShowDoc()<ENTER>
nnoremap <buffer> <silent> <LocalLeader>v :call IdrisVersion()<ENTER>

menu Idris.Reload <LocalLeader>r
menu Idris.Show\ Type <LocalLeader>t
menu Idris.Evaluate <LocalLeader>e
menu Idris.-SEP0- :
menu Idris.Add\ Clause <LocalLeader>d
menu Idris.Add\ with <LocalLeader>w
menu Idris.Case\ Split <LocalLeader>c
menu Idris.Add\ missing\ cases <LocalLeader>m
menu Idris.Proof\ Search <LocalLeader>o
menu Idris.Proof\ Search\ with\ hints <LocalLeader>p

au BufHidden idris-response call IdrisHideResponseWin()
au BufEnter idris-response call IdrisShowResponseWin()
