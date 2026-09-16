#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# OP15 config
OP_RUST_BUILD="true"

echo "=========================================="
echo "     Applying Droidspaces Support          "
echo "=========================================="

cd "${COMMON_KERNEL_FOLDER}"

# 1. SYSVIPC ABI fix for sm8850
echo "[1/3] Patching SYSVIPC ABI fix (sm8850)..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/droidspaces/fix_sysvipc_kabi_a16-6.12.patch" "${COMMON_KERNEL_FOLDER}"
echo "  ✅ SYSVIPC ABI fix applied"

# 2. Ghost task fix for oplus_bsp_midas
echo "[2/3] Patching ghost task fix..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/droidspaces/0001-Return-ghost-task-if-task-is-null-and-is-requested-b.patch" "${COMMON_KERNEL_FOLDER}"
echo "  ✅ Ghost task fix applied"

# 3. Droidspaces config flags
echo "[3/3] Adding Droidspaces defconfig entries..."
"$SCRIPTS_CONFIG" --file "${GKI_DEFCONFIG}" \
-e CONFIG_SYSVIPC \
-e CONFIG_DEVTMPFS \
-e CONFIG_PID_NS \
-e CONFIG_POSIX_MQUEUE \
-e CONFIG_NETFILTER_XT_TARGET_LOG \
-e CONFIG_NETFILTER_XT_MATCH_RECENT \
-e CONFIG_USER_NS

# Add IPC namespace symbols for rust binder (OP15 has rust_build=true)
if [ "${OP_RUST_BUILD}" = "true" ]; then
  echo "Adding IPC NS missing symbols for rust binder..."
  if ! grep -q 'EXPORT_SYMBOL.*put_ipc_ns' "${COMMON_KERNEL_FOLDER}/ipc/namespace.c"; then
    echo -e '\nEXPORT_SYMBOL_GPL(put_ipc_ns);' >> "${COMMON_KERNEL_FOLDER}/ipc/namespace.c"
  fi
  if ! grep -q 'EXPORT_SYMBOL.*init_ipc_ns' "${COMMON_KERNEL_FOLDER}/ipc/msgutil.c"; then
    echo -e '\nEXPORT_SYMBOL_GPL(init_ipc_ns);' >> "${COMMON_KERNEL_FOLDER}/ipc/msgutil.c"
  fi
  echo "  ✅ IPC NS symbols added"
fi

echo "=========================================="
echo "     Done! Droidspaces Applied             "
echo "=========================================="
