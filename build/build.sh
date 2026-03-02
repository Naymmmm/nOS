#!/bin/sh
#
# nOS Build Script
# Assembles the nOS root filesystem from FreeBSD base + nOS overlay
#

set -e

ARCH="${1:-amd64}"
FBSD_VER="${2:-14.1-RELEASE}"
SRCDIR="${SRCDIR:-/usr/src}"
NOSDIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOTFS="${NOSDIR}/dist/rootfs"

echo "============================================"
echo "  nOS Build System"
echo "  Architecture : ${ARCH}"
echo "  FreeBSD Base : ${FBSD_VER}"
echo "  Output       : ${ROOTFS}"
echo "============================================"
echo ""

# Must be built on FreeBSD
if [ "$(uname -s)" != "FreeBSD" ]; then
    echo "Error: nOS must be built on a FreeBSD host."
    exit 1
fi

# Must be root
if [ "$(id -u)" != "0" ]; then
    echo "Error: build.sh must be run as root."
    exit 1
fi

step() { echo ""; echo "==> $*"; }

mkdir -p "${ROOTFS}"

step "Installing FreeBSD world..."
cd "${SRCDIR}" && make installworld \
    DESTDIR="${ROOTFS}" \
    SRCCONF="${NOSDIR}/build/config/src.conf" \
    TARGET="${ARCH}" \
    -j"$(sysctl -n hw.ncpu)"

step "Installing nOS kernel..."
cd "${SRCDIR}" && make installkernel \
    DESTDIR="${ROOTFS}" \
    KERNCONF=NOSKERNEL \
    KERNCONFDIR="${NOSDIR}/build/config" \
    TARGET="${ARCH}"

step "Running make distribution..."
cd "${SRCDIR}" && make distribution \
    DESTDIR="${ROOTFS}" \
    SRCCONF="${NOSDIR}/build/config/src.conf" \
    TARGET="${ARCH}"

step "Applying nOS rootfs overlay..."
# System configuration files
cp -rp "${NOSDIR}/rootfs/." "${ROOTFS}/"

step "Staging desktop environment..."
mkdir -p "${ROOTFS}/usr/local/share/nos"
cp -rp "${NOSDIR}/desktop"      "${ROOTFS}/usr/local/share/nos/"
cp -rp "${NOSDIR}/installer"    "${ROOTFS}/usr/local/share/nos/"
cp -rp "${NOSDIR}/scripts/."    "${ROOTFS}/usr/local/bin/"
chmod +x "${ROOTFS}/usr/local/bin/nos-"*

step "Setting up xsessions entry..."
mkdir -p "${ROOTFS}/usr/local/share/xsessions"
cat > "${ROOTFS}/usr/local/share/xsessions/nos.desktop" << 'EOF'
[Desktop Entry]
Name=nOS
Comment=nOS Desktop Environment
Exec=/usr/local/bin/nos-session
Type=Application
EOF

step "Installing packages into rootfs..."
pkg -r "${ROOTFS}" update
pkg -r "${ROOTFS}" install -y \
    $(tr '\n' ' ' < "${NOSDIR}/packages/base-packages.txt") \
    $(tr '\n' ' ' < "${NOSDIR}/packages/desktop-packages.txt")

step "Configuring display manager..."
mkdir -p "${ROOTFS}/usr/local/etc/lightdm"
cp "${NOSDIR}/display-manager/lightdm.conf" \
   "${ROOTFS}/usr/local/etc/lightdm/lightdm.conf"
cp "${NOSDIR}/display-manager/greeter.conf" \
   "${ROOTFS}/usr/local/etc/lightdm/lightdm-gtk-greeter.conf"

step "Writing version info..."
echo "${FBSD_VER}" > "${ROOTFS}/etc/freebsd-version"
printf "NOS_VERSION=1.0.0\nNOS_CODENAME=Agate\nNOS_ARCH=%s\n" "${ARCH}" \
    > "${ROOTFS}/etc/nos-release"

step "Build complete."
echo ""
echo "Root filesystem: ${ROOTFS}"
echo "Next: make image"
