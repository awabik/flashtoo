#!/bin/bash

PARTUUID=__FLASHTOO_PARTUUID__
SYSCFG=/boot/extlinux/syslinux.cfg

THISVER=$1

echo "DEFAULT flashtoo-${THISVER}" > /boot/extlinux/syslinux.cfg
echo "TIMEOUT 100" >> /boot/extlinux/syslinux.cfg
echo "" >> /boot/extlinux/syslinux.cfg

for i in /boot/vmlinuz-*; do
	VER=$(echo $i | sed 's|/boot/vmlinuz-||')
	IMAGE_NAME=$i

	cat >> /boot/extlinux/syslinux.cfg << EOF
LABEL flashtoo-${VER}
LINUX /vmlinuz-${VER}
APPEND root=PARTUUID=${PARTUUID} rw rootflags=compress_algorithm=zstd init=/lib/systemd/systemd rootwait

EOF

done


