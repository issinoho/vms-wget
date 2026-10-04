/* vms.c - OpenVMS support routines used by wget's __VMS code paths.

   See vms.h.  Part of the OpenVMS port of GNU Wget
   (github.com/issinoho/vms-wget); distributed under the GNU General Public
   License, version 3 or later.  */

#include <config.h>

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <descrip.h>
#include <dvidef.h>
#include <lib$routines.h>
#include <syidef.h>

#include "vms.h"

/* The C RTL's exit routines (vms_exit() below replaces exit(); see patch
   0008): decc$exit takes a VMS condition value as it is, decc$__posix_exit
   a POSIX exit code.  */
void decc$exit (int status);
void decc$__posix_exit (int status);

int
acc_cb (int *id_arg, struct FAB *fab, struct RAB *rab)
{
  (void) id_arg;
  (void) fab;
  /* Sequential transfers: read ahead, write behind, a few buffers.  */
  rab->rab$l_rop |= RAB$M_RAH | RAB$M_WBH;
  if (rab->rab$b_mbf < 4)
    rab->rab$b_mbf = 4;
  return 0;
}

/* Is the destination volume ODS-5?  -1 until known.  */
static int ods5_dest = -1;

/* ODS-5 test for the volume of a device or file specification.  If the
   answer is unknown, assume ODS-5 (names are then left alone).  */
static int
volume_is_ods5 (const char *spec)
{
  char dev[256];
  const char *colon = strchr (spec, ':');
  size_t n = colon ? (size_t) (colon - spec) : strlen (spec);
  int item = DVI$_ACPTYPE;
  unsigned int acptype = 0;
  struct dsc$descriptor_s d;
  /* A Unix-style or relative name: its volume is the default one.  */
  if (!colon || n == 0 || n >= sizeof dev || strchr (spec, '/'))
    {
      strcpy (dev, "SYS$DISK");
      n = strlen (dev);
    }
  else
    {
      memcpy (dev, spec, n);
      dev[n] = '\0';
    }
  d.dsc$w_length = (unsigned short) n;
  d.dsc$b_dtype = DSC$K_DTYPE_T;
  d.dsc$b_class = DSC$K_CLASS_S;
  d.dsc$a_pointer = dev;
  if (!(lib$getdvi (&item, 0, &d, &acptype, 0, 0) & 1))
    return 1;
  return acptype == DVI$C_ACP_F11V5;
}

void
set_ods5_dest (const char *dest)
{
  ods5_dest = volume_is_ods5 (dest ? dest : "SYS$DISK");
}

/* Make one ODS-2 name component in place: only A-Z a-z 0-9 _ $ -, at
   most one dot (the last one; earlier dots become "_"), and at most 39
   characters before and after it.  */
static void
ods2_component (char *name)
{
  char *last_dot = strrchr (name, '.');
  char *p, *out = name;
  int len = 0;
  for (p = name; *p; p++)
    {
      int c = (unsigned char) *p;
      if (p == last_dot)
        {
          *out++ = '.';
          len = 0;
          continue;
        }
      if (len >= 39)
        continue;
      if (!(isalnum (c) || c == '_' || c == '$' || c == '-'))
        c = '_';
      *out++ = (char) c;
      len++;
    }
  *out = '\0';
}

char *
ods_conform (char *path)
{
  char *copy, *start, *slash;
  if (ods5_dest < 0)
    set_ods5_dest ("SYS$DISK");
  if (ods5_dest)
    return path;
  copy = malloc (strlen (path) + 1);
  if (copy == NULL)
    return path;
  strcpy (copy, path);
  /* Unix-style relative or absolute path: conform each component.  */
  for (start = copy; *start; start = slash + 1)
    {
      slash = strchr (start, '/');
      if (slash)
        *slash = '\0';
      if (*start && strcmp (start, ".") && strcmp (start, ".."))
        ods2_component (start);
      if (!slash)
        break;
      *slash = '/';
    }
  return copy;
}

char *
vms_basename (char *file_spec)
{
  static char name[40];
  const char *p = file_spec, *q;
  size_t n;

  /* Skip "node::", "dev:" and "[dir]" or "<dir>"; a Unix-style
     "/dir/name" too.  */
  if ((q = strrchr (p, ']')) || (q = strrchr (p, '>'))
      || (q = strrchr (p, ':')) || (q = strrchr (p, '/')))
    p = q + 1;
  for (n = 0; p[n] && p[n] != '.' && p[n] != ';' && n < sizeof name - 1; n++)
    name[n] = (char) tolower ((unsigned char) p[n]);
  name[n] = '\0';
  return n ? name : (char *) "wget";
}

/* A $GETSYI string item, trailing blanks removed.  */
static void
syi_string (int item, char *buf, size_t size)
{
  unsigned short len = 0;
  struct dsc$descriptor_s d;
  d.dsc$w_length = (unsigned short) (size - 1);
  d.dsc$b_dtype = DSC$K_DTYPE_T;
  d.dsc$b_class = DSC$K_CLASS_S;
  d.dsc$a_pointer = buf;
  if (!(lib$getsyi (&item, 0, &d, &len, 0, 0) & 1))
    len = 0;
  buf[len] = '\0';
  while (len > 0 && buf[len - 1] == ' ')
    buf[--len] = '\0';
}

int
vms_version_supplement (void)
{
  char version[16], arch[16];
  syi_string (SYI$_VERSION, version, sizeof version);
  syi_string (SYI$_ARCH_NAME, arch, sizeof arch);
  if (printf ("OpenVMS %s on %s; port: https://github.com/issinoho/vms-wget\n",
              version, arch) < 0)
    return -1;
  return 0;
}

/* exit() for wget (lib/stdlib.h, patch 0008).  Under a Unix shell (GNV
   bash: SHELL is set and is not "DCL") keep the POSIX exit, which the shell
   decodes as $?.  Under DCL, exit code 0 is success, and any other code N an
   error-severity status in the C RTL's POSIX range with the message
   suppressed (%X1035A002 + N*8), so $SEVERITY is 2 and ON ERROR fires; N is
   still (status & %X7F8) / 8.  */
void
vms_exit (int status)
{
  const char *shell = getenv ("SHELL");
  if (shell != NULL && strcmp (shell, "DCL") != 0)
    decc$__posix_exit (status);
  if (status == 0)
    decc$exit (1);
  decc$exit (0x10000000 | 0x35A000 | ((status & 0xFF) << 3) | 2);
}
