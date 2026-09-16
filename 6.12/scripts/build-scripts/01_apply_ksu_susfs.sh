#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

KSUN_FOLDER="${COMMON_KERNEL_FOLDER}/KernelSU-Next"
SUSFS_FOLDER="${WORKSPACE_ROOT}/susfs4ksu"

echo "=========================================="
echo " Starting KernelSU-Next + SUSFS Installer "
echo "=========================================="

cd "${WORKSPACE_ROOT}"

# 1. Fetch dependencies
echo "[1/4] Fetching SUSFS and Wild Kernel Patches..."
if [ ! -d "${SUSFS_FOLDER}" ]; then
    git clone --depth 1 --branch gki-android16-6.12 https://gitlab.com/simonpunk/susfs4ksu.git "${SUSFS_FOLDER}"

else
    echo "SUSFS already downloaded."
fi

if [ ! -d "${KERNEL_PATCHES_FOLDER}" ]; then
    git clone --depth 1 https://github.com/akronnos/kernel_patches.git "${KERNEL_PATCHES_FOLDER}"
else
    echo "Wild Kernel patches already downloaded."
fi

# 1.5 Clean Up ABI Protected Exports
echo "[1.5/4] Cleaning Up ABI Protected Exports..."
cd "${KERNEL_PLATFORM_FOLDER}"
rm -f common/android/abi_gki_protected_exports_* || true
sed -i 's/protected_modules = \[.*\]/protected_modules = []/' common/modules.bzl || true

# 2. Add KernelSU Next
echo "[2/4] Integrating KernelSU-Next (dev branch)..."
cd "${COMMON_KERNEL_FOLDER}"
if [ ! -d "KernelSU-Next" ]; then
    curl --fail --location --proto '=https' -LSs "https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh" | bash -s 234f6e040fcbca18b16d2398e1aa225712ec99ad
fi

cd "${KSUN_FOLDER}"
git submodule update --init --recursive
cd kernel

COMMITS_COUNT=$(git rev-list --count HEAD)
if [ $COMMITS_COUNT -lt 2684 ]; then
  BASE_VERSION=10200
else
  BASE_VERSION=30000
fi
KSU_VERSION=$(( COMMITS_COUNT + BASE_VERSION ))

# Get the latest git tag for KSU_VERSION_TAG
KSU_GIT_TAG=$(cd "${KSUN_FOLDER}" && git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.1")

# Hardcode version into Kbuild so it works inside bazel sandbox (no .git access).
# The Kbuild uses `ifdef KSU_GIT_VERSION_VALID` to decide whether to use git-derived
# values or emit warnings and fall back to version=1. By injecting this variable
# before the ifdef, and replacing the $(eval ...) lines, we ensure the correct
# version is compiled in even without .git present.
sed -i '/^# Calculate version if git version is available/i \
# Hardcoded for bazel sandbox builds (git not available during build)\
KSU_GIT_VERSION_VALID := 1' Kbuild
sed -i "s/^\$(eval KSU_VERSION=.*/\$(eval KSU_VERSION=${KSU_VERSION})/" Kbuild
sed -i "s/^\$(eval KSU_VERSION_TAG=.*/\$(eval KSU_VERSION_TAG=${KSU_GIT_TAG})/" Kbuild

if [ -f ksu.c ]; then
  sed -i 's/#if defined(CONFIG_STACKPROTECTOR) && (defined(CONFIG_ARM64) && !defined(CONFIG_STACKPROTECTOR_PER_TASK))/#if 0/' ksu.c
fi

# 6.12 specific fixes for Kbuild
if [[ "$KSU_VERSION" -gt 33095 ]]; then
  sed -i 's|ccflags-y += -I$(KSU_KERNEL_DIR) -I$(KSU_KERNEL_DIR)/include|ccflags-y += -I$(KSU_KERNEL_DIR) -I$(KSU_KERNEL_DIR)/include -I$(KSU_KERNEL_DIR)/include/uapi|' Kbuild
  sed -i '/abspath/!s|$(src)|$(abspath $(src))|' Kbuild
  sed -i '/abspath/!s|$(srctree)/$(src)|$(abspath $(srctree)/$(src))|' Kbuild
fi

echo "Adding KSUN Configuration Settings to gki_defconfig"
"$SCRIPTS_CONFIG" --file "${COMMON_KERNEL_FOLDER}/build.config.custom" \
-e CONFIG_KSU \
-d CONFIG_KSU_KPROBES_HOOK

# 3. Apply SUSFS Patches
echo "[3/4] Applying SUSFS Patches..."
cp "${SUSFS_FOLDER}/kernel_patches/fs/"* "${COMMON_KERNEL_FOLDER}/fs/"
cp "${SUSFS_FOLDER}/kernel_patches/include/linux/"* "${COMMON_KERNEL_FOLDER}/include/linux/"

SUSFS_VERSION=$(grep '#define SUSFS_VERSION' "${COMMON_KERNEL_FOLDER}/include/linux/susfs.h" | awk -F'"' '{print $2}')
echo "Detected SUSFS Version: ${SUSFS_VERSION}"

# Apply KernelSU-Next specific SUSFS patch
cd "${KSUN_FOLDER}"
apply_patch "${SUSFS_FOLDER}/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch" "${KSUN_FOLDER}" || true

# Apply version-specific SUSFS fix patches from Wild Kernels
for file in $(find ./kernel -maxdepth 2 -name "*.rej" -exec basename {} .rej \; 2>/dev/null || true); do
  echo "Patching file: $file with fix_$file.patch"
  apply_patch "${KERNEL_PATCHES_FOLDER}/next/susfs_fix_patches/${SUSFS_VERSION}/fix_${file}.patch" "${KSUN_FOLDER}" || true
done
apply_patch "${KERNEL_PATCHES_FOLDER}/next/susfs_fix_patches/${SUSFS_VERSION}/overwrite_hook_mode.patch" "${KSUN_FOLDER}" || true
apply_patch "${KERNEL_PATCHES_FOLDER}/next/susfs_fix_patches/${SUSFS_VERSION}/ksu_toolkit.patch" "${KSUN_FOLDER}" || true

# Apply Core SUSFS kernel patch
cd "${COMMON_KERNEL_FOLDER}"
apply_patch "${SUSFS_FOLDER}/kernel_patches/50_add_susfs_in_gki-android16-6.12.patch" "${COMMON_KERNEL_FOLDER}" || echo "Note: Using fallback patch attempt for SUSFS."

# VMA fallback
if grep -q 'VMA_PAD_START(' ./fs/proc/task_mmu.c && ! grep -qE '#include <linux/pgsize_migration(_inline)?\.h>|define VMA_PAD_START' ./fs/proc/task_mmu.c; then
  sed -i '1a #ifndef VMA_PAD_START\n#define VMA_PAD_START(vma) ((vma)->vm_end)\n#endif' fs/proc/task_mmu.c
fi

# 4. KSU Hooks (VFS)
echo "[4/4] Applying KSU VFS Hooks to common kernel..."
cd "${COMMON_KERNEL_FOLDER}"
if [[ "$SUSFS_VERSION" < "v1.5.13" ]] && [[ "$SUSFS_VERSION" != "v2"* ]]; then
  echo "Applying manual hooks for older SUSFS version..."
  apply_patch "${KERNEL_PATCHES_FOLDER}/next/scope_min_manual_hooks_v1.4.patch" "${COMMON_KERNEL_FOLDER}" || true
else
  echo "Skipping manual hooks (not needed for SUSFS $SUSFS_VERSION)"
fi

echo "=========================================="
echo "    Done! KernelSU-Next + SUSFS Applied   "
echo "=========================================="
