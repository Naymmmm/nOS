#!/usr/bin/env bash
# boot-nos.sh — Set up and launch the nOS desktop VM.
#
# First run: installs NOSKERNEL + nosface desktop packages, then reboots into
# the full nOS desktop accessible via VNC at localhost:5901.
#
# Subsequent runs: just boots straight to the desktop.
#
# Prerequisites:
#   sh build/setup-build-vm.sh   (SSH key must be injected first)
set -euo pipefail

NOSDIR="$(cd "$(dirname "$0")/.." && pwd)"
VMDIR="${NOSDIR}/dist/vm"
BUILDDIR="${NOSDIR}/.nos-build"
DISK="${VMDIR}/FreeBSD-14.3-RELEASE-arm64-aarch64-ufs.qcow2"
SSH_KEY="${BUILDDIR}/nos-build-key"
KEYMARK="${BUILDDIR}/.ssh-injected"
DESKTOP_MARK="${BUILDDIR}/.desktop-installed"
SSH_PORT="${SSH_PORT:-2222}"
VNC_DISPLAY="${VNC_DISPLAY:-1}"
HTTP_PORT="${HTTP_PORT:-8080}"

RED='\033[1;31m'; GREEN='\033[1;32m'; CYAN='\033[1;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { printf "${CYAN}==> %s${NC}\n" "$*"; }
ok()   { printf "${GREEN} ✓  %s${NC}\n" "$*"; }
warn() { printf "${YELLOW}    %s${NC}\n" "$*"; }
die()  { printf "${RED}ERR: %s${NC}\n" "$*" >&2; exit 1; }

[ -f "${KEYMARK}" ] || die "VM not configured. Run:  sh build/setup-build-vm.sh"
[ -f "${SSH_KEY}" ] || die "SSH key missing: ${SSH_KEY}"
[ -f "${DISK}" ]    || die "VM disk not found: ${DISK}"

SSH_OPTS=(
    -i "${SSH_KEY}"
    -p "${SSH_PORT}"
    -o StrictHostKeyChecking=no
    -o UserKnownHostsFile=/dev/null
    -o LogLevel=ERROR
    -o ConnectTimeout=5
    -o ServerAliveInterval=30
)

# ── Cleanup ────────────────────────────────────────────────────────────────────
QEMU_PID=""
HTTP_PID=""
cleanup() {
    [ -n "${HTTP_PID}" ] && kill "${HTTP_PID}" 2>/dev/null || true
    # Don't kill QEMU — user is still using the VM
}
trap cleanup EXIT INT TERM

# ── First-time setup: start HTTP server ───────────────────────────────────────
if [ ! -f "${DESKTOP_MARK}" ]; then
    log "Starting HTTP server on :${HTTP_PORT}..."
    python3 -m http.server "${HTTP_PORT}" --directory "${NOSDIR}" 2>/dev/null &
    HTTP_PID=$!
    sleep 0.5
fi

# ── Boot VM with VNC + GPU ────────────────────────────────────────────────────
log "Booting nOS desktop VM..."

KVM_FLAGS=()
if [ -w /dev/kvm ]; then
    KVM_FLAGS=(-enable-kvm -cpu host)
    ok "KVM enabled"
else
    KVM_FLAGS=(-cpu cortex-a72)
    warn "No KVM — add user to kvm group for better performance"
fi

EFI="${VMDIR}/QEMU_EFI.fd"
EFIVARS="${VMDIR}/QEMU_EFI_VARS.fd"

qemu-system-aarch64 \
    -machine virt,gic-version=3 \
    "${KVM_FLAGS[@]}" \
    -smp 4 \
    -m 4G \
    -drive if=pflash,format=raw,file="${EFI}",readonly=on \
    -drive if=pflash,format=raw,file="${EFIVARS}" \
    -drive if=virtio,file="${DISK}",format=qcow2 \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
    -device virtio-net-pci,netdev=net0 \
    -device virtio-gpu-pci \
    -display "vnc=0.0.0.0:${VNC_DISPLAY}" \
    -usb -device usb-tablet \
    -serial null \
    -monitor none \
    2>/dev/null &
QEMU_PID=$!

# ── Wait for SSH ───────────────────────────────────────────────────────────────
log "Waiting for VM to boot..."
TRIES=0
until ssh "${SSH_OPTS[@]}" root@localhost true 2>/dev/null; do
    [ "${TRIES}" -gt 150 ] && die "VM SSH timeout"
    [ $((TRIES % 15)) -eq 0 ] && printf " [${TRIES}s]\n" || printf "."
    TRIES=$((TRIES + 1))
    sleep 2
done
printf "\n"
ok "VM is up"

# ── First-time: install desktop ────────────────────────────────────────────────
if [ ! -f "${DESKTOP_MARK}" ]; then
    log "First-time setup: installing NOSKERNEL + nosface desktop..."
    log "(this installs packages from FreeBSD pkg — takes ~5-10 min)"

    ssh "${SSH_OPTS[@]}" root@localhost \
        "NOS_HOST=10.0.2.2 NOS_HTTP_PORT=${HTTP_PORT} \
         fetch -qo /tmp/nos-desktop-install.sh http://10.0.2.2:${HTTP_PORT}/dist/vm/nos-desktop-install.sh \
         && sh /tmp/nos-desktop-install.sh"

    ok "Desktop installed — rebooting into nOS..."
    ssh "${SSH_OPTS[@]}" root@localhost "reboot" 2>/dev/null || true
    sleep 5

    # Wait for VM to come back up after reboot
    log "Waiting for reboot..."
    TRIES=0
    until ssh "${SSH_OPTS[@]}" root@localhost true 2>/dev/null; do
        [ "${TRIES}" -gt 120 ] && die "Reboot timeout"
        TRIES=$((TRIES + 1))
        sleep 3
        printf "."
    done
    printf "\n"
    ok "VM rebooted"
    touch "${DESKTOP_MARK}"
fi

# ── Done ───────────────────────────────────────────────────────────────────────
VNC_TCP=$((5900 + VNC_DISPLAY))
printf "\n"
printf "${GREEN}╔══════════════════════════════════════════╗${NC}\n"
printf "${GREEN}║         nOS Desktop is running           ║${NC}\n"
printf "${GREEN}╠══════════════════════════════════════════╣${NC}\n"
printf "${GREEN}║  VNC:  localhost:%-5d                   ║${NC}\n" "${VNC_TCP}"
printf "${GREEN}║  SSH:  ssh -p %-5d root@localhost       ║${NC}\n" "${SSH_PORT}"
printf "${GREEN}╚══════════════════════════════════════════╝${NC}\n"
printf "\n"
printf "Connect with any VNC client. Press Ctrl-C to stop the VM.\n\n"

# Keep script alive (VNC session continues until user kills it)
wait "${QEMU_PID}"
