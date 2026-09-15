#!/bin/bash
# Login check: warn when the running kernel is not using the patched xe module, e.g. after a
# kernel update (the module is per kernel version; a new kernel silently brings stock xe back).
# Silent when everything is fine. Install as a user service: see xe-driver-check.service.
K=$(uname -r)

if ! grep -q '^xe ' /proc/modules; then
	notify-send -u critical -a "xe driver check" "xe driver not loaded" \
		"Kernel $K booted without the xe module. Check: journalctl -k -b | grep -iE 'xe|simpledrm'"
	exit 0
fi

# The patched module has the DPT iterator (patch 0001); stock xe does not.
grep -q ' xe_bo_addr_iter_first' /proc/kallsyms && exit 0

notify-send -u critical -a "xe driver check" "Stock xe driver running" \
	"Kernel $K is running the stock xe module. Build and install the patched one for this kernel: ./build.sh $K && sudo ./install.sh $K"
exit 0
