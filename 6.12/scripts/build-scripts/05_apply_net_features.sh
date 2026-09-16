#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "=========================================="
echo "  Applying Network Features (BBR/TTL/IP)   "
echo "=========================================="

cd "${COMMON_KERNEL_FOLDER}"

# 1. BBR (enabled, bbr3 disabled per OP15 config)
echo "[1/4] Adding BBR support..."
"$SCRIPTS_CONFIG" --file "${GKI_DEFCONFIG}" \
-e CONFIG_TCP_CONG_ADVANCED \
-e CONFIG_TCP_CONG_BBR \
-d CONFIG_TCP_CONG_HTCP \
-d CONFIG_TCP_CONG_BIC \
-d CONFIG_TCP_CONG_WESTWOOD
echo "  ✅ BBR added"

# 2. Net schedulers (qdisc) — always enabled
echo "[2/4] Enabling net schedulers (qdisc)..."
"$SCRIPTS_CONFIG" --file "${GKI_DEFCONFIG}" \
-e CONFIG_NET_SCH_FQ \
-e CONFIG_NET_SCH_FQ_CODEL \
-e CONFIG_NET_SCH_CAKE \
-e CONFIG_NET_SCH_PIE \
-e CONFIG_NET_SCH_FQ_PIE
echo "  ✅ Net schedulers added"

# 3. TTL target support
echo "[3/4] Adding TTL target support..."
"$SCRIPTS_CONFIG" --file "${GKI_DEFCONFIG}" \
-e CONFIG_IP_NF_TARGET_TTL \
-e CONFIG_IP6_NF_TARGET_HL \
-e CONFIG_IP6_NF_MATCH_HL
echo "  ✅ TTL support added"

# 4. IP SET & IPv6 NAT support
# Note: CONFIG_BPF_STREAM_PARSER skipped for kernel 6.12
echo "[4/4] Adding IP SET & IPv6 NAT support..."
"$SCRIPTS_CONFIG" --file "${GKI_DEFCONFIG}" \
-e CONFIG_IP_SET \
--set-val CONFIG_IP_SET_MAX 65534 \
-e CONFIG_IP_SET_BITMAP_IP \
-e CONFIG_IP_SET_BITMAP_IPMAC \
-e CONFIG_IP_SET_BITMAP_PORT \
-e CONFIG_IP_SET_HASH_IP \
-e CONFIG_IP_SET_HASH_IPMARK \
-e CONFIG_IP_SET_HASH_IPPORT \
-e CONFIG_IP_SET_HASH_IPPORTIP \
-e CONFIG_IP_SET_HASH_IPPORTNET \
-e CONFIG_IP_SET_HASH_IPMAC \
-e CONFIG_IP_SET_HASH_MAC \
-e CONFIG_IP_SET_HASH_NETPORTNET \
-e CONFIG_IP_SET_HASH_NET \
-e CONFIG_IP_SET_HASH_NETNET \
-e CONFIG_IP_SET_HASH_NETPORT \
-e CONFIG_IP_SET_HASH_NETIFACE \
-e CONFIG_IP_SET_LIST_SET \
-e CONFIG_NETFILTER_XT_MATCH_ADDRTYPE \
-e CONFIG_NETFILTER_XT_SET \
-e CONFIG_IP6_NF_NAT \
-e CONFIG_IP6_NF_TARGET_MASQUERADE
echo "  ✅ IP SET & IPv6 NAT added"

echo "=========================================="
echo "  Done! Network Features Applied            "
echo "=========================================="
