#!/bin/sh
#
# nOS Installation Wizard
# Interactive TUI installer powered by dialog(1)
#

set -e

NOSVERSION="1.0.0"
TITLE="nOS ${NOSVERSION} Installation"
TMPDIR="/tmp/nos-install"
LOGFILE="${TMPDIR}/install.log"
CFG="${TMPDIR}/install.conf"
TARGET="/mnt"

mkdir -p "${TMPDIR}"
exec 2>>"${LOGFILE}"

# ---------------------------------------------------------------------------
# Utilities
# ---------------------------------------------------------------------------

die() {
    dialog --title "Fatal Error" \
        --msgbox "\nError: $1\n\nDetails in: ${LOGFILE}" 10 60
    exit 1
}

log() { echo "[$(date '+%H:%M:%S')] $*" >> "${LOGFILE}"; }

cfg_set() { echo "$1=$2" >> "${CFG}"; }

# ---------------------------------------------------------------------------
# Step 1: Welcome
# ---------------------------------------------------------------------------
step_welcome() {
    dialog \
        --backtitle "nOS Installation" \
        --title "Welcome to nOS" \
        --msgbox "\
\n\
    ███╗   ██╗ ██████╗ ███████╗\n\
    ████╗  ██║██╔═══██╗██╔════╝\n\
    ██╔██╗ ██║██║   ██║███████╗\n\
    ██║╚██╗██║██║   ██║╚════██║\n\
    ██║ ╚████║╚██████╔╝███████║\n\
    ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝\n\
\n\
    Version ${NOSVERSION}  |  Based on FreeBSD\n\
\n\
  A simple, beautiful, and open-source\n\
  desktop operating system.\n\
\n\
  This wizard will guide you through\n\
  installation. Press Enter to begin.\n\
" 22 62
}

# ---------------------------------------------------------------------------
# Step 2: License
# ---------------------------------------------------------------------------
step_license() {
    dialog \
        --backtitle "nOS Installation" \
        --title "Open Source License" \
        --yesno "\
nOS is free and open-source software.\n\
\n\
The nOS-specific components are released under the\n\
BSD 2-Clause License. The FreeBSD base system is\n\
covered by the BSD License and related licenses.\n\
\n\
Full license text is available at:\n\
  /usr/local/share/nos/LICENSE\n\
\n\
Do you accept the license agreement?" \
        14 60 || { dialog --msgbox "Installation cancelled." 6 40; exit 0; }
}

# ---------------------------------------------------------------------------
# Step 3: Disk selection
# ---------------------------------------------------------------------------
step_disk() {
    DISKS=""
    for d in $(sysctl -n kern.disks | tr ' ' '\n' | grep -E '^(ada|da|nvd|vtblk|mmcsd)'); do
        sz=$(diskinfo "${d}" 2>/dev/null | awk '{printf "%.0f GB", $3/1000/1000/1000}')
        DISKS="${DISKS} ${d} \"${sz}\""
    done

    [ -z "${DISKS}" ] && die "No suitable disks found."

    DISK=$(eval "dialog \
        --backtitle 'nOS Installation' \
        --title 'Select Installation Disk' \
        --menu '\nChoose the disk for nOS installation.\n\nWARNING: All existing data will be erased!\n' \
        16 60 6 \
        ${DISKS} \
        3>&1 1>&2 2>&3") || die "No disk selected."

    cfg_set DISK "${DISK}"
    log "Disk selected: ${DISK}"
}

# ---------------------------------------------------------------------------
# Step 4: Partition layout
# ---------------------------------------------------------------------------
step_partition() {
    MODE=$(dialog \
        --backtitle "nOS Installation" \
        --title "Disk Layout" \
        --menu "\nHow should the disk be partitioned?" \
        11 58 2 \
        "auto"   "Automatic ZFS layout (recommended)" \
        "manual" "Manual partitioning (advanced)" \
        3>&1 1>&2 2>&3) || MODE="auto"

    cfg_set PARTITION_MODE "${MODE}"
}

# ---------------------------------------------------------------------------
# Step 5: Hostname
# ---------------------------------------------------------------------------
step_hostname() {
    HOSTNAME=$(dialog \
        --backtitle "nOS Installation" \
        --title "System Hostname" \
        --inputbox "\nEnter a hostname for this machine:" \
        8 50 "nos" \
        3>&1 1>&2 2>&3) || HOSTNAME="nos"

    cfg_set HOSTNAME "${HOSTNAME:-nos}"
}

# ---------------------------------------------------------------------------
# Step 6: Timezone
# ---------------------------------------------------------------------------
step_timezone() {
    # Use FreeBSD's tzsetup if available
    if [ -x /usr/sbin/tzsetup ]; then
        tzsetup
    fi
    TZ=$(readlink /etc/localtime | sed 's|.*/zoneinfo/||' 2>/dev/null || echo "UTC")
    cfg_set TIMEZONE "${TZ}"
    log "Timezone: ${TZ}"
}

# ---------------------------------------------------------------------------
# Step 7: Root password
# ---------------------------------------------------------------------------
step_root_password() {
    while true; do
        P1=$(dialog \
            --backtitle "nOS Installation" \
            --title "Root Password" \
            --passwordbox "\nSet the root administrator password:" \
            8 52 3>&1 1>&2 2>&3)
        P2=$(dialog \
            --backtitle "nOS Installation" \
            --title "Root Password" \
            --passwordbox "\nConfirm the root password:" \
            8 52 3>&1 1>&2 2>&3)
        [ "${P1}" = "${P2}" ] && break
        dialog --msgbox "Passwords do not match. Try again." 6 45
    done
    cfg_set ROOT_PASSWORD "${P1}"
}

# ---------------------------------------------------------------------------
# Step 8: User account
# ---------------------------------------------------------------------------
step_user() {
    USERNAME=$(dialog \
        --backtitle "nOS Installation" \
        --title "Create User Account" \
        --inputbox "\nEnter a username (lowercase, no spaces):" \
        8 52 "" 3>&1 1>&2 2>&3) || die "No username provided."

    FULLNAME=$(dialog \
        --backtitle "nOS Installation" \
        --title "Create User Account" \
        --inputbox "\nEnter your full name:" \
        8 52 "" 3>&1 1>&2 2>&3) || FULLNAME="${USERNAME}"

    while true; do
        P1=$(dialog \
            --backtitle "nOS Installation" \
            --title "User Password" \
            --passwordbox "\nPassword for ${USERNAME}:" \
            8 52 3>&1 1>&2 2>&3)
        P2=$(dialog \
            --backtitle "nOS Installation" \
            --title "User Password" \
            --passwordbox "\nConfirm password for ${USERNAME}:" \
            8 52 3>&1 1>&2 2>&3)
        [ "${P1}" = "${P2}" ] && break
        dialog --msgbox "Passwords do not match. Try again." 6 45
    done

    cfg_set USERNAME "${USERNAME}"
    cfg_set FULLNAME "${FULLNAME}"
    cfg_set USER_PASSWORD "${P1}"
}

# ---------------------------------------------------------------------------
# Step 9: Network
# ---------------------------------------------------------------------------
step_network() {
    IFACES=""
    for i in $(ifconfig -l | tr ' ' '\n' | grep -v '^lo'); do
        IFACES="${IFACES} ${i} 'Network interface'"
    done
    IFACES="${IFACES} skip 'Skip network configuration'"

    IFACE=$(eval "dialog \
        --backtitle 'nOS Installation' \
        --title 'Network Configuration' \
        --menu '\nSelect a network interface to configure:' \
        13 58 6 \
        ${IFACES} \
        3>&1 1>&2 2>&3") || IFACE="skip"

    if [ "${IFACE}" != "skip" ]; then
        NET_MODE=$(dialog \
            --backtitle "nOS Installation" \
            --title "Network Mode: ${IFACE}" \
            --menu "\nConfigure IP address:" \
            10 50 2 \
            "dhcp"   "Automatic (DHCP)" \
            "static" "Manual (Static IP)" \
            3>&1 1>&2 2>&3) || NET_MODE="dhcp"

        cfg_set NET_IFACE "${IFACE}"
        cfg_set NET_MODE  "${NET_MODE}"

        if [ "${NET_MODE}" = "static" ]; then
            IP=$(dialog --inputbox "IP Address:"       8 46 "" 3>&1 1>&2 2>&3)
            NM=$(dialog --inputbox "Subnet Mask:"      8 46 "255.255.255.0" 3>&1 1>&2 2>&3)
            GW=$(dialog --inputbox "Default Gateway:"  8 46 "" 3>&1 1>&2 2>&3)
            DNS=$(dialog --inputbox "DNS Server:"      8 46 "1.1.1.1" 3>&1 1>&2 2>&3)
            cfg_set NET_IP  "${IP}"
            cfg_set NET_MASK "${NM}"
            cfg_set NET_GW  "${GW}"
            cfg_set NET_DNS "${DNS}"
        fi
    fi
}

# ---------------------------------------------------------------------------
# Step 10: Confirm
# ---------------------------------------------------------------------------
step_confirm() {
    # shellcheck disable=SC1090
    . "${CFG}"

    dialog \
        --backtitle "nOS Installation" \
        --title "Confirm Installation" \
        --yesno "\
Review your choices:\n\
\n\
  Disk     : /dev/${DISK}  (${PARTITION_MODE} layout)\n\
  Hostname : ${HOSTNAME}\n\
  Timezone : ${TIMEZONE}\n\
  User     : ${USERNAME}  (${FULLNAME})\n\
  Network  : ${NET_IFACE:-not configured}\n\
\n\
!! ALL DATA ON /dev/${DISK} WILL BE ERASED !!\n\
\n\
Proceed with installation?" \
        17 58 || { dialog --msgbox "Installation cancelled." 6 40; exit 0; }
}

# ---------------------------------------------------------------------------
# Step 11: Install
# ---------------------------------------------------------------------------
step_install() {
    # shellcheck disable=SC1090
    . "${CFG}"

    (
        echo "XXX"; echo "5"; echo "Clearing disk..."; echo "XXX"
        gpart destroy -F "/dev/${DISK}" 2>/dev/null || true
        dd if=/dev/zero of="/dev/${DISK}" bs=1M count=4 2>/dev/null

        echo "XXX"; echo "10"; echo "Creating partition table..."; echo "XXX"
        gpart create -s gpt "/dev/${DISK}"
        gpart add -t freebsd-boot -s 512k  -l boot0  "/dev/${DISK}"
        gpart add -t efi          -s 256M  -l efi0   "/dev/${DISK}"
        gpart add -t freebsd-zfs          -l zroot0  "/dev/${DISK}"

        echo "XXX"; echo "15"; echo "Installing boot code..."; echo "XXX"
        gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 "/dev/${DISK}"
        newfs_msdos -F 32 -c 1 "/dev/${DISK}p2"
        mkdir -p /tmp/nos-efi
        mount_msdosfs "/dev/${DISK}p2" /tmp/nos-efi
        mkdir -p /tmp/nos-efi/EFI/BOOT
        cp /boot/loader.efi /tmp/nos-efi/EFI/BOOT/BOOTX64.EFI
        umount /tmp/nos-efi

        echo "XXX"; echo "22"; echo "Creating ZFS pool..."; echo "XXX"
        zpool create \
            -o ashift=12 -o autotrim=on \
            -O compression=lz4 -O atime=off \
            -O xattr=sa -O mountpoint=none \
            -R "${TARGET}" \
            zroot "/dev/${DISK}p3"

        echo "XXX"; echo "28"; echo "Creating filesystem datasets..."; echo "XXX"
        zfs create -o mountpoint=none           zroot/ROOT
        zfs create -o mountpoint=/              zroot/ROOT/default
        zfs create -o mountpoint=/home          zroot/home
        zfs create -o mountpoint=/var           zroot/var
        zfs create -o mountpoint=/var/log       zroot/var/log
        zfs create -o mountpoint=/var/db        zroot/var/db
        zfs create -o mountpoint=/var/tmp \
            -o exec=off -o setuid=off           zroot/var/tmp
        zfs create -o mountpoint=/tmp \
            -o exec=off -o setuid=off           zroot/tmp
        zfs create -o mountpoint=/usr/local     zroot/usrlocal
        zpool set bootfs=zroot/ROOT/default zroot
        zfs set canmount=noauto zroot/ROOT/default

        echo "XXX"; echo "35"; echo "Installing nOS base system..."; echo "XXX"
        if [ -f /nos/rootfs.txz ]; then
            tar -xpJf /nos/rootfs.txz -C "${TARGET}"
        else
            for set in base kernel; do
                fetch -q -o "${TMPDIR}/${set}.txz" \
                    "https://download.FreeBSD.org/releases/amd64/14.1-RELEASE/${set}.txz" \
                    >> "${LOGFILE}" 2>&1
                tar -xpJf "${TMPDIR}/${set}.txz" -C "${TARGET}"
            done
        fi

        echo "XXX"; echo "62"; echo "Configuring system..."; echo "XXX"

        # fstab
        cat > "${TARGET}/etc/fstab" << 'FSTAB'
# nOS fstab — auto-managed, do not edit manually
tmpfs  /tmp  tmpfs  rw,mode=1777  0  0
FSTAB

        # rc.conf
        cat > "${TARGET}/etc/rc.conf" << RCEOF
hostname="${HOSTNAME}"
zfs_enable="YES"
zfsd_enable="YES"
dbus_enable="YES"
lightdm_enable="YES"
moused_enable="YES"
ntpd_enable="YES"
ntpd_sync_on_start="YES"
syslogd_flags="-ss"
sendmail_enable="NONE"
clear_tmp_enable="YES"
dumpdev="NO"
RCEOF

        # Network
        if [ -n "${NET_IFACE}" ]; then
            if [ "${NET_MODE}" = "dhcp" ]; then
                printf 'ifconfig_%s="DHCP"\n' "${NET_IFACE}" \
                    >> "${TARGET}/etc/rc.conf"
            else
                printf 'ifconfig_%s="inet %s netmask %s"\ndefaultrouter="%s"\n' \
                    "${NET_IFACE}" "${NET_IP}" "${NET_MASK}" "${NET_GW}" \
                    >> "${TARGET}/etc/rc.conf"
                printf 'nameserver %s\n' "${NET_DNS}" \
                    > "${TARGET}/etc/resolv.conf"
            fi
        fi

        echo "XXX"; echo "68"; echo "Setting timezone..."; echo "XXX"
        cp "/usr/share/zoneinfo/${TIMEZONE:-UTC}" "${TARGET}/etc/localtime"
        echo "${TIMEZONE:-UTC}" > "${TARGET}/etc/timezone"

        echo "XXX"; echo "72"; echo "Setting passwords..."; echo "XXX"
        echo "${ROOT_PASSWORD}" | chroot "${TARGET}" pw usermod root -h 0

        echo "XXX"; echo "76"; echo "Creating user account..."; echo "XXX"
        chroot "${TARGET}" pw groupadd "${USERNAME}" -g 1001 2>/dev/null || true
        chroot "${TARGET}" pw useradd "${USERNAME}" \
            -u 1001 -g 1001 -G wheel,video,audio \
            -m -d "/home/${USERNAME}" \
            -s /bin/sh \
            -c "${FULLNAME}"
        echo "${USER_PASSWORD}" | chroot "${TARGET}" pw usermod "${USERNAME}" -h 0

        echo "XXX"; echo "80"; echo "Configuring bootloader..."; echo "XXX"
        mkdir -p "${TARGET}/boot/zfs"
        cp /boot/zfs/zpool.cache "${TARGET}/boot/zfs/" 2>/dev/null || true
        cat > "${TARGET}/boot/loader.conf" << 'LOADEREOF'
zfs_load="YES"
vfs.root.mountfrom="zfs:zroot/ROOT/default"
autoboot_delay="3"
beastie_disable="YES"
loader_logo="none"
kern.vty=vt
virtio_load="YES"
virtio_pci_load="YES"
virtio_blk_load="YES"
virtio_net_load="YES"
virtio_random_load="YES"
nvme_load="YES"
snd_hda_load="YES"
LOADEREOF

        echo "XXX"; echo "86"; echo "Applying desktop configuration..."; echo "XXX"
        sh /nos/installer/postinstall.sh "${TARGET}" >> "${LOGFILE}" 2>&1

        echo "XXX"; echo "95"; echo "Sealing root filesystem (immutable)..."; echo "XXX"
        zfs set readonly=on zroot/ROOT/default

        echo "XXX"; echo "98"; echo "Exporting ZFS pool..."; echo "XXX"
        zpool export zroot

        echo "XXX"; echo "100"; echo "Installation complete!"; echo "XXX"

    ) | dialog \
        --backtitle "nOS Installation" \
        --title "Installing nOS" \
        --gauge "\n  Installing nOS ${NOSVERSION}, please wait...\n" \
        10 65 0
}

# ---------------------------------------------------------------------------
# Step 12: Done
# ---------------------------------------------------------------------------
step_done() {
    dialog \
        --backtitle "nOS Installation" \
        --title "Installation Complete" \
        --msgbox "\
\n\
  nOS has been successfully installed!\n\
\n\
  Remove the installation media and\n\
  press Enter to reboot into your\n\
  new system.\n\
\n\
  Welcome to nOS.\n\
" 14 52
    reboot
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    [ "$(id -u)" = "0" ] || { echo "Error: must be root."; exit 1; }
    command -v dialog >/dev/null 2>&1 || { echo "Error: dialog not found."; exit 1; }

    > "${CFG}"   # reset config

    step_welcome
    step_license
    step_disk
    step_partition
    step_hostname
    step_timezone
    step_root_password
    step_user
    step_network
    step_confirm
    step_install
    step_done
}

main "$@"
