#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# OP15 config values
OP_BBR="true"
OP_BBR3="false"
OP_IP_SET="true"
OP_BLACKLIST_MODULES="kernelsu,oplus_security_guard,oplus_qr_scan,oplus_score,oplus_vip_task,oplus_dns_cache,oplus_network_linkpower_module,oplus_data_module,oplus_secure_harden,oplus_security_keventupload,oplus_secure_guard_new,oplus_secure_guard,coresight_tpda,coresight_tgu,coresight_trace_noc,coresight_cti,coresight_qmi,coresight_dummy,coresight_remote_etm,coresight_tpdm,coresight_uetm,coresight_stm,coresight_tmc_sec,f_fs_ipc_log,qti_battery_debug,rdbg,stm_heartbeat,stm_p_ost,stm_core,stm_ftrace,stm_console,spmi_pmic_arb_debug"

echo "=========================================="
echo " Applying Misc Features (Unicode/Tmpfs/    "
echo " Fake Config/Module Overlay/Blacklist/     "
echo " Build Configs)                            "
echo "=========================================="

cd "${COMMON_KERNEL_FOLDER}"

# 1. Unicode bypass fix (kernel 6.12 >= 5.16, use 6.1+ variant)
echo "[1/7] Applying Unicode bypass fix..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/unicode_bypass_fix_6.1+.patch" "${COMMON_KERNEL_FOLDER}"
echo "  ✅ Unicode fix applied"

# 2. Tmpfs support — always enabled
echo "[2/7] Adding Tmpfs support..."
"$SCRIPTS_CONFIG" --file "${GKI_DEFCONFIG}" \
-e CONFIG_TMPFS_XATTR \
-e CONFIG_TMPFS_POSIX_ACL
echo "  ✅ Tmpfs support added"

# 3. Build-based configs — always enabled
echo "[3/7] Adding build-based configs..."
"$SCRIPTS_CONFIG" --file "${GKI_DEFCONFIG}" \
-e CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE \
-d CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE_O3 \
--set-val CONFIG_FRAME_WARN 0 \
-e CONFIG_TRACEPOINTS
echo "  ✅ Build configs added"

# 4. Rust build configs (OP15 has rust_build=true)
echo "[4/7] Adding Rust build configs..."
"$SCRIPTS_CONFIG" --file "${GKI_DEFCONFIG}" \
-m CONFIG_ANDROID_BINDER_IPC_RUST \
-e CONFIG_RUST
echo "  ✅ Rust build configs added"

# 5. Fake config.gz patch
echo "[5/7] Applying fake config.gz patch..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/fake_config.patch" "${COMMON_KERNEL_FOLDER}"
echo "  ✅ Fake config.gz applied"

# 6. Module overlay mechanism
echo "[6/7] Applying module intercept and overlay mechanism..."
apply_patch "${KERNEL_PATCHES_FOLDER}/oneplus/module_overlay/0001-module-Add-module-intercept-and-overlay-mechanism-android16-6.12.patch" "${COMMON_KERNEL_FOLDER}"
if [ -d "${COMMON_KERNEL_FOLDER}/kernel/module/module_overlay/" ]; then
  chmod +x ./kernel/module/module_overlay/convert_overlay.sh
elif [ -d "${COMMON_KERNEL_FOLDER}/kernel/module_overlay/" ]; then
  chmod +x ./kernel/module_overlay/convert_overlay.sh
fi
echo "  ✅ Module overlay applied"

# 7. Disable vendor/kernel modules (blacklist)
echo "[7/7] Disabling vendor/kernel modules..."

# Modules that MUST NEVER be blacklisted
RISKY_MODULES=("coresight" "rust_binder" "msm_kgsl" "camera" "oplusboot" "rmnet_wlan" "rmnet_core" "msm_drm" "cnss2" "oplus_chg_v2" "reboot_mode" "rfkill" "bootloader_log")

declare -a modules=()
IFS=',' read -ra ADDR <<< "${OP_BLACKLIST_MODULES}"
for mod in "${ADDR[@]}"; do
  [[ -n "$mod" ]] && modules+=("$mod")
done

# Auto-add oplus_network_tuning when BBR is enabled
if [ "${OP_BBR}" = "true" ] || [ "${OP_BBR3}" = "true" ]; then
  if [[ ! " ${modules[*]} " =~ " oplus_network_tuning " ]]; then
    modules+=("oplus_network_tuning")
  fi
  if [[ ! " ${modules[*]} " =~ " oplus_networks_tuning " ]]; then
    modules+=("oplus_networks_tuning")
  fi
fi

# Safety validation — filter out risky modules
declare -a validated_modules=()
for mod in "${modules[@]}"; do
  is_risky=false
  for risky in "${RISKY_MODULES[@]}"; do
    if [ "$mod" = "$risky" ]; then
      is_risky=true
      echo "  ⚠️  Blocked attempt to blacklist protected module: $mod"
      break
    fi
  done
  if [ "$is_risky" = false ]; then
    validated_modules+=("$mod")
  fi
done

if [ ${#validated_modules[@]} -gt 0 ]; then
  RAW_JOINED=$(IFS=,; echo "${validated_modules[*]}")
  RAW_JOINED="${RAW_JOINED}"
  RESULT_LIST="\"${RAW_JOINED}\""
else
  RAW_JOINED=""
  RESULT_LIST='""'
fi

echo "  Disabling modules: ${RESULT_LIST}"
"$SCRIPTS_CONFIG" --file "${GKI_DEFCONFIG}" --set-str CONFIG_DEBLOAT_VENDOR_MODULES "$RAW_JOINED"
# The raw string above correctly delegates escaping to scripts/config

# Kernel 6.12 >= 5.16, use the 6.1+ variant
apply_patch "${KERNEL_PATCHES_FOLDER}/common/vendor_modules/0001-Support-conditional-vendor-modules-blacklisting-6.1-and-above.patch" "${COMMON_KERNEL_FOLDER}"
echo "  ✅ Module blacklist applied"

echo "=========================================="
echo "      Done! Misc Features Applied          "
echo "=========================================="
