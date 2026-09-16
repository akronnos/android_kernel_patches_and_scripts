#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

NTSYNC_FOLDER="${KERNEL_PATCHES_FOLDER}/common/ntsync"
NTSYNC_PATCH="${NTSYNC_FOLDER}/ntsync_compat_android16-6.12.patch"

echo "Applying NTSync patch for Android 16 (6.12)..."
cd "${COMMON_KERNEL_FOLDER}"

echo "Removing pre-existing ntsync files for android16-6.12..."
rm -f include/uapi/linux/ntsync.h
rm -f drivers/misc/ntsync.c

echo "Patching compatibility layer: $(basename ${NTSYNC_PATCH})"
apply_patch "${NTSYNC_PATCH}" "${COMMON_KERNEL_FOLDER}"

echo "Patching ntsync_base!"
apply_patch "${NTSYNC_FOLDER}/ntsync_base.patch" "${COMMON_KERNEL_FOLDER}"
"$SCRIPTS_CONFIG" --file "$COMMON_KERNEL_FOLDER/build.config.custom" \
-e CONFIG_NTSYNC
echo "Done applying NTSync!"
