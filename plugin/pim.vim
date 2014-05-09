if exists('s:loaded') || &compatible
  finish
else
  let s:loaded = 1
endif

if !exists('g:pim_pig_command')
  let g:pim_pig_command = 'pig'
endif
if !exists('g:pim_remote_url')
  let g:pim_remote_url = ''
endif
if !exists('g:pim_kerberos_bin_dir')
  let g:pim_kerberos_bin_dir = '/usr/bin/'
endif

command! -nargs=1 PimDescribe call pim#describe(<q-args>)
command! -bang -nargs=0 -range=% PimGrunt <line1>,<line2>call pim#grunt(<bang>0)
