#!/bin/bash
# build-kernel.sh — Fully automated nOS FreeBSD 15.0 kernel build.
#
# First run:  sh build/setup-build-vm.sh   (one-time SSH setup, needs sudo)
# Every run:  sh build/build-kernel.sh     (no sudo required)
#
# What it does:
#   1. Starts HTTP server to serve repo files to the VM
#   2. Boots the FreeBSD 15.0 QEMU VM with SSH port forwarding
#   3. Waits for the VM SSH to become available
#   4. Runs the kernel build inside the VM via SSH
#   5. SCPs the finished kernel back to dist/kernel/ (no sudo, no mounting)
#   6. Powers off the VM cleanly via SSH
set -euo pipefail

NOSDIR="$(cd "$(dirname "$0")/.." && pwd)"
VMDIR="${NOSDIR}/dist/vm"
OUTDIR="${NOSDIR}/dist/kernel"
BUILDDIR="${NOSDIR}/.nos-build"
DISK="${VMDIR}/FreeBSD-14.3-RELEASE-arm64-aarch64-ufs.qcow2"
EFI="${VMDIR}/QEMU_EFI.fd"
EFIVARS="${VMDIR}/QEMU_EFI_VARS.fd"
SSH_KEY="${BUILDDIR}/nos-build-key"
KEYMARK="${BUILDDIR}/.ssh-injected"
SSH_PORT="${SSH_PORT:-2222}"
HTTP_PORT="${HTTP_PORT:-8080}"
MEM="${MEM:-8G}"
JOBS="${JOBS:-$(nproc)}"

RED='\033[1;31m'; GREEN='\033[1;32m'; CYAN='\033[1;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { printf "${CYAN}==> %s${NC}\n" "$*"; }
ok()   { printf "${GREEN} ✓  %s${NC}\n" "$*"; }
warn() { printf "${YELLOW}    %s${NC}\n" "$*"; }
die()  { printf "${RED}ERR: %s${NC}\n" "$*" >&2; exit 1; }

# ── Preflight ──────────────────────────────────────────────────────────────────
[ -f "${KEYMARK}" ]  || die "VM not configured. Run:  sh build/setup-build-vm.sh"
[ -f "${SSH_KEY}" ]  || die "SSH key missing: ${SSH_KEY}"
[ -f "${DISK}" ]     || die "VM disk not found: ${DISK}"
[ -f "${EFI}" ]      || die "EFI firmware not found: ${EFI}"
command -v qemu-system-aarch64 >/dev/null || die "qemu-system-aarch64 not found"
command -v python3             >/dev/null || die "python3 not found"
command -v ssh                 >/dev/null || die "ssh not found"
command -v scp                 >/dev/null || die "scp not found"

mkdir -p "${OUTDIR}"

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
    [ -n "${HTTP_PID}" ]  && kill "${HTTP_PID}"  2>/dev/null || true
    [ -n "${QEMU_PID}" ]  && kill "${QEMU_PID}"  2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ── 1. HTTP server ─────────────────────────────────────────────────────────────
log "Starting HTTP server on :${HTTP_PORT}..."
python3 -m http.server "${HTTP_PORT}" --directory "${NOSDIR}" 2>/dev/null &
HTTP_PID=$!
sleep 0.5
curl -sf "http://localhost:${HTTP_PORT}/build/config/NOSKERNEL" >/dev/null \
    || die "HTTP server failed to start"
ok "HTTP server up (pid ${HTTP_PID})"

# ── 2. KVM check ───────────────────────────────────────────────────────────────
KVM_FLAGS=()
if [ -w /dev/kvm ]; then
    KVM_FLAGS=(-enable-kvm -cpu host)
    ok "KVM enabled"
else
    KVM_FLAGS=(-cpu cortex-a72)
    warn "KVM not accessible — run 'sudo usermod -aG kvm ${USER}' for full speed"
fi

# ── 3. Boot VM ─────────────────────────────────────────────────────────────────
log "Booting FreeBSD 15.0 build VM (${JOBS} CPUs / ${MEM} RAM)..."
qemu-system-aarch64 \
    -machine virt,gic-version=3 \
    "${KVM_FLAGS[@]}" \
    -smp "${JOBS}" \
    -m "${MEM}" \
    -nographic \
    -drive if=pflash,format=raw,file="${EFI}",readonly=on \
    -drive if=pflash,format=raw,file="${EFIVARS}" \
    -drive if=none,id=disk0,file="${DISK}",format=qcow2 \
    -device virtio-blk-pci,drive=disk0,bootindex=0 \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
    -device virtio-net-pci,netdev=net0,bootindex=99 \
    -serial null \
    -monitor none \
    -display none \
    2>/dev/null &
QEMU_PID=$!

# ── 4. Wait for SSH ────────────────────────────────────────────────────────────
log "Waiting for VM SSH on port ${SSH_PORT}..."
TRIES=0
until ssh "${SSH_OPTS[@]}" root@localhost true 2>/dev/null; do
    TRIES=$((TRIES + 1))
    [ "${TRIES}" -gt 180 ] && die "SSH timeout after 6 min — check VM boots correctly"
    [ $((TRIES % 15)) -eq 0 ] && printf " [${TRIES}s elapsed]\n" || printf "."
    sleep 2
done
printf "\n"
ok "VM is up"

# ── 5. Run build ───────────────────────────────────────────────────────────────
log "Running kernel build on VM..."
ssh "${SSH_OPTS[@]}" root@localhost \
    "NOS_AUTO_BUILD=1 fetch -qo /tmp/build.sh http://10.0.2.2:${HTTP_PORT}/dist/vm/nos-bsd-build-http.sh \
     && sh /tmp/build.sh"
ok "Build finished"

# ── 6. SCP artifacts back ──────────────────────────────────────────────────────
log "Fetching artifacts via SCP..."
scp "${SSH_OPTS[@]}" \
    "root@localhost:/root/kernel-out/NOSKERNEL" \
    "${OUTDIR}/NOSKERNEL"
scp "${SSH_OPTS[@]}" \
    "root@localhost:/root/kernel-out/kernel-build.log" \
    "${OUTDIR}/kernel-build.log" 2>/dev/null || true
ok "Kernel: ${OUTDIR}/NOSKERNEL  ($(du -sh "${OUTDIR}/NOSKERNEL" | cut -f1))"

# ── 7. Shutdown ────────────────────────────────────────────────────────────────
log "Shutting down VM..."
ssh "${SSH_OPTS[@]}" root@localhost "shutdown -p now" 2>/dev/null || true
wait "${QEMU_PID}" 2>/dev/null || true
QEMU_PID=""
ok "VM off"

printf "\n${GREEN}All done.${NC} Kernel at dist/kernel/NOSKERNEL\n"
