#!/bin/sh
#
# nOS Image Creator
# Produces a bootable GPT+ZFS disk image
#

set -e

ARCH="${1:-amd64}"
VERSION="${2:-1.0.0}"
NOSDIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOTFS="${NOSDIR}/dist/rootfs"
IMGDIR="${NOSDIR}/dist"
IMAGE="${IMGDIR}/nOS-${VERSION}-${ARCH}.img"
IMGSIZE="8G"
MNTTARGET="/mnt/nos-build"

if [ "$(uname -s)" != "FreeBSD" ]; then
    echo "Error: mkimage.sh must be run on FreeBSD."
    exit 1
fi
if [ "$(id -u)" != "0" ]; then
    echo "Error: mkimage.sh must be run as root."
    exit 1
fi

step() { echo ""; echo "==> $*"; }

cleanup() {
    echo "==> Cleanup..."
    zpool export zroot_build 2>/dev/null || true
    [ -n "${MD}" ] && mdconfig -d -u "${MD}" 2>/dev/null || true
    umount -f "${MNTTARGET}/tmp/efi" 2>/dev/null || true
}
trap cleanup EXIT

mkdir -p "${IMGDIR}" "${MNTTARGET}"

step "Allocating ${IMGSIZE} disk image: ${IMAGE}"
truncate -s "${IMGSIZE}" "${IMAGE}"
MD=$(mdconfig -a -t vnode -f "${IMAGE}")
echo "    Memory device: /dev/${MD}"

step "Creating GPT partition table..."
gpart create -s gpt "/dev/${MD}"
gpart add -t freebsd-boot -s 512k  -l boot0  "/dev/${MD}"
gpart add -t efi          -s 256M  -l efi0   "/dev/${MD}"
gpart add -t freebsd-zfs          -l zroot0  "/dev/${MD}"

step "Installing boot code..."
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 "/dev/${MD}"

step "Formatting EFI partition..."
newfs_msdos -F 32 -c 1 "/dev/${MD}p2"
mkdir -p "${MNTTARGET}/tmp/efi"
mount_msdosfs "/dev/${MD}p2" "${MNTTARGET}/tmp/efi"
mkdir -p "${MNTTARGET}/tmp/efi/EFI/BOOT"
cp /boot/loader.efi "${MNTTARGET}/tmp/efi/EFI/BOOT/BOOTX64.EFI"
umount "${MNTTARGET}/tmp/efi"

step "Creating ZFS pool..."
zpool create \
    -o ashift=12 \
    -o autotrim=on \
    -O compression=lz4 \
    -O atime=off \
    -O xattr=sa \
    -O mountpoint=none \
    -R "${MNTTARGET}" \
    zroot_build "/dev/${MD}p3"

step "Creating dataset hierarchy..."
zfs create -o mountpoint=none          zroot_build/ROOT
zfs create -o mountpoint=/             zroot_build/ROOT/default
zfs create -o mountpoint=/home         zroot_build/home
zfs create -o mountpoint=/var          zroot_build/var
zfs create -o mountpoint=/var/log      zroot_build/var/log
zfs create -o mountpoint=/var/db       zroot_build/var/db
zfs create -o mountpoint=/var/tmp \
    -o exec=off -o setuid=off          zroot_build/var/tmp
zfs create -o mountpoint=/tmp \
    -o exec=off -o setuid=off          zroot_build/tmp
zfs create -o mountpoint=/usr/local    zroot_build/usrlocal

zpool set bootfs=zroot_build/ROOT/default zroot_build
zfs set canmount=noauto zroot_build/ROOT/default

step "Copying root filesystem (this may take a while)..."
tar -cf - -C "${ROOTFS}" . | tar -xpf - -C "${MNTTARGET}"

step "Writing bootloader configuration..."
mkdir -p "${MNTTARGET}/boot/zfs"
cp /boot/zfs/zpool.cache "${MNTTARGET}/boot/zfs/" 2>/dev/null || true

cat > "${MNTTARGET}/boot/loader.conf" << 'EOF'
# nOS Boot Loader
zfs_load="YES"
vfs.root.mountfrom="zfs:zroot/ROOT/default"
autoboot_delay="3"
beastie_disable="YES"
loader_logo="none"
kern.vty=vt
# VirtIO (QEMU)
virtio_load="YES"
virtio_pci_load="YES"
virtio_blk_load="YES"
virtio_net_load="YES"
virtio_random_load="YES"
nvme_load="YES"
# Audio
snd_hda_load="YES"
EOF

step "Sealing root dataset as read-only (immutable)..."
zfs set readonly=on zroot_build/ROOT/default

step "Exporting pool..."
zpool export zroot_build
mdconfig -d -u "${MD}"
MD=""

echo ""
echo "============================================"
echo "  Image created: ${IMAGE}"
echo "  Size: ${IMGSIZE}"
echo ""
echo "  Run in QEMU:"
echo "    qemu-system-x86_64 \\"
echo "      -m 2048 -smp 2 \\"
echo "      -hda ${IMAGE} \\"
echo "      -enable-kvm \\"
echo "      -vga virtio \\"
echo "      -device virtio-net,netdev=net0 \\"
echo "      -netdev user,id=net0"
echo "============================================"
