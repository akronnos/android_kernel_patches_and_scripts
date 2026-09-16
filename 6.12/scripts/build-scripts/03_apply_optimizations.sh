#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# OP15 config: bbr=true, bbr3=false
OP_BBR="true"
OP_BBR3="false"

echo "=========================================="
echo "     Applying Optimization Patches         "
echo "=========================================="

cd "${COMMON_KERNEL_FOLDER}"

echo "Patching optimized_mem_operations..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/optimized_mem_operations.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching file_struct_8bytes_align..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/file_struct_8bytes_align.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching reduce_cache_pressure..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/reduce_cache_pressure.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching mem_opt_prefetch..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/mem_opt_prefetch.patch" "${COMMON_KERNEL_FOLDER}"

# Kernel 6.12 >= 5.16, so use the standard memcmp patch
echo "Patching optimise_memcmp..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/optimise_memcmp.patch" "${COMMON_KERNEL_FOLDER}"

echo "Patching minimise_wakeup_time..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/minimise_wakeup_time.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching int_sqrt..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/int_sqrt.patch" "${COMMON_KERNEL_FOLDER}"

# Skip force_tcp_nodelay since BBR is enabled
if [ "${OP_BBR}" = "false" ] && [ "${OP_BBR3}" = "false" ]; then
  echo "Patching force_tcp_nodelay..."
  apply_patch "${KERNEL_PATCHES_FOLDER}/common/force_tcp_nodelay.patch" "${COMMON_KERNEL_FOLDER}"
else
  echo "Skipping force_tcp_nodelay (BBR/BBRv3 enabled)"
fi

echo "Patching reduce_gc_thread_sleep_time..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/reduce_gc_thread_sleep_time.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching add_timeout_wakelocks_globally..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/add_timeout_wakelocks_globally.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching f2fs_reduce_congestion..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/f2fs_reduce_congestion.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching reduce_freeze_timeout..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/reduce_freeze_timeout.patch" "${COMMON_KERNEL_FOLDER}"

# Kernel 6.12 >= 5.16, use the sed-modified variant
echo "Patching clear_page_16bytes_align..."
cat "${KERNEL_PATCHES_FOLDER}/common/clear_page_16bytes_align.patch" | sed -e 's/SYM_FUNC_START_PI(clear_page)/SYM_FUNC_START_PI(__pi_clear_page)/' > /tmp/clear_page_modified.patch
apply_patch "/tmp/clear_page_modified.patch" "${COMMON_KERNEL_FOLDER}" "-F3"
rm -f /tmp/clear_page_modified.patch

echo "Patching add_limitation_scaling_min_freq..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/add_limitation_scaling_min_freq.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching re_write_limitation_scaling_min_freq..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/re_write_limitation_scaling_min_freq.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching adjust_cpu_scan_order..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/adjust_cpu_scan_order.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching avoid_extra_s2idle_wake_attempts..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/avoid_extra_s2idle_wake_attempts.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching disable_cache_hot_buddy..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/disable_cache_hot_buddy.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching f2fs_enlarge_min_fsync_blocks..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/f2fs_enlarge_min_fsync_blocks.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching increase_ext4_default_commit_age..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/increase_ext4_default_commit_age.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching increase_sk_mem_packets..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/increase_sk_mem_packets.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching reduce_pci_pme_wakeups..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/reduce_pci_pme_wakeups.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching silence_irq_cpu_logspam..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/silence_irq_cpu_logspam.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching silence_system_logspam..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/silence_system_logspam.patch" "${COMMON_KERNEL_FOLDER}"
echo "Patching use_unlikely_wrap_cpufreq..."
apply_patch "${KERNEL_PATCHES_FOLDER}/common/use_unlikely_wrap_cpufreq.patch" "${COMMON_KERNEL_FOLDER}"

echo "=========================================="
echo "     Done! Optimization Patches Applied    "
echo "=========================================="
