! DESCRIP.MMS - build GNU Wget for OpenVMS (IA64, x86-64)
!
! Run from the top of the prepared source tree via [.VMS]BUILD.COM, which
! passes ARCH (IA64 or X86_64), creates the output directories and defines
! the logical names for the libraries:
!   ZLIB$ROOT   zlib install tree (github.com/issinoho/vms-zlib)
!   PCRE2$ROOT  PCRE2 install tree (github.com/issinoho/vms-pcre2)
!   OPENSSL     SSL3$INCLUDE:, so <openssl/ssl.h> finds VSI's SSL3 headers
! Source lists and per-object rules come from [.VMS]SOURCES.MMS, generated
! by tools/prepare.sh on the host.

.IFDEF ARCH
.ELSE
ARCH = IA64
.ENDIF

OBJ = [.OBJ_$(ARCH)]
LOBJ = [.OBJ_$(ARCH).LIB]
BIN = [.BIN_$(ARCH)]

.INCLUDE [.VMS]SOURCES.MMS

LIB = $(OBJ)LIBGNU.OLB
EXE = $(BIN)WGET.EXE

CC = CC
! SYSTEM_WGETRC: the system-wide startup file (src/Makefile passes
! $(sysconfdir)/wgetrc); the kit installs WGET$ROOT:[ETC]WGETRC.
CFLAGS = $(CC_QUAL)/NOLIST-
	/INCLUDE_DIRECTORY=("./src","./lib","./vms","ZLIB$ROOT:[INCLUDE]","PCRE2$ROOT:[INCLUDE]")-
	/DEFINE=($(CC_DEFS),HAVE_CONFIG_H,"SYSTEM_WGETRC=""WGET$ROOT:[ETC]WGETRC.""")
LIBS = $(LIB)/LIBRARY, PCRE2$ROOT:[LIB]PCRE2-8.OLB/LIBRARY, ZLIB$ROOT:[LIB]LIBZ.OLB/LIBRARY, -
	SYS$DISK:[.VMS]SSL3.OPT/OPTIONS

ALL : $(EXE)
	@ CONTINUE

! "-": LINK ends with a warning status (%ILINK-W-COMPWARN) because some
! modules compile with benign warnings: arithmetic on void * (taken as char *,
! as gcc does), gnulib's ioctl() declaration against the CRTL's, and zconf.h
! redefining HAVE_VSNPRINTF.  tools/build.sh fails the build on real link
! errors and undefined symbols.
$(EXE) : $(SRC_OBJS), $(EXTRA_OBJS), $(LIB)
	- LINK/EXECUTABLE=$(MMS$TARGET)/MAP=$(OBJ)WGET.MAP/FULL $(SRC_OBJS), $(EXTRA_OBJS), $(LIBS)

$(LIB) : $(LIB_OBJS)
	IF F$SEARCH("$(MMS$TARGET)") .EQS. "" THEN LIBRARY/CREATE/OBJECT $(MMS$TARGET)
	LIBRARY/REPLACE/OBJECT $(MMS$TARGET) $(LOBJ)*.OBJ

CLEAN :
	IF F$SEARCH("$(LOBJ)*.*") .NES. "" THEN DELETE/NOLOG $(LOBJ)*.*;*
	IF F$SEARCH("$(OBJ)*.OBJ") .NES. "" THEN DELETE/NOLOG $(OBJ)*.OBJ;*,*.OLB;*,*.MAP;*
	IF F$SEARCH("$(BIN)*.*") .NES. "" THEN DELETE/NOLOG $(BIN)*.*;*
