#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "=========================================="
echo "    Cleaning kernel_platform/common        "
echo "=========================================="

# 1. Reset common kernel tree to pristine state
echo "[1/4] Resetting common kernel git tree..."
cd "${COMMON_KERNEL_FOLDER}"
git checkout -- .
git clean -fdx
echo "  ✅ common/ reset to HEAD"

# 2. Remove KernelSU-Next (installed by setup.sh)
echo "[2/4] Removing KernelSU-Next..."
if [ -L "${COMMON_KERNEL_FOLDER}/drivers/kernelsu" ]; then
  rm -f "${COMMON_KERNEL_FOLDER}/drivers/kernelsu"
  echo "  Removed drivers/kernelsu symlink"
fi
if [ -d "${COMMON_KERNEL_FOLDER}/KernelSU-Next" ]; then
  rm -rf "${COMMON_KERNEL_FOLDER}/KernelSU-Next"
  echo "  Removed KernelSU-Next directory"
fi
echo "  ✅ KernelSU-Next removed"

# 3. Remove BBG (installed by setup.sh into kernel_platform/)
echo "[3/4] Removing Baseband Guard..."
if [ -d "${KERNEL_PLATFORM_FOLDER}/Baseband-guard" ]; then
  rm -rf "${KERNEL_PLATFORM_FOLDER}/Baseband-guard"
  rm -rf "${COMMON_KERNEL_FOLDER}/security/baseband-guard/"
  echo "  Removed Baseband-guard directory"
fi
if [ -L "${COMMON_KERNEL_FOLDER}/security/baseband_guard" ]; then
  rm -f "${COMMON_KERNEL_FOLDER}/security/baseband_guard"
  echo "  Removed security/baseband_guard symlink"
elif [ -d "${COMMON_KERNEL_FOLDER}/security/baseband_guard" ]; then
  rm -rf "${COMMON_KERNEL_FOLDER}/security/baseband_guard"
  echo "  Removed security/baseband_guard directory"
fi
echo "  ✅ BBG removed"

# 4. Clean bazel state to force rebuild
echo "[4/4] Cleaning bazel state..."
cd "${KERNEL_PLATFORM_FOLDER}"
if [ -x "./tools/bazel" ]; then
  ./tools/bazel clean --expunge 2>/dev/null || true
  echo "  ✅ bazel expunged"
else
  echo "  ⚠️  bazel not found, skipping"
fi

echo ""
echo "=========================================="
echo "    Clean complete! Ready to re-patch.     "
echo "=========================================="

# 5. Initialize custom config fragment (Step 5/5)
touch "${COMMON_KERNEL_FOLDER}/build.config.custom"
echo "  ✅ build.config.custom created"
