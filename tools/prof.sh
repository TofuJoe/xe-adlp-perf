#!/bin/bash
# ftrace function_profile: DPT pin/unpin totals per page flip.
# Run as root while something repaints: sudo tools/prof.sh SECONDS (e.g. 6)
# usage: prof.sh seconds "cmd to run as user or empty"
T=/sys/kernel/tracing
FUNCS="drm_mode_atomic_ioctl intel_atomic_commit_tail:mod:xe intel_plane_pin_fb:mod:xe intel_plane_unpin_fb:mod:xe xe_fb_pin_reuse_vma:mod:xe __xe_pin_fb_vma:mod:xe __xe_pin_fb_vma_dpt:mod:xe __xe_pin_fb_vma_ggtt:mod:xe __xe_unpin_fb_vma:mod:xe xe_bo_create_pin_map_at_novm:mod:xe xe_bo_unpin_map_no_vm:mod:xe xe_device_l2_flush:mod:xe xe_bo_validate:mod:xe dpt_pool_get:mod:xe dpt_pool_put:mod:xe write_dpt_remapped:mod:xe xe_ggtt_node_remove:mod:xe xe_ggtt_insert_bo_at:mod:xe xe_bo_free:mod:xe ttm_bo_pin ttm_bo_unpin ttm_tt_populate ttm_pool_alloc ttm_pool_free set_pages_array_wc set_pages_array_wc_noflush __xe_bo_create_locked:mod:xe xe_bo_vmap:mod:xe xe_ttm_bo_destroy:mod:xe ttm_bo_put intel_cursor_unpin_work:mod:xe intel_crtc_vblank_work:mod:xe"
echo 0 > $T/function_profile_enabled
echo > $T/set_ftrace_filter; echo 1 > $T/options/sleep-time
for f in $FUNCS; do echo "$f" >> $T/set_ftrace_filter 2>/dev/null; done
echo "filtered: $(wc -l < $T/set_ftrace_filter)"
echo 0 > $T/options/sleep-time; echo 1 > $T/function_profile_enabled
python3 -c "import time; time.sleep($1)"
echo 0 > $T/function_profile_enabled
cat $T/trace_stat/function* | awk '$1!="Function" && $1!~/^-/ && NF>=4 {h[$1]+=$2; t[$1]+=$3} END {for (f in h) printf "%-34s %7d calls %10.1f us total %8.1f us avg\n", f, h[f], t[f], t[f]/h[f]}' | sort -k4 -nr
echo > $T/set_ftrace_filter; echo 1 > $T/options/sleep-time
