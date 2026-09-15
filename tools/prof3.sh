#!/bin/bash
# ftrace function_profile: CPU time of the whole atomic commit, by stage.
# Run as root while something repaints: sudo tools/prof3.sh SECONDS (e.g. 6)
T=/sys/kernel/tracing
FUNCS="drm_mode_atomic_ioctl drm_atomic_commit intel_atomic_commit:mod:xe intel_atomic_commit_tail:mod:xe intel_atomic_check:mod:xe intel_atomic_prepare_plane_clear_colors:mod:xe intel_prepare_plane_fb:mod:xe intel_plane_pin_fb:mod:xe intel_plane_unpin_fb:mod:xe intel_cleanup_plane_fb:mod:xe intel_psr_pre_plane_update:mod:xe intel_psr_post_plane_update:mod:xe intel_update_crtc:mod:xe intel_crtc_planes_update_arm:mod:xe intel_crtc_planes_update_noarm:mod:xe skl_wm_get_hw_state:mod:xe skl_compute_wm:mod:xe intel_bw_atomic_check:mod:xe intel_cdclk_atomic_check:mod:xe drm_atomic_helper_wait_for_flip_done intel_frontbuffer_flip:mod:xe intel_psr_flush:mod:xe"
echo 0 > $T/function_profile_enabled; echo 0 > $T/options/sleep-time; echo > $T/set_ftrace_filter
for f in $FUNCS; do echo "$f" >> $T/set_ftrace_filter 2>/dev/null; done
echo "filtered: $(wc -l < $T/set_ftrace_filter)"
echo 1 > $T/function_profile_enabled; python3 -c "import time; time.sleep($1)"; echo 0 > $T/function_profile_enabled
cat $T/trace_stat/function* | awk '$1!="Function" && $1!~/^-/ && NF>=4 {h[$1]+=$2; t[$1]+=$3} END {for (f in h) printf "%-38s %6d calls %9.1f us total %7.1f us avg\n", f, h[f], t[f], t[f]/h[f]}' | sort -k4 -nr
echo > $T/set_ftrace_filter; echo 1 > $T/options/sleep-time
