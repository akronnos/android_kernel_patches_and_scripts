#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "=========================================="
echo "       Applying Baseband Guard (BBG)       "
echo "=========================================="

cd "${KERNEL_PLATFORM_FOLDER}"

echo "[1/3] Running BBG setup script..."
if ! wget -O- https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh | bash -s main; then
  echo "WARNING: BBG setup script failed, continuing anyway"
fi

echo "[2/3] Applying BBG efisp abl whitelist patch (sm8850)..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/bbg/0001-Enable-abl-and-efisp-flashing-for-efisp-exploit-devices.patch" "${KERNEL_PLATFORM_FOLDER}"

# BBG's setup.sh creates a symlink: common/security/baseband-guard → ../../Baseband-guard
# This breaks in bazel's sandbox because the symlink target is outside common/.
# Replace the symlink with an actual copy so the files are inside the sandbox.
if [ -L "${COMMON_KERNEL_FOLDER}/security/baseband-guard" ]; then
  echo "  Replacing BBG symlink with actual copy (bazel sandbox fix)..."
  rm -f "${COMMON_KERNEL_FOLDER}/security/baseband-guard"
  cp -r "${KERNEL_PLATFORM_FOLDER}/Baseband-guard" "${COMMON_KERNEL_FOLDER}/security/baseband-guard"
  rm -rf "${KERNEL_PLATFORM_FOLDER}/Baseband-guard"
fi

echo "[3/3] Adding BBG config and LSM entry..."
"$SCRIPTS_CONFIG" --file "${COMMON_KERNEL_FOLDER}/build.config.custom" \
-e CONFIG_BBG
sed -i '/^config LSM$/,/^help$/{ /^[[:space:]]*default/ { /baseband_guard/! s/selinux/selinux,baseband_guard/ } }' "${COMMON_KERNEL_FOLDER}/security/Kconfig"

echo "=========================================="
echo "         Done! BBG Applied                 "
echo "=========================================="
