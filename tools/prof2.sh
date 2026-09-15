#!/bin/bash
# ftrace function_profile: BO-create internals on the flip path.
# Run as root while something repaints: sudo tools/prof2.sh SECONDS (e.g. 6)
T=/sys/kernel/tracing
FUNCS="__xe_pin_fb_vma_dpt:mod:xe __xe_unpin_fb_vma:mod:xe xe_bo_create_pin_map_at_novm:mod:xe __xe_bo_create_locked:mod:xe xe_bo_alloc:mod:xe xe_bo_init_locked:mod:xe ttm_bo_init_reserved ttm_bo_init_validate ttm_bo_validate ttm_bo_handle_move_mem xe_bo_move:mod:xe drm_gem_object_init drm_gem_private_object_init shmem_file_setup __shmem_file_setup ttm_resource_alloc xe_ttm_tt_populate:mod:xe xe_tt_map_sg:mod:xe dma_map_sgtable iommu_dma_map_sg iommu_dma_unmap_sg __iommu_unmap iommu_map_sg alloc_pages_bulk_noprof xe_ggtt_insert_bo:mod:xe xe_ggtt_insert_node:mod:xe drm_mm_insert_node_in_range xe_ggtt_map_bo:mod:xe xe_ggtt_map_bo_unlocked:mod:xe xe_ggtt_clear:mod:xe xe_ggtt_remove_bo:mod:xe xe_ggtt_node_remove:mod:xe xe_tlb_inval_ggtt:mod:xe xe_guc_ct_send:mod:xe ttm_bo_vmap vmap vm_map_ram xe_bo_vmap:mod:xe xe_bo_vunmap:mod:xe ttm_bo_vunmap vunmap xe_bo_pin:mod:xe xe_bo_unpin:mod:xe xe_bo_put:mod:xe ttm_bo_release ttm_bo_delayed_delete drm_gem_object_release xe_ttm_bo_destroy:mod:xe ttm_pool_alloc ttm_pool_free ttm_tt_populate synchronize_rcu xe_device_l2_flush:mod:xe xe_bo_addr_iter_first:mod:xe write_dpt_remapped:mod:xe"
echo 0 > $T/function_profile_enabled
echo 0 > $T/options/sleep-time
echo > $T/set_ftrace_filter
for f in $FUNCS; do echo "$f" >> $T/set_ftrace_filter 2>/dev/null; done
echo "filtered: $(wc -l < $T/set_ftrace_filter)"
echo 1 > $T/function_profile_enabled
python3 -c "import time; time.sleep($1)"
echo 0 > $T/function_profile_enabled
cat $T/trace_stat/function* | awk '$1!="Function" && $1!~/^-/ && NF>=4 {h[$1]+=$2; t[$1]+=$3} END {for (f in h) printf "%-30s %6d calls %9.1f us total %7.1f us avg\n", f, h[f], t[f], t[f]/h[f]}' | sort -k4 -nr
echo > $T/set_ftrace_filter
echo 1 > $T/options/sleep-time
