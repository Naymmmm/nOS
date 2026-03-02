#!/bin/sh
# nos-patches.sh — Apply nOS modifications to FreeBSD 14.x kernel source
# Run from inside the VM before make buildkernel.
# Usage: sh nos-patches.sh [/usr/src] [http://10.0.2.2:8080]

set -e

SRCDIR="${1:-/usr/src}"
HOST="${2:-http://10.0.2.2:8080}"

log()  { printf '\033[1;36m[nOS] %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m  OK: %s\033[0m\n' "$*"; }
skip() { printf '\033[1;33m  --: %s (skipped)\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERR: %s\033[0m\n' "$*" >&2; exit 1; }

log "Applying nOS patches to ${SRCDIR}"
[ -f "${SRCDIR}/sys/kern/init_main.c" ] || die "Not a FreeBSD source tree: ${SRCDIR}"

# ============================================================
# 1. Boot banner — replace "FreeBSD" branding in kern/init_main.c
# ============================================================
log "1/4  Boot banner"
TARGET="${SRCDIR}/sys/kern/init_main.c"

# FreeBSD 14 prints the version via: printf("%s", version);
# We insert our banner line just before that.
if grep -q 'nOS' "${TARGET}"; then
    skip "Boot banner already patched"
else
    # Insert nOS banner before the first printf("%s", version) call
    sed -i '' 's/printf("%s", version);/printf("\\nnOS 1.0 \\"Void\\" — built on FreeBSD\\n");\n\tprintf("%s", version);/' \
        "${TARGET}" && ok "Boot banner inserted" || skip "Banner sed failed"
fi

# ============================================================
# 2. kern.ostype — advertise "nOS" instead of "FreeBSD"
# ============================================================
log "2/4  kern.ostype"
TARGET="${SRCDIR}/sys/kern/kern_mib.c"

if grep -q '"nOS"' "${TARGET}"; then
    skip "ostype already patched"
else
    sed -i '' 's/static char ostype\[\] = "FreeBSD"/static char ostype[] = "nOS"/' \
        "${TARGET}" && ok "kern.ostype = nOS" || skip "ostype sed failed"
fi

# ============================================================
# 3. ULE scheduler — desktop interactivity tuning
#    Lower SCHED_INTERACT_THRESH: fewer ticks needed to be
#    classified interactive → snappier UI thread response.
#    Lower SCHED_INTERACT_HALF: tighter interactive window.
# ============================================================
log "3/4  ULE scheduler tuning"
TARGET="${SRCDIR}/sys/kern/sched_ule.c"

if grep -q 'NOS_DESKTOP_TUNING' "${TARGET}"; then
    skip "Scheduler already patched"
else
    # Default SCHED_INTERACT_THRESH is 30; lower to 20 for desktop
    sed -i '' 's/#define\tSCHED_INTERACT_THRESH\t(30)/#define\tSCHED_INTERACT_THRESH\t(20)\t\/* nOS desktop tuning *\//' \
        "${TARGET}" && ok "SCHED_INTERACT_THRESH 30 -> 20" || skip "thresh sed failed"

    # Default SCHED_INTERACT_HALF is 15; lower to 10
    sed -i '' 's/#define\tSCHED_INTERACT_HALF\t(SCHED_INTERACT_MAX \/ 2)/#define\tSCHED_INTERACT_HALF\t(10)\t\/* nOS desktop tuning *\//' \
        "${TARGET}" && ok "SCHED_INTERACT_HALF -> 10" || skip "half sed failed"

    # Mark file so we know it was patched
    echo "/* NOS_DESKTOP_TUNING applied */" >> "${TARGET}"
fi

# ============================================================
# 4. kern_nos.c — nOS sysctl tree (kern.nos.*)
# ============================================================
log "4/4  kern.nos sysctl tree"
DEST="${SRCDIR}/sys/kern/kern_nos.c"

fetch -q -o "${DEST}" "${HOST}/build/patches/kern_nos.c" \
    && ok "kern_nos.c installed" \
    || die "Could not fetch kern_nos.c from ${HOST}"

# Register in sys/conf/files if not already present
FILES="${SRCDIR}/sys/conf/files"
if grep -q 'kern_nos.c' "${FILES}"; then
    skip "kern_nos.c already in sys/conf/files"
else
    echo 'kern/kern_nos.c			standard' >> "${FILES}"
    ok "kern_nos.c added to sys/conf/files"
fi

# ============================================================
# Done
# ============================================================
log "nOS patches applied. Build with: make buildkernel KERNCONF=NOSKERNEL"
