#!/usr/bin/env bash
# setup-build-vm.sh — One-time: inject SSH key into the FreeBSD build VM image.
# Must be run once before build-kernel.sh. Requires sudo (for qemu-nbd mount).
set -euo pipefail

NOSDIR="$(cd "$(dirname "$0")/.." && pwd)"
VMDIR="${NOSDIR}/dist/vm"
BUILDDIR="${NOSDIR}/.nos-build"
DISK="${VMDIR}/FreeBSD-14.3-RELEASE-arm64-aarch64-ufs.qcow2"
SSH_KEY="${BUILDDIR}/nos-build-key"
KEYMARK="${BUILDDIR}/.ssh-injected"

RED='\033[1;31m'; GREEN='\033[1;32m'; CYAN='\033[1;36m'; NC='\033[0m'
log() { printf "${CYAN}==> %s${NC}\n" "$*"; }
ok()  { printf "${GREEN} ✓  %s${NC}\n" "$*"; }
die() { printf "${RED}ERR: %s${NC}\n" "$*" >&2; exit 1; }

[ -f "${KEYMARK}" ] && { ok "VM already configured. Run build-kernel.sh."; exit 0; }

mkdir -p "${BUILDDIR}"

# Generate SSH keypair
if [ ! -f "${SSH_KEY}" ]; then
    log "Generating build SSH keypair..."
    ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -C "nos-build" -q
    ok "Key: ${SSH_KEY}"
fi
PUBKEY="$(cat "${SSH_KEY}.pub")"

# Mount image, inject key + enable root login
log "Injecting SSH key into VM image (needs sudo)..."
MNTDIR="$(mktemp -d)"
cleanup() { sudo umount "${MNTDIR}" 2>/dev/null || true; sudo qemu-nbd --disconnect /dev/nbd0 2>/dev/null || true; rmdir "${MNTDIR}" 2>/dev/null || true; }
trap cleanup EXIT

sudo modprobe nbd max_part=8
sudo qemu-nbd --connect=/dev/nbd0 "${DISK}"
sleep 1

# Detect partition (FreeBSD UFS is usually p3 or p4)
PART=""
for p in /dev/nbd0p4 /dev/nbd0p3 /dev/nbd0p2; do
    if sudo blkid "${p}" 2>/dev/null | grep -q ufs; then
        PART="${p}"; break
    fi
done
[ -z "${PART}" ] && die "Could not find UFS partition on ${DISK}"

sudo mount -t ufs -o ufstype=ufs2 "${PART}" "${MNTDIR}"

# Inject authorized_keys
sudo mkdir -p "${MNTDIR}/root/.ssh"
echo "${PUBKEY}" | sudo tee "${MNTDIR}/root/.ssh/authorized_keys" > /dev/null
sudo chmod 700 "${MNTDIR}/root/.ssh"
sudo chmod 600 "${MNTDIR}/root/.ssh/authorized_keys"

# Enable root SSH login
if ! sudo grep -q "^PermitRootLogin yes" "${MNTDIR}/etc/ssh/sshd_config" 2>/dev/null; then
    echo "PermitRootLogin yes" | sudo tee -a "${MNTDIR}/etc/ssh/sshd_config" > /dev/null
fi

# Ensure sshd is enabled
if ! sudo grep -q "sshd_enable" "${MNTDIR}/etc/rc.conf" 2>/dev/null; then
    echo 'sshd_enable="YES"' | sudo tee -a "${MNTDIR}/etc/rc.conf" > /dev/null
fi

ok "SSH key injected"
ok "PermitRootLogin yes"
ok "sshd_enable=YES"

touch "${KEYMARK}"
log "Setup complete. Run:  sh build/build-kernel.sh"
