#!/bin/sh
# nos-desktop-install.sh — runs INSIDE the FreeBSD VM via SSH.
# Installs NOSKERNEL + nOS desktop (sway headless + wayvnc + nosface GTK3 components).
# VNC access: connect to VM port 5900 (wayvnc) — NOT QEMU's VNC port 5901.
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
# sway: headless Wayland compositor (no DRM needed with WLR_BACKENDS=headless)
# wayvnc: Wayland VNC server — users connect to port 5900
pkg install -y \
    sway                    \
    wayvnc                  \
    python3                 \
    py311-pygobject         \
    py311-dbus              \
    gtk3                    \
    gtk-layer-shell         \
    liberation-fonts-ttf    \
    xdg-user-dirs           \
    bash                    \
    dbus

# ── 4. Install nosface components ─────────────────────────────────────────────
# Each component goes in its own dir alongside its CSS so __file__ resolution works
log "Installing nosface shell components..."
NOSBIN="/usr/local/bin"
NOSSHARE="/usr/local/share/nosface"
mkdir -p "${NOSSHARE}/themes/dark" "${NOSSHARE}/themes/light"

for comp in bar dock launcher notify; do
    COMPDIR="${NOSSHARE}/${comp}"
    mkdir -p "${COMPDIR}"
    # Install Python module and CSS into component dir
    fetch -qo "${COMPDIR}/${comp}.py" "${BASE}/shell/nosface-${comp}/${comp}.py"
    fetch -qo "${COMPDIR}/style.css"  "${BASE}/shell/nosface-${comp}/style.css"
    chmod +x "${COMPDIR}/${comp}.py"
    # Wrapper in /usr/local/bin invokes the module with correct __file__ path
    printf '#!/bin/sh\nexec python3 "%s/%s.py" "$@"\n' "${COMPDIR}" "${comp}" \
        > "${NOSBIN}/nosface-${comp}"
    chmod +x "${NOSBIN}/nosface-${comp}"
done

# Setup wizard (its CSS is looked up via __file__ as nos_setup_wizard.css)
WIZDIR="${NOSSHARE}/wizard"
mkdir -p "${WIZDIR}"
fetch -qo "${WIZDIR}/nos_setup_wizard.py"  "${BASE}/installer/nos_setup_wizard.py"
fetch -qo "${WIZDIR}/nos_setup_wizard.css" "${BASE}/installer/nos_setup_wizard.css"
chmod +x "${WIZDIR}/nos_setup_wizard.py"
printf '#!/bin/sh\nexec python3 "%s/nos_setup_wizard.py" "$@"\n' "${WIZDIR}" \
    > "${NOSBIN}/nos-setup-wizard"
chmod +x "${NOSBIN}/nos-setup-wizard"

fetch -qo "${NOSSHARE}/themes/dark/theme.css"  "${BASE}/themes/dark/theme.css"
fetch -qo "${NOSSHARE}/themes/light/theme.css" "${BASE}/themes/light/theme.css"

# ── 5. Configure sway (headless mode) ─────────────────────────────────────────
log "Configuring sway compositor (headless + wayvnc)..."
mkdir -p /root/.config/sway

cat > /root/.config/sway/config << 'EOF'
# nOS sway config — headless mode with VNC via wayvnc
# Users connect via VNC to port 5900

# Headless virtual output (1920x1080)
output HEADLESS-1 {
    resolution 1920x1080
    background #08081a solid_color
}

# Disable title bars, set gaps
default_border none
default_floating_border none
gaps inner 8

# nosface session
exec /usr/local/bin/nos-session
EOF

# ── 6. nOS session launcher ───────────────────────────────────────────────────
log "Creating nOS session script..."
cat > /usr/local/bin/nos-session << 'SCRIPT'
#!/bin/sh
# nOS desktop session — started by sway exec
export GDK_BACKEND=wayland
export MOZ_ENABLE_WAYLAND=1
export WAYLAND_DISPLAY=wayland-1
export XDG_RUNTIME_DIR=/tmp/nos-runtime

# Start D-Bus if not running
if [ -z "${DBUS_SESSION_BUS_ADDRESS}" ]; then
    eval "$(dbus-launch --sh-syntax)"
fi

# Start wayvnc so users can connect on port 5900
wayvnc 0.0.0.0 5900 &

# Start nosface shell components (call wrappers directly, not via python3)
/usr/local/bin/nosface-bar     &
/usr/local/bin/nosface-dock    &
/usr/local/bin/nosface-notify  &

# First-run wizard
if [ ! -f "${HOME}/.nos-setup-done" ]; then
    /usr/local/bin/nos-setup-wizard
    touch "${HOME}/.nos-setup-done"
fi

wait
SCRIPT
chmod +x /usr/local/bin/nos-session

# ── 7. rc.d script — autostart sway on boot ───────────────────────────────────
log "Configuring sway autostart via rc.d..."

cat > /usr/local/etc/rc.d/nosde << 'RCSCRIPT'
#!/bin/sh
# PROVIDE: nosde
# REQUIRE: dbus LOGIN FILESYSTEMS
# KEYWORD: shutdown

. /etc/rc.subr

name="nosde"
rcvar="nosde_enable"
start_cmd="nosde_start"
stop_cmd="nosde_stop"

nosde_start()
{
    echo "Starting nOS desktop (sway headless + wayvnc)..."
    export WLR_BACKENDS=headless
    export WLR_RENDERER=pixman
    export XDG_RUNTIME_DIR=/tmp/nos-runtime
    mkdir -p "${XDG_RUNTIME_DIR}"
    chmod 700 "${XDG_RUNTIME_DIR}"
    daemon -u root -o /var/log/nos-sway.log \
        /usr/bin/env \
        WLR_BACKENDS=headless \
        WLR_RENDERER=pixman \
        XDG_RUNTIME_DIR=/tmp/nos-runtime \
        /usr/local/bin/sway
}

nosde_stop()
{
    pkill -f sway || true
    pkill -f wayvnc || true
}

load_rc_config $name
run_rc_command "$1"
RCSCRIPT
chmod +x /usr/local/etc/rc.d/nosde

# ── 8. rc.conf — enable dbus + nosde ─────────────────────────────────────────
log "Configuring autostart in rc.conf..."
if ! grep -q 'dbus_enable' /etc/rc.conf; then
    cat >> /etc/rc.conf << 'EOF'

# nOS desktop
dbus_enable="YES"
nosde_enable="YES"
EOF
fi

# ── Done ──────────────────────────────────────────────────────────────────────
log "nOS desktop installation complete."
log "Reboot to start the desktop:"
log "  reboot"
log ""
log "Then connect via VNC (wayvnc):  localhost:5900"
log "Note: QEMU VNC port 5901 shows the text console only."
