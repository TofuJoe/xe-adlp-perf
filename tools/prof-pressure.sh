#!/bin/bash
# GPU memory ping-pong under memory pressure: shrinker backups vs exec restores, split by task.
#   sudo tools/prof-pressure.sh [seconds]
set -u
D=${1:-15}; T=/sys/kernel/tracing; OUT=$(mktemp -d)
FUNCS="xe_bo_shrink ttm_bo_shrink ttm_tt_backup ttm_tt_restore xe_shrinker_scan xe_exec_ioctl xe_vm_validate_rebind set_pages_array_wc set_pages_array_wb xe_bo_cpu_fault"
vm() { grep -E '^(pgscan_kswapd|pgscan_direct|pgsteal_kswapd|pgsteal_direct|allocstall_normal|compact_stall|pswpin|pswpout|workingset_refault_anon) ' /proc/vmstat; }
cleanup() {
  echo 0 > $T/function_profile_enabled; echo > $T/set_ftrace_filter
  [ -e $T/events/kprobes/enable ] && echo 0 > $T/events/kprobes/enable; echo 0 > $T/tracing_on
  echo > $T/kprobe_events 2>/dev/null; echo > $T/trace; echo 1 > $T/tracing_on
}
trap cleanup EXIT
cleanup
echo "== before"; grep -E 'MemAvailable|SwapFree|GPUActive' /proc/meminfo; cat /proc/pressure/memory
vm > $OUT/vm0
echo "$FUNCS" | tr ' ' '\n' > $T/set_ftrace_filter
echo 'r:xeshr xe_bo_shrink ret=$retval' >> $T/kprobe_events
echo 'p:ttmshr ttm_bo_shrink' >> $T/kprobe_events
echo 'p:ttrest ttm_tt_restore' >> $T/kprobe_events
echo 16384 > $T/buffer_size_kb
echo > $T/trace
echo 1 > $T/events/kprobes/enable
echo 1 > $T/function_profile_enabled
sleep "$D"
echo 0 > $T/function_profile_enabled
echo 0 > $T/events/kprobes/enable
vm > $OUT/vm1
cat $T/trace > $OUT/trace
echo "== function profile ($D s, CPU time)"
cat $T/trace_stat/function* | awk '$1!~/Function|---/ && NF>=4 {c[$1]+=$2; t[$1]+=$3*($4=="us"?1:($4=="ms"?1000:0.001))} END {for (f in c) printf "%-24s %8d calls %9.1f us avg %8.1f ms total\n", f, c[f], t[f]/c[f], t[f]/1000}' | sort -k2 -nr
echo "== vmstat deltas"
join $OUT/vm0 $OUT/vm1 | awk '{printf "%-26s %d\n", $1, $3-$2}'
echo "== xe_bo_shrink results by task (ret: -11 = skipped active, -16 = busy, >0 = pages freed)"
gawk '/xeshr:/ {comm=$1; sub(/-[0-9]+$/,"",comm); match($0,/ret=[^ ]+/); v=strtonum(substr($0,RSTART+4,RLENGTH-4)); if (v>=2^63) v-=2^64; k=(v>0?"freed":v); n[comm" "k]++} END {for (x in n) print n[x], x}' $OUT/trace | sort -nr | head -15
echo "== ttm_bo_shrink (actual shrink attempts) by task"
awk '/ttmshr:/ {comm=$1; sub(/-[0-9]+$/,"",comm); n[comm]++} END {for (x in n) print n[x], x}' $OUT/trace | sort -nr | head
echo "== ttm_tt_restore (swap-ins) by task"
awk '/ttrest:/ {comm=$1; sub(/-[0-9]+$/,"",comm); n[comm]++} END {for (x in n) print n[x], x}' $OUT/trace | sort -nr | head
echo "lost events: $(grep -c LOST $OUT/trace)"
echo "== after"; grep -E 'MemAvailable|SwapFree|GPUActive' /proc/meminfo; cat /proc/pressure/memory
rm -rf $OUT
