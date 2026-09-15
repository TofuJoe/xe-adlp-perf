#!/bin/bash
# Install the module from build/<kernel-version>/xe.ko for that kernel and rebuild its initramfs.
#   sudo ./install.sh [kernel-version]      (default: the running kernel)
# The kernel must be installed. Takes effect on the next boot of that kernel.
# Undo with: sudo ./revert.sh [kernel-version]
set -euo pipefail
R=$(cd "$(dirname "$0")" && pwd)
K=${1:-$(uname -r)}
M=$R/build/$K/xe.ko
[ "$(id -u)" = 0 ] || { echo "run with sudo"; exit 1; }
[ -f "$M" ] || { echo "no module built for $K (expected $M): run ./build.sh $K first"; exit 1; }
[ -d "/lib/modules/$K/kernel" ] || { echo "kernel $K is not installed"; exit 1; }
modinfo "$M" | grep -q "^vermagic: *$K " || { echo "module vermagic does not match kernel $K"; exit 1; }

if mokutil --sb-state 2>/dev/null | grep -q 'SecureBoot enabled'; then
	signer=$(modinfo -F signer "$M" || true)
	[ -n "$signer" ] || { echo "Secure Boot is on but the module is unsigned: rebuild with MOK_KEY/MOK_CERT (see README)"; exit 1; }
	echo "module signed by: $signer (that key must be enrolled with mokutil, or the module won't load)"
fi

install -d "/lib/modules/$K/updates"
install -m 644 "$M" "/lib/modules/$K/updates/xe.ko"
depmod -a "$K"
echo "modprobe now resolves xe to: $(modinfo -k "$K" -n xe)"
[ -f "/boot/initramfs-$K.img.bak-pre-xe-patched" ] || cp -a "/boot/initramfs-$K.img" "/boot/initramfs-$K.img.bak-pre-xe-patched"
dracut -f "/boot/initramfs-$K.img" "$K"
echo "Done. Reboot into $K. Check with: modinfo -n xe; grep -c xe_bo_addr_iter /proc/kallsyms"
