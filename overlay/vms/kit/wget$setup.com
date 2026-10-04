$! WGET$SETUP.COM - define the wget command for a user
$!
$! Add to LOGIN.COM (or SYS$MANAGER:SYLOGIN.COM for everyone):
$!     $ @WGET$ROOT:[000000]WGET$SETUP.COM
$!
$! Upper-case options (-O, -N, -P, ...) need SET PROCESS/PARSE_STYLE=EXTENDED,
$! or double quotes, because traditional DCL parsing changes their case;
$! batch jobs use the traditional style.
$!
$ if f$trnlnm("WGET$ROOT") .eqs. ""
$ then
$   write sys$error "WGET$SETUP: WGET$ROOT is not defined; run WGET$STARTUP.COM first"
$   exit 44
$ endif
$ wget :== $WGET$ROOT:[BIN]WGET.EXE
$ exit 1
