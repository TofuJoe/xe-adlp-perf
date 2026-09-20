> ### Unofficial patches — not an Intel or kernel.org project
>
> A personal patch series for Intel's `xe` GPU driver, built out of tree for Fedora kernels.
> It is **not affiliated with, endorsed by, or supported by Intel or the Linux kernel community.**
> Tested on one laptop. Don't report problems seen with this module to Intel or upstream;
> reproduce them on a stock kernel first.
>
> The kernel is GPL-2.0; these patches and scripts are GPL-2.0 too (see [LICENSE](LICENSE)).

# xe-adlp-perf

Performance patches for the `xe` driver on **Alder Lake-P** integrated graphics, for Fedora 44
kernel **7.2.5**. They started as a fix for one bad bug: on a 5K external monitor, every page flip
took 20–70 ms in the kernel, so the mouse cursor lagged whenever anything animated on screen (a
Google Maps tab was enough). With that fixed, the rest of the flip, render and memory-pressure
paths were profiled and trimmed.

## Impact

Test machine: Lenovo ThinkPad X1, Alder Lake-P iGPU (8086:46a6) running on `xe`, 16 GB RAM with
zram swap, Fedora 44, GNOME 50 (Mutter 50.4). Displays: internal 1920x1200 eDP panel and a
Lenovo P40w-20 at 5120x2160@60 over a USB4/Thunderbolt dock.

Method: `strace -T` on gnome-shell's KMS thread for commit latency, and ftrace
`function_profile` (the scripts in [tools/](tools/)) for kernel CPU time. Times in µs are CPU
time per call.

### 5K page flips (Chrome with a Google Maps tab animating)

| | Stock 7.2.5 | Patched (0001–0015) |
|---|---|---|
| Atomic commit (`DRM_IOCTL_MODE_ATOMIC`), average | **20 ms** | **0.17 ms** |
| Atomic commit, worst | 70 ms | 0.54 ms |
| Commits longer than one frame (16.7 ms) | 20 of 60 | 0 of 240 |
| gnome-shell KMS thread CPU | 40–48% of a core | ~1% |

Most of the win is patch 0001, which removes the O(N²) page table fill (on the internal panel,
0001 alone gave 0.33 ms average commits). At 5K, the 0001–0011 build averaged 0.28 ms (0.67 ms
worst); 0012–0015 then removed most of the remaining per-flip CPU:

| Kernel CPU per commit at 5K | After 0001–0011 | After 0001–0015 |
|---|---|---|
| Whole atomic ioctl | 255 µs | 139 µs |
| Commit tail (hardware programming) | 195 µs | 102 µs |
| Display page table pin | 113 µs | 3.7 µs |
| DSB command buffer create / free | 71 / 38 µs | 3.5 / 2.1 µs |
| Plane clear-color read | 30 µs | 2.7 µs |

On the internal panel, the display page table pool (0005) cut pin cost from 125 to 42 µs and unpin
from 53 to 7 µs; per-flip BO creation went from 1 per flip to 4 in 237 flips.

### Rendering at 60 fps (0016–0020 vs 0001–0015)

| | Before | After |
|---|---|---|
| irq_work self-IPIs while rendering | 540/s | 11/s |
| Framebuffer creation per frame (Mutter does ADDFB2 every frame) | 46–73 µs | 25 µs |
| `intel_fill_fb_info` | 23–46 µs | 7 µs |
| Plane format/modifier checks per framebuffer | 42 | 1 (cached) |

### Under memory pressure (0021–0022 vs 0001–0020)

About 1.2 GB of RAM available, 4+ GB in zram, 6+ GB of GPU memory in use (Chrome). Before, the
driver's shrinker kept swapping out buffers of apps that were rendering every frame, and each
app's next GPU submission swapped them straight back in.

| | Before | After |
|---|---|---|
| GPU buffers swapped out | 254/s | 5.5/s |
| GPU buffers swapped back in | 270/s | 27/s |
| GPU submission (exec ioctl), average | 462 µs | 212 µs (36 µs without pressure) |

These two samples were taken at different times, not as a controlled A/B test. The remaining
swap-outs happen inside apps that are themselves stalled waiting for memory (by design, see 0022).

### GPU submission and per-frame bookkeeping (0023–0032 vs 0001–0022)

Measured on the internal panel with `glxgears` at 60 fps on top of the normal desktop, ftrace
function profile over 10 s (2026-09-15):

| | Before | After |
|---|---|---|
| GPU submission (exec ioctl), average | 45 µs | 35 µs |
| Locking the VM and its external buffers per exec | 11.3 µs | 5.5 µs |
| Scheduler dependencies added per job | ~9 | 4.6 |
| PSR frontbuffer flush per display commit | 12.9 µs | 4.9 µs |
| `intel_encoder_can_psr` calls per commit | 28 | 7 |

0027 (lazy shmem backup) and 0028 (fault prefault) only act under memory pressure and were not
measured yet; 0023–0026 are upstream fixes.

### Buffer creation and page clearing (0033–0035 vs 0001–0032)

0033 pools write-back cached pages instead of returning them to the page allocator, and clears them
on the way into the pool rather than on the way out, so buffer creation no longer pays for zeroing:

| | Before | After |
|---|---|---|
| `gem create` for a 6 MiB buffer | 1040 µs | 48 µs |

That moves the cost to the free path, where 0035 makes it cheaper: a block of contiguous pages is
cleared in one pass instead of 4 KiB at a time. Measured with `tools/zeroing/bo-churn.c` (create and
close 400 buffers of a known size, pinned to a P-core), toggling `ttm.pool_clear_contig` between runs:

| Buffer size | Per-page clear | One pass | Package energy |
|---|---|---|---|
| 2 MiB | 99.1 µs/MiB | 70.7 µs/MiB | 2.5 J → 2.0 J |
| 8 MiB | 86.9 µs/MiB | 68.5 µs/MiB | 6.9 J → 5.7 J |

Three alternating rounds at 8 MiB gave 746.8 / 684.3 / 679.5 µs per buffer per-page against
554.0 / 553.0 / 547.1 µs contiguous, with no overlap between the groups.

A microbenchmark (`tools/zeroing/zero.c`) says clearing 4 KiB at a time runs at 14.2 GB/s against
48.4 GB/s over a whole range on this machine, but in the kernel the real gap is much smaller —
about 15 GB/s against 11–12 GB/s — so take the microbenchmark as an upper bound, not a prediction.
There is no fill engine to offload to on this part: no DSA, and `CLZERO` is AMD-only.

0034 (page table cache) was measured at 11 reuses out of 215 page-table creations over 90 s of
desktop use: correct, but little impact next to the pool.

### A tip that is not a patch: the GPU frequency floor

On this machine the firmware's "efficient" frequency is reported as 300 MHz, and with a desktop
that keeps the GPU about 10% busy it simply stays there. Raising the floor halved the time each
render job spends on the GPU (median 1.65 ms → 0.84 ms at 700 MHz) and *raised* RC6 idle residency
from 76% to 87%, because jobs finish sooner:
```
echo 700 | sudo tee /sys/class/drm/card0/device/tile0/gt0/freq0/min_freq
```
Battery cost was not measurable with RAPL on a busy desktop. Undo with `echo 300`.

### Not individually measured

Patches 0002–0004 and 0023–0026 (upstream fixes), 0006 (flip boost), 0007 (exec job allocation),
0008 (LRU refresh for long-running VMs), 0009 (user fence wake-ups), 0010 (TLB invalidation
coalescing), 0027 (lazy shmem backup) and 0028 (fault prefault) were not benchmarked on their own.

## Patches (`patches/7.2.5/`)

| # | What | Origin |
|---|---|---|
| 0001 | O(N) instead of O(N²) display page table fill for remapped framebuffers | Based on Maarten Lankhorst's unmerged series; range sizing reworked |
| 0002 | GuC: fix wake_up race in `handle_sched_done` | Jakub Legowski, intel-xe list (v3) |
| 0003 | Enable HPD polling later during system resume | Imre Deak, upstream 7.3-rc |
| 0004 | GuC: fix `suspend_pending` locking race | Jagmeet Randhawa, intel-xe list (v2), hand-ported |
| 0005 | Pool display page table BOs instead of creating one per flip | |
| 0006 | Briefly raise GPU min frequency when a flip misses vblank (`xe.flip_boost`) | |
| 0007 | Allocate the exec job before taking VM and reservation locks | |
| 0008 | Refresh LRU position of long-running VMs on exec | |
| 0009 | Skip the user fence wake-up when nobody is waiting | |
| 0010 | Coalesce full PPGTT TLB invalidations (`xe.tlb_inval_coalesce`) | |
| 0011 | Hardening of 0006 and 0010 after review | |
| 0012 | Track a backing generation per BO | |
| 0013 | Read the framebuffer clear color without vmap | |
| 0014 | Pool DSB buffers; skip unchanged display page table rewrites | |
| 0015 | Size the pools for two active outputs | |
| 0016 | Signal hardware fences from the interrupt handler instead of irq_work | |
| 0017 | Move shared (dma-buf) BOs to the LRU tail on exec | |
| 0018 | Shrinker: skip busy BOs, keep pages freed before an error | |
| 0019 | Cache per-format plane capability scans for framebuffer creation | |
| 0020 | Shrinker: only skip BOs that were not attempted | |
| 0021 | Shrinker: leave BOs of actively rendering VMs alone (`xe.shrink_active_ms`) | |
| 0022 | Shrinker: apply that only in kswapd and only to idle BOs, so no BO becomes unreclaimable | |
| 0023 | pcode mailbox timeout 1 → 10 ms (spurious `-ETIMEDOUT` under load) | Karthik Poosa, drm-xe-next, hand-ported |
| 0024 | Revert "Clear SEL_FETCH_PLANE_CTL on plane disable" (writes to pipes without selective fetch) | Nemesa Garg, drm-intel-next, Cc stable |
| 0025 | PSR: clear stale selective-fetch enable bits when selective fetch is turned off | Nemesa Garg, drm-intel-next |
| 0026 | Engine-domain forcewake for engine cycle queries instead of waking all domains | Xin Wang, upstream 7.3-rc1 |
| 0027 | Create the shmem backup file lazily in the shrinker, not for every BO at creation | |
| 0028 | CPU fault prefault size tunable, default 512 pages (`xe.prefault_pages`) | |
| 0029 | Skip already-signaled fences when adding dma-resv dependencies to a job | |
| 0030 | Size the exec `drm_exec` object array from the previous lock instead of 4 KiB per exec | |
| 0031 | PSR: frontbuffer flush/invalidate only visit encoders whose PSR is enabled | |
| 0032 | ADDFB2: don't reserve the BO when the write-combine flag is already set | |
| 0033 | Pool write-back cached pages of order > 0, cleared on the way in (`ttm.pool_cached`) — **builds a second module, `ttm.ko`** | |
| 0034 | Cache detached level-0 page tables per VM | |
| 0035 | Clear a pooled block in one pass instead of page by page (`ttm.pool_clear_contig`) | |

0033 and 0035 change the TTM core (`drivers/gpu/drm/ttm/`), not `xe`, so the build produces a
second module, `ttm.ko`, which `install.sh` installs alongside `xe.ko`. TTM is shared with other
DRM drivers, so on a machine with another TTM-based GPU those patches affect it too.

Patches without an origin were written for this series with AI assistance (Claude; marked
`Assisted-by:` in each commit). Patches 0005–0022 and 0027–0032 were checked by independent review
passes before being booted, but none of it has been reviewed by kernel maintainers or run through
Intel's IGT suite. 0006, 0010, 0016, 0018–0022 and 0027 touch GPU frequency control, TLB
invalidation, interrupt handling and memory reclaim, where a bug can mean hangs or corruption
rather than a slow frame.

## Requirements

- Fedora 44 with kernel `7.2.5-*.fc44.x86_64` and the matching `kernel-devel`. The series is for
  7.2.5 source only; other kernels need it rebased.
- An Alder Lake-P iGPU running on `xe`. On ADL-P the kernel still defaults to `i915`, so boot with
  (replace `46a6` with your device ID from `lspci -nn | grep VGA`):
  ```
  sudo grubby --update-kernel=ALL --args='i915.force_probe=!46a6 xe.force_probe=46a6'
  ```
  `force_probe` taints the kernel; that is expected.
- With Secure Boot on, a Machine Owner Key (MOK) to sign the module.

0001 should matter on other Alder Lake-P machines with high-resolution outputs, where large
framebuffers use the remapped view. Nothing was tested on other machines or xe platforms.

## Build and install

One-time, if Secure Boot is on (keep `MOK.priv` private and outside this repo):
```
mkdir -p ~/mok && chmod 700 ~/mok
openssl req -new -x509 -newkey rsa:2048 -nodes -days 36500 -outform DER \
  -subj "/CN=local kernel module signing/" -keyout ~/mok/MOK.priv -out ~/mok/MOK.der
sudo mokutil --import ~/mok/MOK.der      # set a one-time password
# reboot, choose "Enroll MOK" in the blue MokManager screen, enter the password
```

Build, sign and install for a kernel:
```
MOK_KEY=~/mok/MOK.priv MOK_CERT=~/mok/MOK.der ./build.sh 7.2.5-200.fc44.x86_64
sudo ./install.sh 7.2.5-200.fc44.x86_64
reboot
```
`build.sh` copies `kernel-devel` into `build/`, drops in the 7.2.5 `xe`, `i915` and `ttm` sources
(downloaded from cdn.kernel.org and checksum-verified), applies the patches and builds `xe.ko` and
`ttm.ko`. `install.sh` puts both in `/lib/modules/<kernel>/updates/`, keeps a backup of the
initramfs and rebuilds it.

Check after boot:
```
modinfo -n xe                                  # .../updates/xe.ko
modinfo -n ttm                                 # .../updates/ttm.ko
grep -c xe_bo_addr_iter /proc/kallsyms         # non-zero
cat /sys/module/ttm/parameters/pool_cached     # Y
sudo journalctl -k -b | grep -iE 'xe .*(warn|error|timeout)'
```

**Kernel updates:** the module is built for one kernel version. After a kernel update the stock
`xe` comes back until you rebuild for the new kernel (rebasing the patches if the version
changed). `extras/xe-driver-check.sh` with its user service shows a GNOME notification at login
when that happens.

## Turning things off

Undo completely: `sudo ./revert.sh <kernel-version>` and reboot.

Six changes can be switched off at runtime (as root):
```
echo 0 > /sys/module/xe/parameters/flip_boost          # 0006
echo 0 > /sys/module/xe/parameters/tlb_inval_coalesce  # 0010
echo 0 > /sys/module/xe/parameters/shrink_active_ms    # 0021/0022
echo 0 > /sys/module/xe/parameters/prefault_pages      # 0028: back to TTM's 16 pages per fault
echo N > /sys/module/ttm/parameters/pool_cached        # 0033: stop pooling cached pages
echo N > /sys/module/ttm/parameters/pool_clear_contig  # 0035: back to clearing page by page
```
or permanently with `xe.flip_boost=0`, `ttm.pool_cached=0` and so on on the kernel command line.
The pool's size cap is `ttm.page_pool_size` (pages per NUMA node).

## Measuring

The `tools/` scripts use ftrace and must run as root. Run them while something repaints (a Maps
tab, `glxgears`):
```
sudo tools/prof3.sh 6            # CPU time of the atomic commit, by stage
sudo tools/prof-fb.sh 6          # framebuffer create/close per frame
sudo tools/prof-pressure.sh 15   # GPU buffer swap-out/in by process, under memory pressure
sudo tools/prof-zero.sh 30       # buffer alloc/free cost, i.e. what 0033 and 0035 change
```
For the page-clearing patches specifically, `tools/zeroing/` has a deterministic buffer-churn
benchmark and the bandwidth and RAPL-energy microbenchmarks used to size them:
```
cd tools/zeroing && gcc -O2 -o bo-churn bo-churn.c && ./bo-churn 400 8
echo N | sudo tee /sys/module/ttm/parameters/pool_clear_contig   # A/B the clearing method
```
Commit latency as the compositor sees it:
```
top -H -p $(pgrep -x gnome-shell)                       # note the "KMS thread" TID
sudo strace -T -e ioctl -p <TID> 2>&1 | grep MODE_ATOMIC
```
