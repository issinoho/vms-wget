/* vms_ip.h - IP headers for OpenVMS.

   wget's connect.c and host.c include this under __VMS in place of
   <netdb.h>.  The VSI C run-time library provides the BSD socket headers
   directly (TCP/IP Services, or a compatible stack), so this only collects
   them.

   Part of the OpenVMS port of GNU Wget (github.com/issinoho/vms-wget);
   distributed under the GNU General Public License, version 3 or later.  */

#ifndef VMS_IP_H
#define VMS_IP_H

#include <sys/types.h>
#include <errno.h>
#include <netdb.h>

#endif /* VMS_IP_H */
