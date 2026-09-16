#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "=========================================="
echo "    Injecting Config Fragments             "
echo "=========================================="

if [ -f "${COMMON_KERNEL_FOLDER}/build.config.custom" ]; then
  # Inject build.config.custom into post_defconfig_fragments of kernel_aarch64
  # We look for the kernel_aarch64 target and its defconfig line
  
  if ! grep -q 'post_defconfig_fragments.*build.config.custom' "$BAZEL_FILE"; then
    sed -i '/name = "kernel_aarch64",/,/defconfig = / s/\(defconfig = .*\)/\1\n    post_defconfig_fragments = ["build.config.custom"],/' "$BAZEL_FILE"
    echo "  ✅ Injected build.config.custom into kernel_aarch64"
  else
    echo "  ⚠️ build.config.custom already in post_defconfig_fragments"
  fi
else
  echo "  ⚠️ build.config.custom not found, skipping."
fi
