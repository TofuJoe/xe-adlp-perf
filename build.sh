#!/bin/bash
# Build the patched xe module out of tree for an installed Fedora kernel.
#   ./build.sh [kernel-version]            (default: the running kernel)
#   MOK_KEY=... MOK_CERT=... ./build.sh    (also sign it; needed with Secure Boot on)
#
# Needs kernel-devel-<kernel-version> (/usr/src/kernels/<kernel-version>), gcc, make, git, curl,
# xz. Downloads linux-<upstream-version>.tar.xz from cdn.kernel.org once (to dl/) and checks
# it against kernel.org's sha256sums.asc (checksum only; the file's PGP signature is not checked).
# Output: build/<kernel-version>/xe.ko and build/<kernel-version>/ttm.ko (the TTM core module,
# which patches 0033 and 0035 change; install.sh installs it alongside xe.ko).
set -euo pipefail
R=$(cd "$(dirname "$0")" && pwd)
K=${1:-$(uname -r)}
UP=${K%%-*}                                  # 7.2.5-200.fc44.x86_64 -> 7.2.5
DEVEL=/usr/src/kernels/$K
P=$R/patches/$UP
W=$R/build/$K

[ -d "$P" ] || { echo "no patch series for upstream $UP (available: $(ls "$R/patches"))"; exit 1; }
[ -f "$DEVEL/Makefile" ] || { echo "kernel-devel for $K is missing: sudo dnf install kernel-devel-$K"; exit 1; }
if [ -n "${MOK_KEY:-}" ] || [ -n "${MOK_CERT:-}" ]; then
	[ -r "${MOK_KEY:-}" ] && [ -r "${MOK_CERT:-}" ] || { echo "MOK_KEY and MOK_CERT must both be readable files"; exit 1; }
fi

mkdir -p "$R/dl"
T=$R/dl/linux-$UP.tar.xz
if [ ! -f "$T" ]; then
	base=https://cdn.kernel.org/pub/linux/kernel/v${UP%%.*}.x
	curl -fL -o "$T.part" "$base/linux-$UP.tar.xz"
	want=$(curl -fsL "$base/sha256sums.asc" | awk -v f="linux-$UP.tar.xz" '$2 == f {print $1}')
	have=$(sha256sum "$T.part" | cut -d' ' -f1)
	[ -n "$want" ] && [ "$want" = "$have" ] || { echo "sha256 mismatch for linux-$UP.tar.xz"; rm -f "$T.part"; exit 1; }
	mv "$T.part" "$T"
fi

# Private copy of kernel-devel with the upstream xe and i915 sources dropped in (xe builds the
# i915 display code from ../i915), then the patch series on top.
rm -rf "$W"
mkdir -p "$W"
cp -a "$DEVEL" "$W/ktree"
chmod -R u+w "$W/ktree"
rm -rf "$W/ktree/drivers/gpu/drm/xe" "$W/ktree/drivers/gpu/drm/i915" "$W/ktree/drivers/gpu/drm/ttm"
tar -C "$W" -xf "$T" "linux-$UP/drivers/gpu/drm/xe" "linux-$UP/drivers/gpu/drm/i915" \
	"linux-$UP/drivers/gpu/drm/ttm"
mv "$W/linux-$UP/drivers/gpu/drm/xe" "$W/linux-$UP/drivers/gpu/drm/i915" \
	"$W/linux-$UP/drivers/gpu/drm/ttm" "$W/ktree/drivers/gpu/drm/"
rm -rf "$W/linux-$UP"
# An empty git repo in the tree, so git apply works relative to it and not to this checkout.
git init -q "$W/ktree"
for p in "$P"/*.patch; do
	git -C "$W/ktree" apply "$p" || { echo "patch failed: $(basename "$p")"; exit 1; }
done

make -C "$W/ktree" -j"$(nproc)" M=drivers/gpu/drm/ttm modules
make -C "$W/ktree" -j"$(nproc)" M=drivers/gpu/drm/xe modules
cp "$W/ktree/drivers/gpu/drm/xe/xe.ko" "$W/xe.ko"
cp "$W/ktree/drivers/gpu/drm/ttm/ttm.ko" "$W/ttm.ko"
strip --strip-debug "$W/xe.ko" "$W/ttm.ko"

if [ -n "${MOK_KEY:-}" ]; then
	"$DEVEL/scripts/sign-file" sha256 "$MOK_KEY" "$MOK_CERT" "$W/xe.ko"
	"$DEVEL/scripts/sign-file" sha256 "$MOK_KEY" "$MOK_CERT" "$W/ttm.ko"
	echo "signed with $MOK_CERT"
fi

n=$(nm "$W/xe.ko" 2>/dev/null | grep -c ' T xe_bo_addr_iter') || true
[ "$n" = 2 ] || { echo "unexpected: patched symbols missing from xe.ko"; exit 1; }
modinfo "$W/ttm.ko" | grep -q '^parm: *pool_cached' || { echo "unexpected: patched parameters missing from ttm.ko"; exit 1; }
echo "built $W/xe.ko and $W/ttm.ko (kernel $K). Install with: sudo ./install.sh $K"
