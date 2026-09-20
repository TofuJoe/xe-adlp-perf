#!/bin/bash
# Page-clearing cost in the TTM pool (patches 0033 and 0035): profile the BO alloc/free paths
# while a workload churns buffers. Run as root.
#   sudo ./tools/prof-zero.sh [seconds] ["command to run as the desktop user"]
# With no command, profiles whatever is already running for the given time. A cold browser start
# is a good churn workload; tools/zeroing/bo-churn.c is a deterministic one.
T=/sys/kernel/tracing
S=${1:-30}
CMD=${2:-}
FUNCS="ttm_pool_alloc ttm_pool_free ttm_tt_populate ttm_bo_populate \
xe_gem_create_ioctl:mod:xe __xe_bo_create_locked:mod:xe xe_ttm_bo_destroy:mod:xe xe_bo_free:mod:xe"

echo 0 > $T/function_profile_enabled
echo > $T/set_ftrace_filter; echo 1 > $T/options/sleep-time
for f in $FUNCS; do echo "$f" >> $T/set_ftrace_filter 2>/dev/null; done
echo "filtered: $(wc -l < $T/set_ftrace_filter)"

echo 0 > $T/options/sleep-time; echo 1 > $T/function_profile_enabled
if [ -n "$CMD" ]; then
	U=${SUDO_USER:-$(logname 2>/dev/null)}
	runuser -u "$U" -- env XDG_RUNTIME_DIR="/run/user/$(id -u "$U")" \
		WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}" DISPLAY="${DISPLAY:-:0}" \
		setsid bash -c "$CMD" >/dev/null 2>&1 &
fi
sleep "$S"
echo 0 > $T/function_profile_enabled

cat $T/trace_stat/function* | awk '$1!="Function" && $1!~/^-/ && NF>=4 {h[$1]+=$2; t[$1]+=$3} END {for (f in h) printf "%-26s %7d calls %11.1f us total %8.2f us avg\n", f, h[f], t[f], t[f]/h[f]}' | sort -k4 -nr
echo > $T/set_ftrace_filter; echo 1 > $T/options/sleep-time
