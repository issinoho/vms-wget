$! VMS_INSTALLCHECK.COM <tree-dir-name> - install the WGET kit, verify it, run
$! wget from it, then remove it.  Changes the system while it runs (PCSI
$! database, SYS$COMMON:[WGET], system logical WGET$ROOT); leaves it as it was.
$ set noon
$ arch = f$edit(f$getsyi("ARCH_NAME"), "UPCASE")
$ base = "I64VMS"
$ if arch .eqs. "X86_64" then base = "X86VMS"
$ here = f$environment("DEFAULT")
$ tree = here - "]" + "." + p1 + "]"
$ kitdir = tree - "]" + ".KIT_''arch']"
$ write sys$output "=== INSTALL from ", kitdir
$ product install WGET /producer=ISSINOHO /base_system='base' /source='kitdir' /options=noconfirm /log
$ write sys$output "=== install status ", $status
$ product show product WGET /producer=ISSINOHO
$ write sys$output "=== VERIFY"
$ write sys$output "startup procedure: [", f$search("SYS$STARTUP:WGET$STARTUP.COM"), "]"
$ show logical WGET$ROOT
$ directory/nohead/notrail WGET$ROOT:[000000...]*.*
$ write sys$output "=== WGET FROM THE INSTALLED KIT"
$ @WGET$ROOT:[000000]WGET$SETUP.COM
$ set process/parse_style=extended
$ wget --version
$ sev = $severity
$ if sev .eq. 1 then write sys$output "WGET_VERSION: PASS"
$ if sev .ne. 1 then write sys$output "WGET_VERSION: FAIL"
$! HTTPS with no --ca-certificate: the kit's WGETRC. names its CACERT.PEM
$ wget -q -O nla0: https://example.com/
$ sev = $severity
$ if sev .eq. 1 then write sys$output "WGET_HTTPS_DEFAULT_CA: PASS"
$ if sev .ne. 1 then write sys$output "WGET_HTTPS_DEFAULT_CA: FAIL"
$! Downloading a file that exists makes a new version (not index.html.1),
$! written as Stream_LF.
$ if f$search("WGETIC.DIR") .eqs. "" then create/directory [.WGETIC]
$ set default [.WGETIC]
$ wget -q https://example.com/
$ wget -q https://example.com/
$ directory/nohead/notrail/size
$ v2 = f$search("INDEX.HTML;2") .nes. ""
$! (A Unix-style index.html.1 would be INDEX^.HTML.1 on ODS-5; plain
$! "INDEX.HTML.1" would mean version 1 of INDEX.HTML.)
$ dot1 = f$search("INDEX^.HTML.1;*") .nes. ""
$ if v2 .and. .not. dot1 then write sys$output "WGET_NEW_VERSION: PASS"
$ if .not. v2 .or. dot1 then write sys$output "WGET_NEW_VERSION: FAIL"
$ rfm = f$file_attributes("INDEX.HTML", "RFM")
$ write sys$output "record format: ", rfm
$ if rfm .eqs. "STMLF" then write sys$output "WGET_STREAM_LF: PASS"
$ if rfm .nes. "STMLF" then write sys$output "WGET_STREAM_LF: FAIL"
$ delete/nolog *.*;*
$ set default [-]
$ set file/protection=o:rwed WGETIC.DIR
$ delete/nolog WGETIC.DIR;
$! A failed run has error severity under DCL
$ define/user sys$error nla0:
$ wget -q -O nla0: http://nonexistent.invalid/
$! Capture $STATUS once: any DCL assignment resets $STATUS and $SEVERITY.
$ st = $status
$ sev = st .and. 7
$ write sys$output "failed run status ", st, " severity ", sev
$ if sev .eq. 2 .or. sev .eq. 4 then write sys$output "WGET_ERROR_SEVERITY: PASS"
$ if sev .ne. 2 .and. sev .ne. 4 then write sys$output "WGET_ERROR_SEVERITY: FAIL"
$ delete/symbol/global wget
$ write sys$output "=== REMOVE"
$ product remove WGET /producer=ISSINOHO /options=noconfirm /log
$ write sys$output "=== remove status ", $status
$ write sys$output "WGET$ROOT after removal: [", f$trnlnm("WGET$ROOT"), "]"
$ write sys$output "files after removal: [", f$search("SYS$COMMON:[WGET...]*.*"), "]"
$ write sys$output "startup after removal: [", f$search("SYS$STARTUP:WGET$STARTUP.COM"), "]"
$ product show product WGET /producer=ISSINOHO
