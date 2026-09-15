#!/bin/bash
# ftrace function_profile: GPU submission (exec ioctl) path.
# Run as root while something repaints: sudo tools/prof-exec.sh SECONDS (e.g. 6)
# prof-exec.sh seconds: CPU-only profile of the xe submission path
T=/sys/kernel/tracing
FUNCS="xe_exec_ioctl xe_vm_bind_ioctl xe_wait_user_fence_ioctl xe_gem_create_ioctl xe_gem_mmap_offset_ioctl xe_exec_queue_create_ioctl xe_validation_exec_lock drm_gpuvm_prepare_objects drm_gpuvm_exec_lock drm_exec_lock_obj xe_vm_validate_rebind xe_vm_rebind xe_sched_job_create xe_sched_job_add_deps xe_sync_entry_parse xe_sync_entry_signal drm_gpuvm_resv_add_fence guc_exec_queue_run_job drm_sched_run_job_work drm_sched_free_job_work xelp_irq_handler hw_fence_irq_run_cb xe_hw_fence_irq_run drm_sched_job_done_cb xe_guc_ct_send xe_bo_validate xe_pt_update_ops_run xe_vm_ops_execute xe_tlb_inval_range xe_drm_ioctl drm_syncobj_find_fence drm_syncobj_replace_fence xe_hw_engine_handle_irq xe_guc_irq_handler g2h_worker_func receive_g2h"
echo 0 > $T/function_profile_enabled; echo 0 > $T/options/sleep-time; echo > $T/set_ftrace_filter
for f in $FUNCS; do echo "$f" >> $T/set_ftrace_filter 2>/dev/null; done
echo "filtered: $(wc -l < $T/set_ftrace_filter)"
echo 1 > $T/function_profile_enabled; python3 -c "import time; time.sleep($1)"; echo 0 > $T/function_profile_enabled
cat $T/trace_stat/function* | awk '$1!="Function" && $1!~/^-/ && NF>=4 {h[$1]+=$2; t[$1]+=$3} END {for (f in h) printf "%-34s %7d calls %9.1f us total %7.1f us avg\n", f, h[f], t[f], t[f]/h[f]}' | sort -k4 -nr
echo > $T/set_ftrace_filter; echo 1 > $T/options/sleep-time
