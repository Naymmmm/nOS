#!/bin/sh
#
# nOS Post-Install Configuration — Nosface Wayland DE
# Sets up the desktop environment for the newly created user
#

set -e

TARGET="${1:-/mnt}"
CFG="/tmp/nos-install/install.conf"

[ -f "${CFG}" ] && . "${CFG}"

log() { echo "  [postinstall] $*"; }

# ---------------------------------------------------------------------------
# Desktop skeleton
# ---------------------------------------------------------------------------
setup_desktop() {
    local home="${TARGET}/home/${USERNAME}"
    local skel="${TARGET}/usr/share/nosface"

    log "Creating home directories..."
    mkdir -p \
        "${home}/.config/nosface" \
        "${home}/.config/gtk-3.0" \
        "${home}/.local/share/nosface/themes/dark/wallpaper" \
        "${home}/.local/share/nosface/themes/light/wallpaper" \
        "${home}/Desktop" \
        "${home}/Documents" \
        "${home}/Downloads" \
        "${home}/Pictures" \
        "${home}/Music" \
        "${home}/Videos"

    log "Installing GTK settings..."
    cat > "${home}/.config/gtk-3.0/settings.ini" << 'EOF'
[Settings]
gtk-theme-name=Nosface-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Inter 11
gtk-cursor-theme-name=Bibata-Modern-Classic
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=true
gtk-enable-animations=true
EOF

    log "Installing GTK2 theme fallback..."
    cat > "${home}/.gtkrc-2.0" << 'EOF'
gtk-theme-name="Nosface-Dark"
gtk-icon-theme-name="Papirus-Dark"
gtk-font-name="Inter 11"
gtk-cursor-theme-name="Bibata-Modern-Classic"
gtk-cursor-theme-size=24
EOF

    log "Writing .profile..."
    cat > "${home}/.profile" << 'EOF'
# nOS user profile
export PATH="${HOME}/.local/bin:${PATH}"
export XDG_CONFIG_HOME="${HOME}/.config"
export XDG_DATA_HOME="${HOME}/.local/share"
export XDG_CACHE_HOME="${HOME}/.cache"
export EDITOR="gedit"
export PAGER="less"
export NOS_THEME="dark"

# Wayland
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Nosface
export GDK_BACKEND=wayland
export QT_QPA_PLATFORM=wayland
export MOZ_ENABLE_WAYLAND=1
export ELECTRON_OZONE_PLATFORM_HINT=wayland
EOF

    log "Fixing ownership..."
    chroot "${TARGET}" chown -R "${USERNAME}:${USERNAME}" \
        "/home/${USERNAME}" 2>/dev/null || \
        chown -R 1001:1001 "${home}"
}

# ---------------------------------------------------------------------------
# Install Nosface themes system-wide
# ---------------------------------------------------------------------------
setup_themes() {
    log "Installing Nosface themes..."
    local dest="${TARGET}/usr/share/nosface/themes"
    mkdir -p "${dest}/dark" "${dest}/light"

    # Copy from the nOS repo (assumed mounted or chroot accessible)
    _src="${TARGET}/usr/share/nosface/src/themes"
    for t in dark light; do
        [ -f "${_src}/${t}/theme.css"  ] && \
            cp "${_src}/${t}/theme.css"  "${dest}/${t}/theme.css"
        [ -f "${_src}/${t}/colors.sh" ] && \
            cp "${_src}/${t}/colors.sh" "${dest}/${t}/colors.sh" && \
            chmod +x "${dest}/${t}/colors.sh"
    done

    # Generate default wallpapers with ImageMagick
    setup_wallpapers "${dest}"
}

# ---------------------------------------------------------------------------
# Wallpapers
# ---------------------------------------------------------------------------
setup_wallpapers() {
    local dest="$1"
    log "Generating default wallpapers..."

    if chroot "${TARGET}" command -v convert >/dev/null 2>&1; then
        chroot "${TARGET}" convert -size 1920x1080 \
            gradient:'#08081a-#12143a' \
            "${dest}/dark/wallpaper/default.png"  2>/dev/null || true
        chroot "${TARGET}" convert -size 1920x1080 \
            gradient:'#dbeafe-#f0f4ff' \
            "${dest}/light/wallpaper/default.png" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# sudo for wheel
# ---------------------------------------------------------------------------
setup_sudo() {
    log "Enabling sudo for wheel group..."
    mkdir -p "${TARGET}/etc/sudoers.d"
    printf '%%wheel ALL=(ALL:ALL) ALL\n' \
        > "${TARGET}/etc/sudoers.d/10-wheel"
    chmod 440 "${TARGET}/etc/sudoers.d/10-wheel"
}

# ---------------------------------------------------------------------------
# Wayland session entry (for greetd / display managers)
# ---------------------------------------------------------------------------
setup_session() {
    log "Registering Nosface Wayland session..."
    mkdir -p "${TARGET}/usr/share/wayland-sessions"
    cat > "${TARGET}/usr/share/wayland-sessions/nosface.desktop" << 'EOF'
[Desktop Entry]
Name=Nosface
Comment=nOS Nosface Wayland Desktop
Exec=/usr/local/bin/nos-session
Type=Application
DesktopNames=Nosface
EOF

    install -m 755 \
        "${TARGET}/usr/share/nosface/desktop/session/nos-session" \
        "${TARGET}/usr/local/bin/nos-session" 2>/dev/null || true

    # Install noscomp if built
    [ -f "${TARGET}/usr/share/nosface/compositor/build/noscomp" ] && \
        install -m 755 \
            "${TARGET}/usr/share/nosface/compositor/build/noscomp" \
            "${TARGET}/usr/local/bin/noscomp"
}

# ---------------------------------------------------------------------------
# greetd setup
# ---------------------------------------------------------------------------
setup_greetd() {
    log "Configuring greetd..."
    mkdir -p "${TARGET}/etc/greetd"
    cp "${TARGET}/usr/share/nosface/display-manager/greetd/config.toml" \
       "${TARGET}/etc/greetd/config.toml" 2>/dev/null || true

    mkdir -p "${TARGET}/usr/share/nosface/display-manager/greetd"
    cp "${TARGET}/usr/share/nosface/display-manager/greetd/style.css" \
       "${TARGET}/usr/share/nosface/display-manager/greetd/style.css" 2>/dev/null || true

    # Enable greetd service (systemd)
    if [ -d "${TARGET}/etc/systemd/system" ]; then
        ln -sf /usr/lib/systemd/system/greetd.service \
               "${TARGET}/etc/systemd/system/display-manager.service" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# Install shell component launchers
# ---------------------------------------------------------------------------
setup_shell_launchers() {
    log "Installing shell component launchers..."
    local bindir="${TARGET}/usr/local/bin"
    local sharedir="${TARGET}/usr/share/nosface/shell"
    mkdir -p "${bindir}"

    for comp in nosface-bar nosface-dock nosface-launcher nosface-notify; do
        local pydir="${sharedir}/${comp}"
        local script="${pydir}/${comp##nosface-}.py"
        # Correct script name
        case "${comp}" in
            nosface-bar)      script="${pydir}/bar.py" ;;
            nosface-dock)     script="${pydir}/dock.py" ;;
            nosface-launcher) script="${pydir}/launcher.py" ;;
            nosface-notify)   script="${pydir}/notify.py" ;;
        esac
        cat > "${bindir}/${comp}" << EOF
#!/bin/sh
exec python3 "${script}" "\$@"
EOF
        chmod +x "${bindir}/${comp}"
    done
}

# ---------------------------------------------------------------------------
# First-run wizard autostart
# ---------------------------------------------------------------------------
setup_wizard_autostart() {
    log "Configuring first-run wizard autostart..."
    local home="${TARGET}/home/${USERNAME}"
    local flag="${home}/.config/nosface/.setup-done"
    local autostart="${home}/.config/nosface/autostart.sh"

    mkdir -p "${home}/.config/nosface"
    cat > "${autostart}" << 'AUTOEOF'
#!/bin/sh
# Nosface autostart — run on session start
FLAG="${HOME}/.config/nosface/.setup-done"
if [ ! -f "${FLAG}" ]; then
    nos_setup_wizard &
    touch "${FLAG}"
fi
AUTOEOF
    chmod +x "${autostart}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    log "Starting Nosface post-install configuration..."
    setup_desktop
    setup_themes
    setup_sudo
    setup_session
    setup_greetd
    setup_shell_launchers
    setup_wizard_autostart
    log "Post-install complete."
}

main "$@"
