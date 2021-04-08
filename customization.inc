#!/bin/bash

ADDITIONAL_PACKAGES="\
x11-drivers/nvidia-drivers \
gnome-base/gnome \
sys-apps/pciutils \
sys-apps/usbutils \
sys-fs/btrfs-progs \
sys-fs/e2fsprogs \
sys-fs/ntfs3g \
sys-fs/ext4magic \
sys-fs/exfatprogs \
sys-process/htop \
sys-power/powertop \
sys-process/iotop \
sys-fs/ddrescue \
sys-apps/dcfldd \
app-misc/binwalk \
app-forensics/sleuthkit \
net-analyzer/nmap \
app-crypt/md5deep \
app-forensics/foremost \
app-forensics/scalpel \
sys-fs/cryptsetup \
sys-fs/lvm2 \
app-arch/unrar \
app-editors/vim \
media-gfx/gimp \
media-gfx/inkscape \
media-video/celluloid \
www-client/firefox \
app-office/libreoffice \
"

TARGET_PROFILE="default/linux/amd64/17.1/desktop/gnome/systemd"

# Change to =sys-kernel/gentoo-kernel-X.Y.Z for specific version
GENTOO_SOURCES_VER="sys-kernel/gentoo-kernel"


# This function will be invoked in the chroot environment when everything
# is built. You can add users, invoke various configuration actions here,
# and stuff. This is invoked before separating boot from root, and before
# removing /flashtoo directory.

# After this function returns, no other actions will be executed in the
# chroot. At the barest minimal, it should remove or replace /etc/resolv.conf
# file
function post_install_setup_actions() {
	post_install_setup_actions_custom_services
	post_install_setup_actions_systemd
	post_install_setup_actions_timezone_systemd
	post_install_setup_actions_networkmanager
}

function post_install_setup_actions_custom_services() {
	# Enable Xorg GDM greeter:
        systemctl enable gdm
        sed -i 's/#WaylandEnable=false/WaylandEnable=false/' /etc/gdm/custom.conf

        systemctl enable NetworkManager
}

function post_install_setup_actions_systemd() {
	# Let systemd not store much on the flash drive:
        sed -i 's/#Storage=external/Storage=none/' /etc/systemd/coredump.conf
        sed -i 's/#Storage=auto/Storage=volatile/' /etc/systemd/journald.conf
}

function post_install_setup_actions_timezone_systemd() {
	# Time zone
        ln -sf /usr/share/zoneinfo/Europe/Brussels /etc/localtime
        # Warning: a single portable linux may be booted on various machines!
        # Consider this:
        # one PC may use local time
        # other one may use UTC
        # you may snail-mail the flash drive to your acquaintance in Sudan
        # in general, do not trust clock & timezone!
}

function post_install_setup_actions_networkmanager() {
	# Link /etc/resolv.conf to NetworkManager directory
        rm -f /etc/resolv.conf
        ln -s /run/NetworkManager/resolv.conf /etc/resolv.conf
}
