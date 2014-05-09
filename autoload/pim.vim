" global script variables

" path to master socket
let s:control_path = ''
" custom error messages
let s:errors = {
\ '4800': 'Unable to connect to gateway. Check that your credentials are valid.',
\ '4801': 'Something went wrong on the gateway.',
\ '4802': 'Unable to connect to gateway. No valid kerberos credentials.',
\ '4803': 'Unable to connect to gateway. Gateway unreachable.',
\ '4804': 'No master client connection to close.'
\ }
" keywords which will need to be sanitized
let s:triggers = [
\ 'describe', 'store', 'dump', 'stream', 'rmf', 'fs', 'rm', 'mkdir',
\ 'copyToLocal', 'copyFromLocal', 'mv', '--'
\ ]

"various helpers

function! s:tempname(extension)
  " return temporary filename for pig on gateway
  let hash = system("cat /dev/urandom | env LC_CTYPE=C tr -cd 'a-f0-9' | head -c 32")
  return 'tmp_' . hash . '.pim' . a:extension
endfunction

function! s:sanitize(contents, pretty)
  " remove trigger lines in pig script
  " TODO: split on ';' also
  let contents = filter(a:contents, 'v:val !~? ''\v^(' . join(s:triggers, '|') . ') ''')
  if a:pretty
    let contents = insert(contents, 'set pig.pretty.print.schema true;')
  endif
  return contents
endfunction

function! s:open_in_preview_window(contents, filetype)
  " open contents in preview window
  " contents must be a list of strings
  let local_tempname = tempname()
  call writefile(a:contents, local_tempname)
  silent execute 'pedit +setlocal\ filetype=' . a:filetype . '\ buftype=nofile\ bufhidden=wipe\ nobuflisted\ noswapfile ' . local_tempname
  call delete(local_tempname)
endfunction

" ssh session handling

function! s:has_kerberos_ticket(prompt)
  " check if user has valid kerberos ticket (optionally prompt if failed)
  " kerberos binaries don't seem to be in /usr/bin for everyone
  let kbin_dir = g:pim_kerberos_bin_dir
  echo 'Checking for kerberos ticket...'
  call system(kbin_dir . 'klist -s')
  if v:shell_error && a:prompt
    execute '!echo "Creating kerberos credentials..."; ' . kbin_dir . 'kinit'
    redraw!
  else
    " renew if possible in case ticket is outdated
    call system(kbin_dir . 'kinit -R')
  endif
  call system(kbin_dir . 'klist -s')
  return !v:shell_error
endfunction

function! s:open_master_client(prompt)
  " start master client that will multiplex all later ssh connections
  call s:close_master_client(1)
  let control_dir = expand($HOME) . '/.ssh/'
  if filewritable(control_dir) !=# 2
    call mkdir(control_dir, 'p')
  endif
  let s:control_path = control_dir . '/' . s:tempname('.sock')
  while filereadable(s:control_path)
    let s:control_path = control_dir . '/' . s:tempname('.sock')
  endwhile
  if s:has_kerberos_ticket(a:prompt)
    echo 'Initializing connection to gateway...'
    call system('ssh -qfKNMS ' . s:control_path . ' ' . g:pim_remote_url)
    if v:shell_error
      echoerr s:error[4003]
    endif
  else
    echoerr s:errors[4802]
  endif
  return v:shell_error
endfunction

function! s:close_master_client(silent)
  " close master client
  if strlen(s:control_path)
    let cmd = 'ssh -O exit -o "ControlPath=' . s:control_path . '" '
    call system(cmd . g:pim_remote_url)
    let s:control_path = ''
  elseif !a:silent
    echoerr s:error[4804]
  endif
endfunction

function! s:get_ssh_cmd(prompt, force_tty)
  " get parameterized ssh command
  " these connections are multiplexed off the master client and can therefore
  " be opened much faster and also consume less resources
  " force_tty can be used to force a controlling terminal, this will cause
  " remote commands to be stopped when closing the connection
  if strlen(s:control_path) || !s:open_master_client(a:prompt)
    if a:force_tty
      let cmd = 'ssh -tS '
    else
      let cmd = 'ssh -S '
    endif
    return cmd . s:control_path . ' ' . g:pim_remote_url
  else
    throw 'Unable to open ssh connection.'
  endif
endfunction

" remote commands

function! s:remote_system(cmd, contents, force_tty)
  " run command on gateway and capture output
  let ssh_cmd = s:get_ssh_cmd(1, a:force_tty)
  let cmd = ssh_cmd . " '" . a:cmd . "'"
  let shellredir_save = &shellredir
  let &shellredir = '>%s 2>&1'
  if len(a:contents)
    let output = system(cmd, join(a:contents, "\n"))
  else
    let output = system(cmd)
  endif
  let &shellredir = shellredir_save
  return output
endfunction

function! s:remote_execute(cmd, contents, force_tty)
  " run command on gateway using execute, any contents will be piped over
  " note that we don't use `:[RANGE]w !CMD` because it prevents jumping back
  " to the shell screen and thus would disable history scrolling
  let ssh_cmd = s:get_ssh_cmd(1, a:force_tty)
  if len(a:contents)
    if a:force_tty
      " need to do it in two passes
      let temppath = s:tempname('.pig')
      let output = s:remote_system('cat >' . temppath, a:contents, 0)
      if !v:shell_error
        call s:remote_execute('cat ' . temppath . ' - | ' . a:cmd . ' ; rm ' . temppath, [], 0)
      else
        echoerr output
      endif
    else
      let local_tempname = tempname()
      call writefile(a:contents, local_tempname)
      execute '!cat ' . local_tempname . ' | ' . ssh_cmd . " '" . a:cmd . "'"
      call delete(local_tempname)
    endif
  else
    let piped = ''
    execute '!' . ssh_cmd . " '" . a:cmd . "'"
  endif
endfunction

" public functions

function! pim#describe(variable)
  " describe variable under cursor in preview window
  let splits = split(a:variable, ':')
  let start_time = localtime()
  let cur_word = splits[0]
  if len(splits) ==# 1
    let cur_line = line('.')
  else
    let cur_line = splits[1]
  endif
  redraw!
  echo 'Loading description for ' . cur_word . ' at line ' . cur_line . '...'
  " for multiline definitions, the end of the statement might be below the cursor
  let raw_contents = getline(1, match(getline(1, line('$')), ';', cur_line - 1) + 1)
  " remove store, rmf, etc and add prettyprint
  let contents = add(s:sanitize(raw_contents, 1), 'describe ' . cur_word . ';')
  " store to file instead of directly piping to allow registers and defines to work
  let temppath = s:tempname('.pig')
  let command = 'cat >' . temppath . ' && ' . g:pim_pig_command . ' ' . temppath . ' ; rm ' . temppath
  if strlen(g:pim_remote_url)
    let output = s:remote_system(command, contents, 0)
  else
    let output = system(command, join(contents, "\n"))
  endif
  if !v:shell_error
    let list_output = split(output, "\n")
    if match(list_output, '\CERROR') >=# 0
      " something went wrong, output the first error if possible
      let error_match = match(list_output, 'line \d\+, column \d\+')
      if error_match >=# 0
        echoerr substitute(list_output[error_match], '\vfile [^,]+, ', '', '')
      else
        echoerr 'Something went wrong while running your pig script but no error message was found.'
      endif
    else
      " everything seems ok
      let desc_start = -1 + len(list_output) - match(reverse(copy(list_output)), '\C^' . cur_word . ': {')
      " remove verbose pig logs
      let filtered_output = filter(list_output[desc_start : len(list_output) - 1], 'v:val !~? ''\v\[(info|debug)\]''')
      call s:open_in_preview_window(['# ' . cur_word . ' at line ' . cur_line] + filtered_output, 'yaml')
      redraw!
      let seconds = localtime() - start_time
      echo 'Description for ' . cur_word . ' at line ' . cur_line . ' loaded in ' . seconds . ' seconds.'
    endif
  else
    echoerr output
  endif
endfunction

function! pim#grunt(raw) range
  " load range into grunt, optionally removing trigger lines
  redraw!
  let contents = getline(a:firstline, a:lastline)
  if !a:raw
    let contents = s:sanitize(contents, 1)
  endif
  " add line to give empty prompt
  let content = add(contents, '')
  if strlen(g:pim_remote_url)
    echo 'Preparing remote interactive session...'
    call s:remote_execute(g:pim_pig_command, contents, 1)
  else
    let temppath = s:tempname('.pig')
    call system('cat >' . temppath, join(contents, "\n"))
    execute '!cat ' . temppath . ' - | ' . g:pim_pig_command
    call system('rm ' . temppath)
  endif
endfunction

" autocommands

augroup pimcommands
  autocmd!
  autocmd VimLeave * call s:close_master_client(1)
augroup END
