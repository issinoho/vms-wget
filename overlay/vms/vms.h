/* vms.h - OpenVMS support routines used by wget's __VMS code paths.

   wget's sources keep VMS code from an earlier port (ftp.c, url.c,
   utils.c, main.c); its support files are no longer distributed, so this
   port supplies its own implementation of the same interface.

   Part of the OpenVMS port of GNU Wget (github.com/issinoho/vms-wget);
   distributed under the GNU General Public License, version 3 or later.  */

#ifndef VMS_H
#define VMS_H

#include <fab.h>
#include <rab.h>

/* wget's VMS code (ftp.c, utils.c) passes RMS file attributes ("ctx=bin",
   "rfm=stmlf", "acc", acc_cb, ...) as extra arguments to the CRTL's
   variadic open() and fopen().  gnulib replaces both (for O_CLOEXEC, fchdir
   and fclose support wget does not use) with functions that take only the
   standard arguments, so use the CRTL's in the files that include this.  */
#include <fcntl.h>
#include <stdio.h>
#undef open
#undef fopen

/* RMS access callback for open()/fopen() ("acc", acc_cb, &id): sets
   read-ahead/write-behind and multi-buffering for sequential transfers.
   *id_arg identifies the call site (wget numbers them).  */
int acc_cb (int *id_arg, struct FAB *fab, struct RAB *rab);

/* Record whether file names will be created on an ODS-5 volume: the
   volume of DEST (a file or device specification, e.g. "SYS$DISK" or the
   --output-document file).  main() calls it before any download.  */
void set_ods5_dest (const char *dest);

/* A version of PATH whose components are valid file names on the destination
   volume (set_ods5_dest()): PATH itself on ODS-5, otherwise a new
   malloc'ed string (the caller frees PATH and uses the result).  */
char *ods_conform (char *path);

/* The program name for messages: "dev:[dir]WGET.EXE;1" -> "wget".  */
char *vms_basename (char *file_spec);

/* Extra lines for --version (OpenVMS version and architecture, this
   port).  Returns a negative value on an output error.  */
int vms_version_supplement (void);

#endif /* VMS_H */
