/*-
 * kern_nos.c — nOS kernel integration layer
 *
 * Provides the kern.nos.* sysctl tree used by the nOS desktop environment
 * (noscomp compositor, nosface shell, and system utilities) to query kernel
 * identity and register runtime state.
 *
 * Compiled when NOSKERNEL config includes "options NOS".
 */

#include <sys/param.h>
#include <sys/systm.h>
#include <sys/kernel.h>
#include <sys/sysctl.h>
#include <sys/proc.h>
#include <sys/lock.h>
#include <sys/mutex.h>

#define NOS_VERSION     "1.0.0"
#define NOS_CODENAME    "Void"
#define NOS_COMPOSITOR  "noscomp"

/* --------------------------------------------------------------------------
 * kern.nos sysctl tree
 * -------------------------------------------------------------------------- */

SYSCTL_NODE(_kern, OID_AUTO, nos, CTLFLAG_RD | CTLFLAG_MPSAFE, 0,
    "nOS operating system parameters");

/* Identity */
SYSCTL_STRING(_kern_nos, OID_AUTO, version, CTLFLAG_RD | CTLFLAG_MPSAFE,
    NOS_VERSION, 0, "nOS release version");

SYSCTL_STRING(_kern_nos, OID_AUTO, codename, CTLFLAG_RD | CTLFLAG_MPSAFE,
    NOS_CODENAME, 0, "nOS release codename");

SYSCTL_STRING(_kern_nos, OID_AUTO, compositor, CTLFLAG_RD | CTLFLAG_MPSAFE,
    NOS_COMPOSITOR, 0, "nOS Wayland compositor name");

/* Desktop mode flag — set to 0 for headless/server */
static int nos_desktop_mode = 1;
SYSCTL_INT(_kern_nos, OID_AUTO, desktop_mode,
    CTLFLAG_RW | CTLFLAG_MPSAFE,
    &nos_desktop_mode, 0,
    "1 = nOS desktop active, 0 = headless");

/* Compositor PID — written by noscomp on startup so utilities can find it */
static int nos_compositor_pid = -1;
SYSCTL_INT(_kern_nos, OID_AUTO, compositor_pid,
    CTLFLAG_RW | CTLFLAG_MPSAFE,
    &nos_compositor_pid, 0,
    "PID of the running noscomp compositor (-1 if not running)");

/* Session UID — which user owns the current graphical session */
static int nos_session_uid = -1;
SYSCTL_INT(_kern_nos, OID_AUTO, session_uid,
    CTLFLAG_RW | CTLFLAG_MPSAFE,
    &nos_session_uid, 0,
    "UID of the active nOS desktop session (-1 if none)");

/* --------------------------------------------------------------------------
 * Startup announcement
 * -------------------------------------------------------------------------- */

static void
nos_kernel_init(void *arg __unused)
{
    printf("nOS " NOS_VERSION " \"" NOS_CODENAME "\" — noscomp Wayland compositor ready\n");
}

SYSINIT(nos_init, SI_SUB_LAST, SI_ORDER_ANY, nos_kernel_init, NULL);
