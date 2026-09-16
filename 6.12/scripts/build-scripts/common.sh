#!/bin/bash

WORKSPACE_ROOT="/home/akronnos/op15_nvme/op15_workspace"
KERNEL_PLATFORM_FOLDER="${WORKSPACE_ROOT}/kernel_platform"
COMMON_KERNEL_FOLDER="${KERNEL_PLATFORM_FOLDER}/common"
KERNEL_PATCHES_FOLDER="${WORKSPACE_ROOT}/kernel_patches"
SOC_REPO_FOLDER="${KERNEL_PLATFORM_FOLDER}/soc-repo"
GKI_DEFCONFIG="${COMMON_KERNEL_FOLDER}/build.config.custom"
SCRIPTS_CONFIG="${SOC_REPO_FOLDER}/scripts/config"
BAZEL_FILE="${COMMON_KERNEL_FOLDER}/BUILD.bazel"

# Apply a patch idempotently: succeed if fresh, skip if already applied, fail otherwise.
apply_patch() {
  local patch_file="$1"
  local patch_dir="${2:-.}"
  local patch_args="${3:-}"
  local patch_name
  patch_name="$(basename "$patch_file")"

  cd "$patch_dir"
  # Check if already fully applied
  if patch -p1 ${patch_args} -R --dry-run -i "$patch_file" < /dev/null > /dev/null 2>&1; then
    echo "  Already applied. Skipping: $patch_name"
  else
    # Try to apply it forward. We do not do a dry run first because some patches 
    # (like the SUSFS ones) are expected to fail partially and leave .rej files 
    # for later fixup scripts. 
    if ! patch -p1 ${patch_args} --forward -i "$patch_file" < /dev/null; then
      echo "ERROR: patch failed to apply cleanly (may have left .rej files): $patch_name" >&2
      cd - > /dev/null
      return 1
    fi
  fi
  cd - > /dev/null
  return 0
}
