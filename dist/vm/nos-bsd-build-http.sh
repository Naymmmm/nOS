#!/bin/sh
# nos-bsd-build-http.sh — runs INSIDE the FreeBSD VM
# Fetches config from host HTTP server (10.0.2.2), builds NOSKERNEL locally.
# Run on host first:  cd /path/to/nOS && python3 -m http.server 8080
set -e

HOST="10.0.2.2"
PORT="8080"
SRCDIR="/usr/src"
OUTDIR="/root/kernel-out"
JOBS="$(sysctl -n hw.ncpu)"

log() { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die() { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

log "nOS FreeBSD Kernel Build"
log "Host: ${HOST}:${PORT}   Jobs: ${JOBS}"

# ---- Fetch NOSKERNEL config from host ----
log "Fetching NOSKERNEL config..."
fetch -q -o /tmp/NOSKERNEL "http://${HOST}:${PORT}/build/config/NOSKERNEL" \
    || die "Cannot reach host HTTP server at ${HOST}:${PORT} — is python3 -m http.server 8080 running?"

# ---- Bootstrap pkg if needed ----
if ! pkg -N >/dev/null 2>&1; then
    log "Bootstrapping pkg..."
    env ASSUME_ALWAYS_YES=yes pkg bootstrap
fi

# ---- Fetch FreeBSD 14.3 source (once) ----
if [ ! -f "${SRCDIR}/Makefile" ]; then
    log "Installing git..."
    pkg install -y git
    log "Cloning FreeBSD 15.0 source (~500 MB, one-time)..."
    git clone --depth 1 --branch releng/15.0 \
        https://git.FreeBSD.org/src.git "${SRCDIR}"
fi

# ---- Install kernel config ----
log "Installing NOSKERNEL config..."
mkdir -p "${SRCDIR}/sys/arm64/conf"
cp /tmp/NOSKERNEL "${SRCDIR}/sys/arm64/conf/NOSKERNEL"

# ---- Apply nOS kernel patches ----
log "Applying nOS kernel patches..."
fetch -q -o /tmp/nos-patches.sh "http://${HOST}:${PORT}/build/patches/nos-patches.sh" \
    && sh /tmp/nos-patches.sh "${SRCDIR}" "http://${HOST}:${PORT}" \
    || log "WARNING: patches failed, building stock kernel"

# ---- Build ----
log "Building NOSKERNEL with ${JOBS} jobs..."
cd "${SRCDIR}"
make -j"${JOBS}" buildkernel \
    KERNCONF=NOSKERNEL \
    TARGET=arm64 \
    TARGET_ARCH=aarch64 \
    WITHOUT_MODULES=yes \
    2>&1 | tee /tmp/kernel-build.log

# ---- Collect artifacts ----
log "Collecting artifacts -> ${OUTDIR}/"
OBJDIR="/usr/obj/usr/src/arm64.aarch64/sys/NOSKERNEL"
mkdir -p "${OUTDIR}"
cp "${OBJDIR}/kernel"           "${OUTDIR}/NOSKERNEL"
cp "${OBJDIR}/kernel.symbols"   "${OUTDIR}/NOSKERNEL.symbols" 2>/dev/null || true
cp /tmp/kernel-build.log        "${OUTDIR}/kernel-build.log"

log "Build complete!"
log "Artifacts at ${OUTDIR}/"
log "Run on host after shutdown:  make kernel-extract"
log "Shutting down in 5 s... (Ctrl-C to cancel)"
sleep 5
shutdown -p now
