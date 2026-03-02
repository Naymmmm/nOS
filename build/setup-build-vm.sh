#!/bin/bash
# setup-build-vm.sh — One-time: inject SSH key into the FreeBSD VM via console.
# No sudo, no mounting. Boots the VM, logs in via serial socket, injects key.
set -euo pipefail

NOSDIR="$(cd "$(dirname "$0")/.." && pwd)"
VMDIR="${NOSDIR}/dist/vm"
BUILDDIR="${NOSDIR}/.nos-build"
DISK="${VMDIR}/FreeBSD-14.3-RELEASE-arm64-aarch64-ufs.qcow2"
EFI="${VMDIR}/QEMU_EFI.fd"
EFIVARS="${VMDIR}/QEMU_EFI_VARS.fd"
SSH_KEY="${BUILDDIR}/nos-build-key"
KEYMARK="${BUILDDIR}/.ssh-injected"
SERIAL_SOCK="${BUILDDIR}/serial.sock"
SSH_PORT=2223  # temp port for setup

GREEN='\033[1;32m'; CYAN='\033[1;36m'; RED='\033[1;31m'; NC='\033[0m'
log() { printf "${CYAN}==> %s${NC}\n" "$*"; }
ok()  { printf "${GREEN} ✓  %s${NC}\n" "$*"; }
die() { printf "${RED}ERR: %s${NC}\n" "$*" >&2; exit 1; }

[ -f "${KEYMARK}" ] && { ok "VM already configured. Run build-kernel.sh."; exit 0; }

mkdir -p "${BUILDDIR}"

# ── Generate SSH keypair ───────────────────────────────────────────────────────
if [ ! -f "${SSH_KEY}" ]; then
    log "Generating SSH keypair..."
    ssh-keygen -t ed25519 -f "${SSH_KEY}" -N "" -C "nos-build" -q
    ok "Key: ${SSH_KEY}"
fi
PUBKEY="$(cat "${SSH_KEY}.pub")"

command -v python3 >/dev/null || die "python3 required"
command -v qemu-system-aarch64 >/dev/null || die "qemu-system-aarch64 required"

# ── Boot VM with serial on Unix socket ────────────────────────────────────────
log "Booting VM (serial on socket)..."
rm -f "${SERIAL_SOCK}"

KVM_FLAGS=(-cpu cortex-a72)
[ -w /dev/kvm ] && KVM_FLAGS=(-enable-kvm -cpu host)

# Boot WITHOUT network so UEFI skips PXE and goes straight to EFI\BOOT\BOOTAA64.EFI
# Network is added back after SSH key is injected (via a second boot for verification)
qemu-system-aarch64 \
    -machine virt,gic-version=3 \
    "${KVM_FLAGS[@]}" \
    -smp 4 -m 2G \
    -drive if=pflash,format=raw,file="${EFI}",readonly=on \
    -drive if=pflash,format=raw,file="${EFIVARS}" \
    -drive if=virtio,file="${DISK}",format=qcow2 \
    -chardev "socket,id=serial0,path=${SERIAL_SOCK},server=on,wait=off" \
    -serial chardev:serial0 \
    -monitor none \
    -display none \
    2>"${BUILDDIR}/qemu-setup.log" &
QEMU_PID=$!

cleanup() { kill "${QEMU_PID}" 2>/dev/null || true; rm -f "${SERIAL_SOCK}"; }
trap cleanup EXIT INT TERM

# ── Python: drive the serial console ─────────────────────────────────────────
log "Waiting for boot and injecting SSH key via console..."

python3 - "${SERIAL_SOCK}" "${PUBKEY}" << 'PYEOF'
import socket, sys, time, os

sock_path = sys.argv[1]
pubkey    = sys.argv[2]

# Wait for socket to appear
for _ in range(60):
    if os.path.exists(sock_path):
        break
    time.sleep(1)

s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.connect(sock_path)
s.settimeout(2)

def read_until(marker, timeout=180):
    buf = b""
    start = time.time()
    while time.time() - start < timeout:
        try:
            buf += s.recv(4096)
        except socket.timeout:
            pass
        if marker.encode() in buf:
            return buf.decode(errors="replace")
    raise TimeoutError(f"Timed out waiting for: {marker!r}\nGot: {buf[-500:]!r}")

def send(cmd):
    s.sendall((cmd + "\n").encode())
    time.sleep(0.3)

print("  waiting for login prompt...", flush=True)
read_until("login:", timeout=180)
send("root")

print("  logged in, configuring SSH...", flush=True)
read_until("#")

send("mkdir -p /root/.ssh && chmod 700 /root/.ssh")
read_until("#")
send(f"echo '{pubkey}' > /root/.ssh/authorized_keys")
read_until("#")
send("chmod 600 /root/.ssh/authorized_keys")
read_until("#")
send("grep -q 'PermitRootLogin yes' /etc/ssh/sshd_config || echo 'PermitRootLogin yes' >> /etc/ssh/sshd_config")
read_until("#")
send("grep -q 'sshd_enable' /etc/rc.conf || echo 'sshd_enable=\"YES\"' >> /etc/rc.conf")
read_until("#")
send("service sshd start 2>/dev/null || service sshd restart 2>/dev/null || true")
read_until("#")
send("echo NOS_SETUP_DONE")
read_until("NOS_SETUP_DONE")

print("  SSH configured!", flush=True)
PYEOF

# ── Shutdown no-network VM ────────────────────────────────────────────────────
log "Shutting down setup VM..."
wait "${QEMU_PID}" 2>/dev/null || true
sleep 2

# ── Boot WITH network to verify SSH ──────────────────────────────────────────
log "Rebooting with network to verify SSH..."
SSH_OPTS=(-i "${SSH_KEY}" -p "${SSH_PORT}" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=10)

qemu-system-aarch64 \
    -machine virt,gic-version=3 \
    "${KVM_FLAGS[@]}" \
    -smp 4 -m 2G \
    -drive if=pflash,format=raw,file="${EFI}",readonly=on \
    -drive if=pflash,format=raw,file="${EFIVARS}" \
    -drive if=none,id=disk0,file="${DISK}",format=qcow2 \
    -device virtio-blk-pci,drive=disk0,bootindex=0 \
    -netdev "user,id=net0,hostfwd=tcp::${SSH_PORT}-:22" \
    -device virtio-net-pci,netdev=net0,romfile=,bootindex=99 \
    -serial null -monitor none -display none \
    2>>"${BUILDDIR}/qemu-setup.log" &
QEMU_PID=$!

for i in $(seq 1 60); do
    if ssh "${SSH_OPTS[@]}" root@localhost true 2>/dev/null; then
        ok "SSH verified"
        break
    fi
    sleep 3
    [ "${i}" -eq 60 ] && die "SSH verification timed out"
    printf "."
done
printf "\n"

ssh "${SSH_OPTS[@]}" root@localhost "shutdown -p now" 2>/dev/null || true
wait "${QEMU_PID}" 2>/dev/null || true
trap - EXIT INT TERM

touch "${KEYMARK}"
ok "VM setup complete"
log "Run:  bash build/build-kernel.sh   or   bash build/boot-nos.sh"
