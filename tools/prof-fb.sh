#!/bin/bash
# ftrace function_profile: ADDFB2/CLOSEFB cost per frame.
# Run as root while something repaints: sudo tools/prof-fb.sh SECONDS (e.g. 6)
# prof-fb.sh seconds: CPU-only profile of framebuffer create/close (xe display)
T=/sys/kernel/tracing
FUNCS="drm_mode_addfb2_ioctl drm_mode_closefb_ioctl drm_mode_addfb2 drm_framebuffer_init drm_framebuffer_cleanup drm_gem_object_lookup drm_get_format_info intel_user_framebuffer_create:mod:xe intel_framebuffer_create:mod:xe intel_framebuffer_init:mod:xe intel_fill_fb_info:mod:xe intel_bo_read_from_page:mod:xe intel_user_framebuffer_destroy:mod:xe calc_plane_remap_info:mod:xe intel_plane_fb_max_stride:mod:xe intel_fb_plane_get_modifiers:mod:xe intel_fb_plane_supports_modifier:mod:xe tgl_plane_format_mod_supported:mod:xe intel_plane_can_async_flip:mod:xe xe_display_bo_framebuffer_init:mod:xe xe_display_bo_framebuffer_fini:mod:xe xe_frontbuffer_get:mod:xe intel_fb_needs_pot_stride_remap:mod:xe"
echo 0 > $T/function_profile_enabled; echo 0 > $T/options/sleep-time; echo > $T/set_ftrace_filter
for f in $FUNCS; do echo "$f" >> $T/set_ftrace_filter 2>/dev/null; done
echo "filtered: $(wc -l < $T/set_ftrace_filter)"
echo 1 > $T/function_profile_enabled; python3 -c "import time; time.sleep($1)"; echo 0 > $T/function_profile_enabled
cat $T/trace_stat/function* | awk '$1!="Function" && $1!~/^-/ && NF>=4 {h[$1]+=$2; t[$1]+=$3} END {for (f in h) printf "%-38s %6d calls %9.1f us total %7.1f us avg\n", f, h[f], t[f], t[f]/h[f]}' | sort -k4 -nr
echo > $T/set_ftrace_filter; echo 1 > $T/options/sleep-time
