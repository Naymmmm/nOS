#!/usr/bin/env bash
# run-nos-desktop.sh — Boot the nOS desktop VM.
#
# VNC:  Connect to  localhost:5901  (any VNC client)
# SSH:  ssh -p 2222 root@localhost
#
# First run: sh build/boot-nos.sh   (installs NOSKERNEL + desktop packages)
set -euo pipefail

NOSDIR="$(cd "$(dirname "$0")/../.." && pwd)"
VMDIR="${NOSDIR}/dist/vm"
DISK="${VMDIR}/FreeBSD-14.3-RELEASE-arm64-aarch64-ufs.qcow2"
EFI="${VMDIR}/QEMU_EFI.fd"
EFIVARS="${VMDIR}/QEMU_EFI_VARS.fd"
SSH_PORT="${SSH_PORT:-2222}"
VNC_PORT="${VNC_PORT:-1}"   # :1 = TCP 5901
MEM="${MEM:-4G}"
JOBS="${JOBS:-4}"

[ -f "${DISK}" ]    || { echo "ERR: VM disk not found"; exit 1; }
[ -f "${EFI}" ]     || { echo "ERR: EFI firmware not found"; exit 1; }

KVM_FLAGS=()
if [ -w /dev/kvm ]; then
    KVM_FLAGS=(-enable-kvm -cpu host)
    echo "==> KVM enabled"
else
    KVM_FLAGS=(-cpu cortex-a72)
    echo "==> Software emulation (add user to kvm group for full speed)"
fi

echo "==> Booting nOS desktop VM"
echo "    VNC : connect to  localhost:590${VNC_PORT}"
echo "    SSH : ssh -p ${SSH_PORT} root@localhost"
echo ""

exec qemu-system-aarch64 \
    -machine virt,gic-version=3 \
    "${KVM_FLAGS[@]}" \
    -smp "${JOBS}" \
    -m "${MEM}" \
    -drive if=pflash,format=raw,file="${EFI}",readonly=on \
    -drive if=pflash,format=raw,file="${EFIVARS}" \
    -drive if=virtio,file="${DISK}",format=qcow2 \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-gpu-pci \
    -display "vnc=0.0.0.0:${VNC_PORT}" \
    -usb \
    -device usb-tablet \
    -serial null \
    -monitor none
