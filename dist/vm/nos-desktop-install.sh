#!/bin/sh
# nos-desktop-install.sh — runs INSIDE the FreeBSD VM via SSH.
# Installs NOSKERNEL + nOS desktop (weston + nosface GTK3 components).
set -e

HOST="${NOS_HOST:-10.0.2.2}"
PORT="${NOS_HTTP_PORT:-8080}"
BASE="http://${HOST}:${PORT}"

log()  { printf '\033[1;32m==> %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERR: %s\033[0m\n' "$*" >&2; exit 1; }

# ── 1. Install NOSKERNEL ──────────────────────────────────────────────────────
log "Installing NOSKERNEL..."
OBJDIR="/usr/obj/usr/src/arm64.aarch64/sys/NOSKERNEL"

if [ -f "${OBJDIR}/kernel" ]; then
    cp /boot/kernel/kernel /boot/kernel/kernel.stock 2>/dev/null || true
    cp "${OBJDIR}/kernel"  /boot/kernel/kernel
    log "NOSKERNEL installed (stock kernel backed up as kernel.stock)"
else
    log "WARNING: Build artifacts not found at ${OBJDIR}"
    log "         Skipping kernel install — run build-kernel.sh first"
fi

# Announce nOS kernel in loader.conf
if ! grep -q 'kern.nos' /boot/loader.conf 2>/dev/null; then
    cat >> /boot/loader.conf << 'EOF'

# nOS
kern.nos.version="1.0"
hw.vga.textmode=0
EOF
fi

# ── 2. Bootstrap pkg ──────────────────────────────────────────────────────────
log "Bootstrapping pkg..."
env ASSUME_ALWAYS_YES=yes pkg bootstrap -f >/dev/null 2>&1 || true

# ── 3. Install desktop packages ───────────────────────────────────────────────
log "Installing desktop packages (this takes a while)..."
pkg install -y \
    weston                  \
    wayvnc                  \
    python3                 \
    py311-gobject3          \
    py311-dbus              \
    gtk3                    \
    gtk-layer-shell         \
    liberation-fonts-ttf    \
    xdg-user-dirs           \
    bash                    \
    dbus                    \
    2>/dev/null || pkg install -y \
    weston python3 py311-gobject3 gtk3 gtk-layer-shell liberation-fonts-ttf bash dbus

# ── 4. Install nosface components ─────────────────────────────────────────────
log "Installing nosface shell components..."
NOSBIN="/usr/local/bin"
NOSSHARE="/usr/local/share/nosface"
mkdir -p "${NOSSHARE}/themes/dark" "${NOSSHARE}/themes/light"

for comp in bar dock launcher notify; do
    fetch -qo "${NOSBIN}/nosface-${comp}" "${BASE}/shell/nosface-${comp}/${comp}.py"
    fetch -qo "${NOSSHARE}/${comp}.css"   "${BASE}/shell/nosface-${comp}/style.css"
    chmod +x "${NOSBIN}/nosface-${comp}"
done

fetch -qo "${NOSBIN}/nos-setup-wizard"    "${BASE}/installer/nos_setup_wizard.py"
fetch -qo "${NOSSHARE}/setup-wizard.css"  "${BASE}/installer/nos_setup_wizard.css"
chmod +x "${NOSBIN}/nos-setup-wizard"

fetch -qo "${NOSSHARE}/themes/dark/theme.css"  "${BASE}/themes/dark/theme.css"
fetch -qo "${NOSSHARE}/themes/light/theme.css" "${BASE}/themes/light/theme.css"

# ── 5. Configure weston ───────────────────────────────────────────────────────
log "Configuring weston compositor..."
mkdir -p /root/.config

cat > /root/.config/weston.ini << 'EOF'
[core]
idle-time=0
xwayland=false

[shell]
startup-animation=none
panel-position=none
background-color=0xff0d0d1a

[autolaunch]
path=/usr/local/bin/nos-session
EOF

# ── 6. nOS session launcher ───────────────────────────────────────────────────
log "Creating nOS session script..."
cat > /usr/local/bin/nos-session << 'SCRIPT'
#!/bin/sh
# nOS desktop session — started by weston autolaunch
export GDK_BACKEND=wayland
export MOZ_ENABLE_WAYLAND=1

# Start D-Bus if not running
if [ -z "${DBUS_SESSION_BUS_ADDRESS}" ]; then
    eval "$(dbus-launch --sh-syntax)"
fi

# Start nosface components
python3 /usr/local/bin/nosface-bar     &
python3 /usr/local/bin/nosface-dock    &
python3 /usr/local/bin/nosface-notify  &

# First-run wizard
if [ ! -f "${HOME}/.nos-setup-done" ]; then
    python3 /usr/local/bin/nos-setup-wizard
    touch "${HOME}/.nos-setup-done"
fi

# Keep session alive
wait
SCRIPT
chmod +x /usr/local/bin/nos-session

# ── 7. rc.conf — autostart weston on boot ────────────────────────────────────
log "Configuring weston autostart..."
if ! grep -q 'weston' /etc/rc.conf; then
    cat >> /etc/rc.conf << 'EOF'

# nOS desktop
dbus_enable="YES"
weston_enable="YES"
weston_user="root"
weston_args="--backend=drm --log=/var/log/weston.log"
EOF
fi

# ── Done ──────────────────────────────────────────────────────────────────────
log "nOS desktop installation complete."
log "Reboot to start the desktop:"
log "  reboot"
log ""
log "Then connect via VNC:  localhost:5901"
