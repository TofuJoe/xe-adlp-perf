#!/bin/bash
# Remove the patched xe module for a kernel and restore that kernel's previous initramfs.
#   sudo ./revert.sh [kernel-version]      (default: the running kernel)
# Reboot afterwards if that kernel is the one running.
set -euo pipefail
K=${1:-$(uname -r)}
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
[ -d "/lib/modules/$K" ] || { echo "no /lib/modules/$K"; exit 1; }
rm -f "/lib/modules/$K/updates/xe.ko"
depmod -a "$K"
if [ -f "/boot/initramfs-$K.img.bak-pre-xe-patched" ]; then
	mv "/boot/initramfs-$K.img.bak-pre-xe-patched" "/boot/initramfs-$K.img"
else
	dracut -f "/boot/initramfs-$K.img" "$K"
fi
echo "modprobe now resolves xe to: $(modinfo -k "$K" -n xe)"
echo "Reverted $K. Reboot if it is the running kernel."
