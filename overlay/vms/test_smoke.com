$! TEST_SMOKE.COM - smoke test for the built wget ([.BIN_<arch>]WGET.EXE)
$!
$! Usage:  @[.VMS]TEST_SMOKE
$! Needs network access to example.com.  wget reads its system startup file
$! from WGET$ROOT:[ETC]WGETRC. (compiled in), which the kit uses to name the
$! CA bundle; the test points a process WGET$ROOT at a scratch tree laid out
$! like the kit's.
$!
$ set noon
$ saved_default = f$environment("DEFAULT")
$ saved_style = f$getjpi("", "PARSE_STYLE_PERM")
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ wget = "$" + f$parse("[.BIN_''arch']WGET.EXE")
$ pass = 0
$ fail = 0
$ if f$search("SMOKE.DIR") .eqs. "" then create/directory [.SMOKE]
$ if f$search("[.SMOKE]ETC.DIR") .eqs. "" then create/directory [.SMOKE.ETC]
$ if f$search("[.SMOKE]SSL.DIR") .eqs. "" then create/directory [.SMOKE.SSL]
$ if f$search("[.SMOKE]EMPTY.DIR") .eqs. "" then create/directory [.SMOKE.EMPTY]
$ copy/nolog [.VMS]CACERT.PEM [.SMOKE.SSL]
$ create [.SMOKE.ETC]WGETRC.
ca_certificate = WGET$ROOT:[SSL]CACERT.PEM
$ smoke = f$parse("[.SMOKE]",,,"DEVICE","NO_CONCEAL") + -
          (f$parse("[.SMOKE]",,,"DIRECTORY","NO_CONCEAL") - "][" - "]") + ".]"
$ empty = f$parse("[.SMOKE.EMPTY]",,,"DEVICE","NO_CONCEAL") + -
          (f$parse("[.SMOKE.EMPTY]",,,"DIRECTORY","NO_CONCEAL") - "][" - "]") + ".]"
$ out = "[.SMOKE]OUT.TXT"
$ page = "[.SMOKE]PAGE.HTML"
$ set process/parse_style=extended
$ define/process/translation_attributes=concealed WGET$ROOT 'smoke'
$!
$! 1. version: built with OpenSSL (wget lists no zlib or PCRE2 feature;
$!    tests 5 and 7 cover those)
$ define/user sys$output 'out'
$ wget --version
$ search/nooutput 'out' "+ssl/openssl"
$ sev = $severity
$ name = "version shows +ssl/openssl"
$ gosub check_success
$!
$! 2. HTTP download to a file
$ wget -q -O 'page' http://example.com/
$ sev = $severity
$ if sev .eq. 1
$ then
$   search/nooutput 'page' "Example Domain"
$   sev = $severity
$ endif
$ name = "HTTP download to a file"
$ gosub check_success
$!
$! 3. HTTPS verified with the CA bundle named in the system wgetrc
$ wget -q -O nla0: https://example.com/
$ sev = $severity
$ name = "HTTPS with the CA bundle from WGET$ROOT:[ETC]WGETRC."
$ gosub check_success
$!
$! 4. ... and refused without it
$ define/process/translation_attributes=concealed WGET$ROOT 'empty'
$ define/user sys$error nla0:
$ wget -q -O nla0: https://example.com/
$ sev = $severity
$ name = "HTTPS refused without a CA bundle"
$ gosub check_failure
$ define/process/translation_attributes=concealed WGET$ROOT 'smoke'
$!
$! 5. gzip transfer (zlib)
$ wget -q --compression=gzip -O 'page' https://example.com/
$ sev = $severity
$ if sev .eq. 1
$ then
$   search/nooutput 'page' "Example Domain"
$   sev = $severity
$ endif
$ name = "--compression=gzip"
$ gosub check_success
$!
$! 6. output to SYS$OUTPUT comes out as lines, not one character per record
$ define/user sys$output 'out'
$ wget -q -O - https://example.com/
$ search/nooutput 'out' "Example Domain"
$ sev = $severity
$ name = "-O - writes lines"
$ gosub check_success
$!
$! 7. PCRE2 regular expressions are accepted
$ wget -q --regex-type=pcre --accept-regex="exa\w+" -O nla0: https://example.com/
$ sev = $severity
$ name = "--regex-type=pcre"
$ gosub check_success
$!
$! 8. a failure exits with error severity
$ define/user sys$error nla0:
$ wget -q -O nla0: http://nonexistent.invalid/
$ sev = $severity
$ name = "unresolvable host gives an error status"
$ gosub check_failure
$!
$! 9. a download over an older version with fixed 8192-byte records (as a
$!    kit gets after SET FILE/ATTRIBUTE=RFM:FIX) makes a byte-exact Stream_LF
$!    new version, not fixed records (patch 0011)
$ if f$search("[.SMOKE]PAGE9.DIR") .eqs. "" then create/directory [.SMOKE.PAGE9]
$ set default [.SMOKE.PAGE9]
$ wget -q https://example.com/
$ size1 = (f$file_attributes("INDEX.HTML", "EOF") - 1) * 512 + f$file_attributes("INDEX.HTML", "FFB")
$ set file/attribute=(RFM:FIX,LRL:8192,MRS:8192,RAT:CR) INDEX.HTML;1
$ wget -q https://example.com/
$ st = $status
$ rfm2 = f$file_attributes("INDEX.HTML;2", "RFM")
$ size2 = (f$file_attributes("INDEX.HTML;2", "EOF") - 1) * 512 + f$file_attributes("INDEX.HTML;2", "FFB")
$ set default [--]
$ write sys$output "   sizes ''size1' and ''size2', new version ''rfm2'"
$ sev = 2
$ if st .and. rfm2 .eqs. "STMLF" .and. size1 .eq. size2 .and. size1 .gt. 0 then sev = 1
$ name = "download over a fixed-record older version"
$ gosub check_success
$ delete/nolog [.SMOKE.PAGE9]*.*;*
$ set file/protection=o:rwed [.SMOKE]PAGE9.DIR
$ delete/nolog [.SMOKE]PAGE9.DIR;
$!
$ write sys$output "SMOKE: ''pass' passed, ''fail' failed"
$ deassign/process WGET$ROOT
$ delete/nolog [.SMOKE.SSL]*.*;*, [.SMOKE.ETC]*.*;*, [.SMOKE]*.TXT;*, [.SMOKE]*.HTML;*
$ set file/protection=o:rwed [.SMOKE]SSL.DIR, ETC.DIR, EMPTY.DIR
$ delete/nolog [.SMOKE]SSL.DIR;, ETC.DIR;, EMPTY.DIR;
$ set file/protection=o:rwed SMOKE.DIR
$ delete/nolog SMOKE.DIR;
$ if saved_style .eqs. "TRADITIONAL" then set process/parse_style=traditional
$ set default 'saved_default'
$ if fail .eq. 0 then exit 1
$ exit 44
$!
$! The callers save $SEVERITY in sev straight after the command: any
$! assignment (name = ...) resets it.
$check_success:
$ if sev .eq. 1
$ then
$   pass = pass + 1
$   write sys$output "PASS: ", name
$ else
$   fail = fail + 1
$   write sys$output "FAIL: ", name, " (severity ", sev, ")"
$ endif
$ return
$!
$check_failure:
$ if sev .eq. 2 .or. sev .eq. 4
$ then
$   pass = pass + 1
$   write sys$output "PASS: ", name
$ else
$   fail = fail + 1
$   write sys$output "FAIL: ", name, " (severity ", sev, ", expected an error)"
$ endif
$ return
