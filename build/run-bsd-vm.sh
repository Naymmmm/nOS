#!/bin/sh
# run-bsd-vm.sh — Launch the FreeBSD build VM
# The VM shares the nOS repo and dist/kernel output dir via 9p virtfs.
# Serial console output is shown in the terminal.

set -e

NOSDIR="$(cd "$(dirname "$0")/.." && pwd)"
VMDIR="${NOSDIR}/dist/vm"
OUTDIR="${NOSDIR}/dist/kernel"
EFI="${VMDIR}/QEMU_EFI.fd"
EFIVARS="${VMDIR}/QEMU_EFI_VARS.fd"
DISK="${VMDIR}/FreeBSD-14.3-RELEASE-arm64-aarch64-ufs.qcow2"
JOBS="$(nproc)"
MEM="${MEM:-8G}"

mkdir -p "${OUTDIR}"

echo "==> Launching FreeBSD 14.3 build VM"
echo "    Disk: ${DISK}"
echo "    EFI:  ${EFI}"
echo "    RAM:  ${MEM}   CPUs: ${JOBS}"
echo "    nOS repo shared at: nos -> /mnt/nos"
echo "    Output dir shared at: out -> /mnt/out"
echo ""
echo "==> Login: root (no password on fresh image)"
echo "==> Run inside VM:  sh /mnt/nos/dist/vm/nos-bsd-build.sh"
echo ""

# Use KVM if accessible, else fall back to software emulation (slower)
KVM_FLAGS=""
if [ -w /dev/kvm ]; then
    KVM_FLAGS="-enable-kvm -cpu host"
    echo "==> KVM acceleration enabled"
else
    KVM_FLAGS="-cpu cortex-a72"
    echo "==> WARNING: KVM not accessible — running in software emulation (add user to kvm group for full speed)"
fi

exec qemu-system-aarch64 \
    -machine virt,gic-version=3 \
    ${KVM_FLAGS} \
    -smp "${JOBS}" \
    -m "${MEM}" \
    -nographic \
    -drive if=pflash,format=raw,file="${EFI}",readonly=on \
    -drive if=pflash,format=raw,file="${EFIVARS}" \
    -drive if=virtio,file="${DISK}",format=qcow2 \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -fsdev local,id=nos,path="${NOSDIR}",security_model=mapped-xattr \
    -device virtio-9p-pci,fsdev=nos,mount_tag=nos \
    -fsdev local,id=out,path="${OUTDIR}",security_model=mapped-xattr \
    -device virtio-9p-pci,fsdev=out,mount_tag=out \
    -serial mon:stdio
