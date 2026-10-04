$! WGET$STARTUP.COM - system startup for GNU Wget on OpenVMS
$!
$! Installed by PCSI into SYS$STARTUP.  Defines the system logical name
$! WGET$ROOT, pointing at the installed [WGET] directory.  To run it at every
$! boot, add this line to SYS$MANAGER:SYSTARTUP_VMS.COM:
$!
$!     $ @SYS$STARTUP:WGET$STARTUP.COM
$!
$! P1 = "INSTALL": also print the post-installation tasks (PCSI runs it so).
$! P1 = "REMOVE":  deassign WGET$ROOT instead (PCSI runs it so at removal).
$!
$! Users then define the wget command with
$!     $ @WGET$ROOT:[000000]WGET$SETUP.COM
$!
$ set noon
$ mode = f$edit(p1, "UPCASE")
$ if mode .eqs. "REMOVE"
$ then
$   if f$trnlnm("WGET$ROOT", "LNM$SYSTEM_TABLE") .nes. "" then -
        deassign/system/executive_mode WGET$ROOT
$   exit 1
$ endif
$!
$! This procedure sits in <destination>[SYS$STARTUP]; the product is in
$! <destination>[WGET].  Rooted logicals need the physical form:
$! DKA0:[SYS0.SYSCOMMON.SYS$STARTUP] -> DKA0:[SYS0.SYSCOMMON.WGET.]
$ proc = f$environment("PROCEDURE")
$ dev = f$parse(proc,,,"DEVICE","NO_CONCEAL")
$ dir = f$edit(f$parse(proc,,,"DIRECTORY","NO_CONCEAL"), "UPCASE") - "]["
$ root = dir - "SYS$STARTUP]" + "WGET.]"
$ if root .eqs. dir + "WGET.]"
$ then
$   write sys$error "WGET$STARTUP: expected to be in a [SYS$STARTUP] directory, not ''dir'"
$   exit 44
$ endif
$ root = root - ".000000"
$ define/system/executive_mode/translation_attributes=concealed WGET$ROOT 'dev''root'
$ if f$search("WGET$ROOT:[BIN]WGET.EXE") .eqs. ""
$ then
$   write sys$error "WGET$STARTUP: WGET.EXE not found under ''dev'''root'"
$   exit 44
$ endif
$ if mode .nes. "INSTALL" then exit 1
$ say = "write sys$output"
$ say ""
$ say "    Post-installation tasks for GNU Wget"
$ say ""
$ say "    At system startup: to define WGET$ROOT at every boot, add this line to"
$ say "    SYS$MANAGER:SYSTARTUP_VMS.COM:"
$ say "    $ @SYS$STARTUP:WGET$STARTUP.COM"
$ say "    For each user: to define the wget command, add this line to LOGIN.COM:"
$ say "    $ @WGET$ROOT:[000000]WGET$SETUP.COM"
$ say ""
$ say "    PRODUCT REMOVE WGET removes the product and deassigns WGET$ROOT."
$ say ""
$ exit 1
