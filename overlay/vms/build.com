$! BUILD.COM - build GNU Wget for OpenVMS
$!
$! Usage:  @[.VMS]BUILD [target] [KEEP_GOING]
$!         target defaults to ALL; CLEAN also works.  KEEP_GOING carries on
$!         past failed compiles so one run reports every error.
$!
$! Runs from the top of the prepared source tree regardless of where it is
$! invoked from.  Output: [.BIN_<arch>]WGET.EXE
$!
$ status = 44  ! SS$_ABORT unless the build runs
$ on control_y then goto done
$ saved_default = f$environment("DEFAULT")
$ proc = f$environment("PROCEDURE")
$ vmsdir = f$parse(proc,,,"DEVICE") + f$parse(proc,,,"DIRECTORY")
$ set default 'vmsdir'
$ set default [-]
$ arch = f$getsyi("ARCH_NAME")
$ if arch .eqs. "x86_64" then arch = "X86_64"
$ if arch .eqs. "IA64" .or. arch .eqs. "X86_64" then goto arch_ok
$ write sys$error "BUILD: unsupported architecture ''arch'"
$ goto done
$arch_ok:
$ if f$search("OBJ_''arch'.DIR") .eqs. "" then create/directory [.OBJ_'arch']
$ if f$search("[.OBJ_''arch']LIB.DIR") .eqs. "" then create/directory [.OBJ_'arch'.LIB]
$ if f$search("BIN_''arch'.DIR") .eqs. "" then create/directory [.BIN_'arch']
$! Libraries: ZLIB$ROOT and PCRE2$ROOT must be rooted logicals for the
$! vms-zlib and vms-pcre2 install trees, e.g.
$!   $ DEFINE/TRANSLATION=CONCEALED ZLIB$ROOT dev:[dir.ZLIB-1_3_2.INSTALL_IA64.]
$! and VSI's SSL3 kit (OpenSSL 3.0) must be installed.
$ if p1 .nes. "CLEAN"
$ then
$   if f$trnlnm("ZLIB$ROOT") .eqs. "" .or. f$trnlnm("PCRE2$ROOT") .eqs. ""
$   then
$     write sys$error "BUILD: define ZLIB$ROOT and PCRE2$ROOT for the library trees first (see README)"
$     goto done
$   endif
$   if f$trnlnm("SSL3$INCLUDE") .eqs. ""
$   then
$     write sys$error "BUILD: VSI's SSL3 kit (SSL3$INCLUDE) is not installed"
$     goto done
$   endif
$   define/process OPENSSL SSL3$INCLUDE:
$ endif
$ target = p1
$ if target .eqs. "" then target = "ALL"
$ write sys$output "BUILD: ''target' for ''arch' in ''f$environment("DEFAULT")'"
$ mmsq = ""
$ if p2 .eqs. "KEEP_GOING" then mmsq = "/IGNORE=ERROR"
$ mms/description=[.vms]descrip.mms/macro=("ARCH=''arch'")'mmsq' 'target'
$ status = $status
$ if status then write sys$output "BUILD: done"
$done:
$ set default 'saved_default'
$ exit status
