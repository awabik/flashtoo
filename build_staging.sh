#!/bin/bash

set -x
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

. "${DIR}"/customization.inc

SCRIPT_ROOT="${DIR}"
SKELETON="${DIR}"/skeleton

WORK_DIR="${DIR}"/out
STAGING_ROOT="${WORK_DIR}"/staging
STAGING_BOOT="${WORK_DIR}"/staging-boot
STAGING_FLASHTOO_BIN="${WORK_DIR}"/staging-flashtoo
STAGING_KERNEL_SRC="${WORK_DIR}"/staging-kernelsrc
UNTOUCHED_TAG="#flashtoo.no-one.touched.me.yeah.im.generated.kill.me.kill.me.before.it.spreads.killlllll......"

function mount_staging_devprocsys() {
	mount -o bind /dev "${STAGING_ROOT}"/dev
        mount -o bind /proc "${STAGING_ROOT}"/proc
        mount -o bind /sys "${STAGING_ROOT}"/sys
}

function umount_staging_devprocsys() {
	umount "${STAGING_ROOT}"/sys
        umount "${STAGING_ROOT}"/proc
        umount "${STAGING_ROOT}"/dev
}

function setup_staging() {
	mkdir -p "${STAGING_ROOT}"/proc
	mkdir -p "${STAGING_ROOT}"/sys
	mkdir -p "${STAGING_ROOT}"/dev
	mkdir -p "${STAGING_ROOT}"/flashtoo/portage/tmp

	cp -av "${SKELETON}"/* "${STAGING_ROOT}"
	chown -hR root:root "${STAGING_ROOT}"
	cp "${SCRIPT_ROOT}"/rebuild_staging.sh "${STAGING_ROOT}"/flashtoo
	cp "${SCRIPT_ROOT}"/customization.inc "${STAGING_ROOT}"/flashtoo
	echo ${UNTOUCHED_TAG} > "${STAGING_ROOT}"/etc/resolv.conf
	cat /etc/resolv.conf >> "${STAGING_ROOT}"/etc/resolv.conf
}

function build_staging() {
	mkdir -p /flashtoo/portage/tmp
	emerge --usepkg --root="${STAGING_ROOT}" @system
}

function chroot_rebuild_staging() {
	chroot "${STAGING_ROOT}" /bin/bash /flashtoo/rebuild_staging.sh
}

function cleanup_staging() {
	resolv_conf_untouched=0
	grep ${UNTOUCHED_TAG} ${STAGING_ROOT}/etc/resolv.conf > /dev/null  2>&1 || resolv_conf_untouched=$?
	if [ "${resolv_conf_untouched}" -eq 0 ]; then
		rm "${STAGING_ROOT}"/etc/resolv.conf
	fi
}

function tar_staging_dir() {
	TOTAR=$1
	SUFFIX=$2
	pushd "${TOTAR}"
	tar cf "${WORK_DIR}"/staging-${SUFFIX}.tar ./
	popd
}

function tar_unpack() {
	TOTAR=$1
        SUFFIX=$2
        pushd "${TOTAR}"
        tar xf "${WORK_DIR}"/staging-${SUFFIX}.tar
        popd
}

function rel_cleanup_staging() {
	mv "${STAGING_ROOT}"/usr/src "${STAGING_KERNEL_SRC}"
	mv "${STAGING_ROOT}"/flashtoo "${STAGING_FLASHTOO_BIN}"
	mv "${STAGING_ROOT}"/usr/portage "${STAGING_FLASHTOO_BIN}"/usr-portage

	mkdir -p "${STAGING_BOOT}"
        mv "${STAGING_ROOT}"/boot/* "${STAGING_BOOT}"
}

function rel_consolidate_staging() {
	mv "${STAGING_FLASHTOO_BIN}"/usr-portage "${STAGING_ROOT}"/usr/portage
        mv "${STAGING_FLASHTOO_BIN}" "${STAGING_ROOT}"/flashtoo
        mv "${STAGING_BOOT}"/* "${STAGING_ROOT}"/boot
        rmdir "${STAGING_BOOT}"
        mv "${STAGING_KERNEL_SRC}" "${STAGING_ROOT}"/usr/src
}

function rel_cleanup_staging_bdeps() {
	chroot "${STAGING_ROOT}" /bin/bash -c "emerge --depclean --with-bdeps=n"
}

function pack_staging_bin_artifacts() {
	rel_cleanup_staging

	tar_staging_dir "${STAGING_BOOT}" boot
	tar_staging_dir "${STAGING_ROOT}" root
	tar_staging_dir "${STAGING_FLASHTOO_BIN}" flashtoo-bin
	tar_staging_dir "${STAGING_KERNEL_SRC}" kernel

	rel_consolidate_staging
	mount_staging_devprocsys
	rel_cleanup_staging_bdeps
	umount_staging_devprocsys
	rel_cleanup_staging

	tar_staging_dir "${STAGING_ROOT}" root-nobdeps

	rm -rf "${STAGING_BOOT}"
	rm -rf "${STAGING_ROOT}"
	rm -rf "${STAGING_FLASHTOO_BIN}"
	rm -rf "${STAGING_KERNEL_SRC}"
}

function reset_root_password() {
	chroot "${STAGING_ROOT}" /bin/bash -c "passwd -d root"
        rm -f "${STAGING_ROOT}"/root/.bash_history
}

function do_build() {
	if [ -e "${WORK_DIR}" ]; then
		echo "Work dir in ${WORK_DIR} exists. If you want to build new release, remove it"
		exit 1
	fi

	build_staging
	setup_staging
	mount_staging_devprocsys
	chroot_rebuild_staging
	umount_staging_devprocsys
	cleanup_staging
	reset_root_password
}

function do_package() {
	if [ ! -e "${STAGING_ROOT}" ]; then
		echo "Staging dir in ${STAGING_DIR} does not exit."
		exit 1
	fi

	pack_staging_bin_artifacts
}

function do_unpack() {
	if [ -e "${STAGING_ROOT}" ]; then
                echo "Staging dir in ${STAGING_DIR} exists. Will not unpack"
                exit 1
        fi

	mkdir -p "${STAGING_KERNEL_SRC}"
	mkdir -p "${STAGING_ROOT}"
	mkdir -p "${STAGING_BOOT}"
	mkdir -p "${STAGING_FLASHTOO_BIN}"

	tar_unpack "${STAGING_KERNEL_SRC}" kernel
	tar_unpack "${STAGING_ROOT}" root
	tar_unpack "${STAGING_BOOT}" boot
	tar_unpack "${STAGING_FLASHTOO_BIN}" flashtoo-bin

	rel_consolidate_staging
}

if [ "$1" == "build" ]; then
	do_build
elif [ "$1" == "package" ]; then
	do_package
elif [ "$1" == "unpack" ]; then
        do_unpack
else
	echo 'Usage: '${0}' <build|package|unpack>'
fi
