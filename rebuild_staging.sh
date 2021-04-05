#!/bin/bash

set -e
set -x

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

. "${DIR}"/customization.inc

MANDATORY_ADDITIONAL_PACKAGES="\
sys-boot/syslinux \
sys-fs/f2fs-tools \
sys-fs/dosfstools \
sys-kernel/linux-firmware \
"

# gentoo-kernel requires cpio, and does not have it set in its bdeps:
MANDATORY_KERNEL_BDEPS="\
app-arch/cpio \
"

function sync_portage() {
	emerge-webrsync
	emerge --sync
	eselect profile set "${TARGET_PROFILE}"
	emerge -1 portage
}

# The stage1 tree is built from binary packages with --root option
# for emerge. This causes a number of bdeps not installed, like perl.
# Need to build these deps before installing kernel
function build_system_bdeps() {
	emerge --with-bdeps=y --deep --noreplace @world ${MANDATORY_KERNEL_BDEPS}
}

function build_kernel() {
	emerge ${GENTOO_SOURCES_VER}
	eselect kernel set 1
}

function clean_kernel() {
	rm -rf /lib/modules/*
	rm -f /boot/vmlinuz-*
	rm -f /boot/config-*
	rm -f /boot/System.map-*
}

function rebuild_world_for_stage2() {
	emerge --emptytree --exclude ${GENTOO_SOURCES_VER} @world
	emerge @preserved-rebuild
	emerge --depclean
}

function rebuild_world_for_stage3() {
	emerge --emptytree @world ${MANDATORY_ADDITIONAL_PACKAGES} ${ADDITIONAL_PACKAGES}
	emerge @preserved-rebuild
	emerge --depclean

	rm -f /boot/*.old
}

function purge_news_and_stuff() {
	eselect news read
	eselect news purge
}

sync_portage
build_system_bdeps
build_kernel
rebuild_world_for_stage2
clean_kernel

# FIXME: what if the stage2 installed new gcc/binutils? depclean should
# have removed old ones, but can we count on this?
rebuild_world_for_stage3
purge_news_and_stuff

post_install_setup_actions
