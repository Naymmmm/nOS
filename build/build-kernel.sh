#!/bin/sh
# nOS Linux Kernel Build Script
# Builds Linux 6.17 with the nos-linux.config for aarch64
#
# Usage:  sh build/build-kernel.sh [JOBS]
#   JOBS defaults to $(nproc)

set -e

KVER="6.17"
KURL="https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${KVER}.tar.xz"
NOSDIR="$(cd "$(dirname "$0")/.." && pwd)"
SRCROOT="${NOSDIR}/dist/linux-${KVER}"
OUTDIR="${NOSDIR}/dist/kernel"
CONFIG="${NOSDIR}/build/config/nos-linux.config"
JOBS="${1:-$(nproc)}"
TARBALL="${NOSDIR}/dist/linux-${KVER}.tar.xz"

log()  { printf "\033[1;32m==> %s\033[0m\n" "$*"; }
die()  { printf "\033[1;31mERROR: %s\033[0m\n" "$*" >&2; exit 1; }

# ---- Sanity checks ----
command -v gcc   >/dev/null || die "gcc not found"
command -v make  >/dev/null || die "make not found"
command -v bc    >/dev/null || die "bc not found (apt install bc)"
command -v flex  >/dev/null || die "flex not found (apt install flex)"
command -v bison >/dev/null || die "bison not found (apt install bison)"
[ -f /usr/include/ssl/ssl.h ] || [ -d /usr/include/openssl ] || \
    die "libssl-dev not found (apt install libssl-dev)"
command -v pahole 2>/dev/null || \
    printf "\033[33mWARN: pahole/dwarves not found — BTF will be disabled\033[0m\n"

mkdir -p "${NOSDIR}/dist"

# ---- Download source ----
if [ ! -d "${SRCROOT}" ]; then
    if [ ! -f "${TARBALL}" ]; then
        log "Downloading Linux ${KVER} from kernel.org (~153 MB)..."
        curl -L --progress-bar "${KURL}" -o "${TARBALL}"
    fi
    log "Extracting Linux ${KVER}..."
    tar -xf "${TARBALL}" -C "${NOSDIR}/dist"
    mv "${NOSDIR}/dist/linux-${KVER}" "${SRCROOT}" 2>/dev/null || true
fi

# ---- Apply config ----
log "Applying nos-linux.config..."
cp "${CONFIG}" "${SRCROOT}/.config"

# If pahole not present, disable BTF to avoid build error
if ! command -v pahole >/dev/null 2>&1; then
    sed -i \
        's/^CONFIG_DEBUG_INFO_BTF=y/# CONFIG_DEBUG_INFO_BTF is not set/' \
        "${SRCROOT}/.config"
    sed -i \
        's/^CONFIG_DEBUG_INFO_BTF_MODULES=y/# CONFIG_DEBUG_INFO_BTF_MODULES is not set/' \
        "${SRCROOT}/.config"
fi

cd "${SRCROOT}"

log "Running make olddefconfig..."
make olddefconfig

# ---- Build ----
log "Building kernel with ${JOBS} jobs..."
log "Source: ${SRCROOT}"
log "Output: ${OUTDIR}"
START=$(date +%s)

make -j"${JOBS}" \
    Image \
    modules \
    dtbs 2>&1 | tee "${NOSDIR}/dist/kernel-build.log"

END=$(date +%s)
ELAPSED=$((END - START))
MINS=$((ELAPSED / 60))
SECS=$((ELAPSED % 60))

# ---- Collect artifacts ----
log "Collecting artifacts -> ${OUTDIR}"
mkdir -p "${OUTDIR}/boot" "${OUTDIR}/modules"

cp arch/arm64/boot/Image        "${OUTDIR}/boot/Image-${KVER}-nosface"
cp arch/arm64/boot/Image.gz     "${OUTDIR}/boot/Image.gz-${KVER}-nosface" 2>/dev/null || true
cp System.map                   "${OUTDIR}/boot/System.map-${KVER}-nosface"
cp .config                      "${OUTDIR}/boot/config-${KVER}-nosface"
find arch/arm64/boot/dts -name "*.dtb" -exec cp {} "${OUTDIR}/boot/" \; 2>/dev/null || true

log "Installing modules to ${OUTDIR}/modules ..."
make modules_install INSTALL_MOD_PATH="${OUTDIR}/modules"

log "========================================"
log "Build complete in ${MINS}m ${SECS}s"
log "Kernel: ${OUTDIR}/boot/Image-${KVER}-nosface"
log "Modules: ${OUTDIR}/modules/lib/modules/${KVER}-nosface/"
log "Build log: ${NOSDIR}/dist/kernel-build.log"
log "========================================"
