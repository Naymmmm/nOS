#!/bin/sh
# nos-bsd-build.sh — runs INSIDE the FreeBSD VM
# Builds the NOSKERNEL and copies the result to /mnt/out (shared 9p dir)
set -e

NOSDIR="/mnt/nos"          # nOS repo mounted via 9p virtfs
OUTDIR="/mnt/out"          # output dir mounted via 9p virtfs
SRCDIR="/usr/src"
JOBS="$(sysctl -n hw.ncpu)"

log()  { echo "\033[1;32m==> $*\033[0m"; }
die()  { echo "\033[1;31mERROR: $*\033[0m" >&2; exit 1; }

log "nOS FreeBSD Kernel Build"
log "Jobs: ${JOBS}"
log "Kernel config: NOSKERNEL"

# ---- Grow the UFS partition to fill the resized disk ----
log "Growing root partition..."
gpart recover da0 2>/dev/null || true
gpart resize -i 3 da0 2>/dev/null || true
growfs -y / 2>/dev/null || true

# ---- Mount shared dirs ----
log "Mounting shared filesystems..."
mkdir -p /mnt/nos /mnt/out
mount -t virtfs -o trans=virtio,version=9p2000.L nos  /mnt/nos 2>/dev/null || \
    mount_9p nos  /mnt/nos 2>/dev/null || \
    log "WARNING: Could not mount nOS share (continuing anyway)"
mount -t virtfs -o trans=virtio,version=9p2000.L out  /mnt/out 2>/dev/null || \
    mount_9p out  /mnt/out 2>/dev/null || \
    log "WARNING: Could not mount out share (continuing anyway)"

# ---- Fetch FreeBSD 14.3 source ----
if [ ! -d "${SRCDIR}/.git" ] && [ ! -f "${SRCDIR}/Makefile" ]; then
    log "Fetching FreeBSD 14.3-RELEASE source tree..."
    pkg install -y git
    git clone --depth 1 \
        --branch releng/15.0 \
        https://git.FreeBSD.org/src.git \
        "${SRCDIR}"
fi

# ---- Copy kernel config ----
log "Installing NOSKERNEL config..."
KERN_CONF_SRC="/mnt/nos/build/config/NOSKERNEL"
if [ -f "${KERN_CONF_SRC}" ]; then
    cp "${KERN_CONF_SRC}" "${SRCDIR}/sys/arm64/conf/NOSKERNEL"
else
    log "WARNING: NOSKERNEL not found in share, using config from repo copy"
fi

# ---- Build kernel ----
log "Building NOSKERNEL with ${JOBS} jobs..."
cd "${SRCDIR}"
make -j"${JOBS}" buildkernel \
    KERNCONF=NOSKERNEL \
    TARGET=arm64 \
    TARGET_ARCH=aarch64 \
    2>&1 | tee /tmp/kernel-build.log

log "Build complete — collecting artifacts..."
OBJDIR="/usr/obj/usr/src/arm64.aarch64/sys/NOSKERNEL"

mkdir -p "${OUTDIR}"
cp "${OBJDIR}/kernel"        "${OUTDIR}/NOSKERNEL"       2>/dev/null || true
cp "${OBJDIR}/kernel.symbols" "${OUTDIR}/NOSKERNEL.symbols" 2>/dev/null || true
cp /tmp/kernel-build.log    "${OUTDIR}/kernel-build.log"

log "Artifacts written to /mnt/out (host: dist/kernel/)"
log "DONE"
