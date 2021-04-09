#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

function part_disk() {
# Create new MBR partition table
# Create partition 1, 128MB
# Make it bootable
# Create partition 2, rest of device size
# Write partition table
# Overwrite all filesystem signatures
echo "o
n
p
1

+128M
a
n
p
2


w" | fdisk -w always -W always ${DISK}
}

function discover_internal() {
	lsblk -n -l -o NAME ${DISK} | grep -v `basename ${DISK}`$ | {
		read PART1
		read PART2
		FAT_BOOT_PART="`dirname ${DISK}`/${PART1}"
		F2FS_ROOT_PART="`dirname ${DISK}`/${PART2}"
		echo "FAT_BOOT_PART=$FAT_BOOT_PART"
		echo "F2FS_ROOT_PART=$F2FS_ROOT_PART"
	}
}

function discover_drive_partitions() {
	eval $(discover_internal)
	FAT_PARTUUID=$(blkid -s PARTUUID -o value ${FAT_BOOT_PART})
        F2FS_PARTUUID=$(blkid -s PARTUUID -o value ${F2FS_ROOT_PART})
}

function format_partitions() {
	echo "Format partitions ${DISK}"

	echo "Create EXT4 filesystem in ${FAT_BOOT_PART}"
	mkfs.ext4 -F -L FLASHTOO "${FAT_BOOT_PART}"

	echo "Create F2FS filesystem in ${F2FS_ROOT_PART}"
	mkfs.f2fs -f -l FLASHTOO-ROOT \
            -O extra_attr,encrypt,lost_found,inode_checksum,quota,inode_crtime,sb_checksum,compression \
            -a 1 -w 4096 -i "${F2FS_ROOT_PART}"
}

function setup_fstab() {
	if [ ! -e "${F2FS_ROOT}"/etc/fstab ]; then
		echo "bad root"
		return 1
	fi

	# Remove comments
	sed -i '/^# FLASHTOO_REM /d' "${F2FS_ROOT}"/etc/fstab
	sed -i 's/#PARTUUID=__FLASHTOO_F2FS_PARTUUID/PARTUUID='${F2FS_PARTUUID}'/' "${F2FS_ROOT}"/etc/fstab
	sed -i 's/#PARTUUID=__FLASHTOO_FAT_PARTUUID/PARTUUID='${FAT_PARTUUID}'/' "${F2FS_ROOT}"/etc/fstab
}

function chroot_flashdrive() {
	TARBALL="${STAGING_TARBALL_DIR}/${STAGING_BOOT_TARBALL}"

	mkdir "${SYSLINUX_SETUP_DIR}"
	cp "${DIR}"/flash_drive.sh "${SYSLINUX_SETUP_DIR}"
	cp "${TARBALL}" "${SYSLINUX_SETUP_DIR}"
	chroot "${F2FS_ROOT}" /bin/bash /flashtoo-syslinux-setup/flash_drive.sh chrooted_set_syslinux ${FAT_PARTUUID} ${F2FS_PARTUUID} ${DISK}
	rm -rf "${SYSLINUX_SETUP_DIR}"
}

function mount_f2fs_part() {
        mkdir "${F2FS_ROOT}"
        mount -o compress_algorithm=lzo ${F2FS_ROOT_PART} "${F2FS_ROOT}"
}

function umount_f2fs_part() {
	umount "${F2FS_ROOT}"
	rmdir "${F2FS_ROOT}"
}

function mount_f2fs_devprocsys() {
	mount -o bind /dev "${F2FS_ROOT}"/dev
        mount -o bind /proc "${F2FS_ROOT}"/proc
        mount -o bind /sys "${F2FS_ROOT}"/sys
}

function umount_f2fs_devprocsys() {
	umount "${F2FS_ROOT}"/sys
	umount "${F2FS_ROOT}"/proc
	umount "${F2FS_ROOT}"/dev
}

function setup_root_part() {
	F2FS_ROOT_TARBALL="${STAGING_TARBALL_DIR}/${STAGING_ROOT_TARBALL}"

	chattr -R +c "${F2FS_ROOT}"
	pushd "${F2FS_ROOT}"
	tar xf "${F2FS_ROOT_TARBALL}"
	popd
}

function safe_format_disk() {
	DISK_NAME=`lsblk -d -o VENDOR,MODEL,SIZE -n ${DISK}`

	echo "about to partition disk ${DISK}"
	echo ${DISK_NAME}
	echo "this will WIPE ALL DATA on ${DISK} -" ${DISK_NAME}
	echo "IRREVOCABLY"
	echo 'continue?(type exactly: yes please)'

	read confirmation

	if [ "${confirmation}" != "yes please" ]; then
		echo "\"${confirmation}\" is not \"yes please\", aborting"
		exit 1
	fi

	set -e
	set -x

	part_disk

	return 0
}


# PUBLIC:
function prepare_flash_state() {
        if [ "$#" -ne "2" ]; then
                echo "Usage: $0 block_device dir_with_staging_tarballs"
                exit 1
        fi

        # arguments
        DISK=${1}
        STAGING_TARBALL_DIR=$(realpath "${2}")

        # global state
        FAT_PARTUUID="run discover_drive_partitions first"
        F2FS_PARTUUID="run discover_drive_partitions first"
        FAT_BOOT_PART="run discover_drive_partitions first"
        F2FS_ROOT_PART="run discover_drive_partitions first"

        # constants
        F2FS_ROOT="${DIR}"/f2fs_root
        SYSLINUX_SETUP_DIR="${F2FS_ROOT}"/flashtoo-syslinux-setup
        STAGING_ROOT_TARBALL=staging-root-nobdeps.tar
        STAGING_BOOT_TARBALL=staging-boot.tar
}

function do_flash() {
	if [ "$#" -ne "2" ]; then
                echo "Usage: flash block_device dir_with_staging_tarballs"
                exit 1
        fi

	prepare_flash_state $@

	safe_format_disk

	set -e
	set -x

	discover_drive_partitions
	format_partitions
	mount_f2fs_part
	setup_root_part
	setup_fstab
	mount_f2fs_devprocsys
	chroot_flashdrive
	umount_f2fs_devprocsys
	umount_f2fs_part
}

function do_syslinux_chrooted() {
	if [ "$#" -ne "3" ]; then
                echo "Usage: chrooted_set_syslinux FAT_PARTUUID F2FS_PARTUUID DISK"
                exit 1
        fi

	set -x
	set -e

	FAT_BOOT_PARTUUID=${1}
	F2FS_ROOT_PARTUUID=${2}
	FLASH_DRIVE_DEVICE=${3}

	dd bs=440 conv=notrunc count=1 if=/usr/share/syslinux/mbr.bin of=${FLASH_DRIVE_DEVICE}

	mount /boot
	mkdir -p /boot/extlinux || true
	pushd /usr/share/syslinux
	cp memdisk *.c32 /boot/extlinux
	popd
	extlinux --device /dev/disk/by-partuuid/${FAT_BOOT_PARTUUID} --install /boot/extlinux
	pushd /boot
	# Do not use script var, we're in chroot:
	tar xf "${DIR}"/staging-boot.tar
	popd
	sed -i "s/__FLASHTOO_PARTUUID__/${F2FS_ROOT_PARTUUID}/" /boot/extlinux/syslinux.cfg
	sed -i "s/__FLASHTOO_PARTUUID__/${F2FS_ROOT_PARTUUID}/" /etc/kernel/postinst.d/10-flashtoo-syslinux.sh
	umount /boot
}

if [ "$1" == "flash" ]; then
	do_flash "$2" "$3"
elif [ "$1" == "chrooted_set_syslinux" ]; then
	do_syslinux_chrooted $2 $3 $4
else
	echo 'Usage: '${0}' flash <block_device> <dir_with_staging_tarballs>'
fi


