#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

echo "=========================================="
echo "    Applying Kali NetHunter Patches        "
echo "=========================================="

# 1. Add NetHunter Kconfigs
echo "[1/6] Injecting NetHunter Configs..."
"$SCRIPTS_CONFIG" --file "${COMMON_KERNEL_FOLDER}/build.config.custom" \
-d CONFIG_USB_CONFIGFS_RNDIS \
-d CONFIG_USB_F_RNDIS \
-d CONFIG_CFG80211_WEXT \
-e CONFIG_WIRELESS \
-e CONFIG_WIRELESS_EXT \
-e CONFIG_WEXT_CORE \
-e CONFIG_WEXT_PROC \
-e CONFIG_WEXT_PRIV \
-e CONFIG_BRIDGE \
-e CONFIG_TUN \
-e CONFIG_VETH \
-e CONFIG_DUMMY \
-e CONFIG_PACKET \
-e CONFIG_USB_STORAGE \
-m CONFIG_USB_ACM \
-m CONFIG_USB_SERIAL \
-m CONFIG_USB_SERIAL_FTDI_SIO \
-m CONFIG_USB_NET_CDC_SUBSET \
-m CONFIG_USB_NET_RNDIS_HOST \
-m CONFIG_CFG80211 \
-m CONFIG_MAC80211 \
-e CONFIG_LEDS_TRIGGERS \
-e CONFIG_WLAN_VENDOR_ATH \
-e CONFIG_WLAN_VENDOR_RALINK \
-e CONFIG_WLAN_VENDOR_REALTEK \
-m CONFIG_RTL8XXXU \
-e CONFIG_RTL8XXXU_UNTESTED \
-m CONFIG_RT2X00 \
-m CONFIG_RT2800USB \
-e CONFIG_RT2800USB_RT3573 \
-e CONFIG_RT2800USB_RT33XX \
-e CONFIG_RT2800USB_RT35XX \
-e CONFIG_RT2800USB_RT53XX \
-e CONFIG_RT2800USB_RT55XX \
-e CONFIG_RT2800USB_UNKNOWN \
-m CONFIG_RT2800_LIB \
-m CONFIG_RT2X00_LIB_USB \
-m CONFIG_RT2X00_LIB \
-e CONFIG_RT2X00_LIB_FIRMWARE \
-m CONFIG_ATH_COMMON \
-m CONFIG_ATH9K_HW \
-m CONFIG_ATH9K_COMMON \
-m CONFIG_ATH9K_HTC \
-e CONFIG_ATH9K_HTC_DEBUGFS \
-m CONFIG_BT_HCIBTUSB \
-e CONFIG_BT_HCIBTUSB_MTK \
-e CONFIG_BT_HCIBTUSB_RTL \
-e CONFIG_USB_SERIAL_GENERIC \
-m CONFIG_USB_SERIAL_CH341 \
-m CONFIG_USB_SERIAL_CP210X \
-m CONFIG_USB_SERIAL_PL2303 \
-m CONFIG_USB_SERIAL_OPTION \
-m CONFIG_CIFS \
-e CONFIG_CIFS_XATTR \
-e CONFIG_CIFS_POSIX \
-m CONFIG_NFS_FS \
-m CONFIG_NFS_V3 \
-m CONFIG_NFS_V4 \
-m CONFIG_NFSD \
-e CONFIG_NFSD_V4 \
-m CONFIG_LOCKD \
-m CONFIG_SUNRPC \
-m CONFIG_PACKET_DIAG \
-e CONFIG_NL80211_TESTMODE

# 2. Source Code Patches (Monitor Mode & WEXT)
echo "[2/6] Patching mac80211/cfg80211 for NetHunter..."
apply_patch "$KERNEL_PATCHES_FOLDER/common/nethunter-6.12.patch" "${COMMON_KERNEL_FOLDER}"

# 3. GKI Namespace Restrictions Bypass for NFS/CIFS
echo "[3/6] Fixing GKI VFS Namespace Restrictions..."
for file in "fs/smb/client/cifsfs.c" "fs/nfs/inode.c" "fs/nfs/nfs4super.c" "net/sunrpc/sunrpc_syms.c" "fs/nfsd/nfsctl.c"; do
  if ! grep -q "VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver" "${COMMON_KERNEL_FOLDER}/${file}"; then
    echo "MODULE_IMPORT_NS(VFS_internal_I_am_really_a_filesystem_and_am_NOT_a_driver);" >> "${COMMON_KERNEL_FOLDER}/${file}"
  fi
done

# 4. Strict Config Fixes for device build
echo "[4/6] Adjusting device strict Kconfig expectations..."
sed -i "/select MAC80211_LEDS/d" "${COMMON_KERNEL_FOLDER}/drivers/net/wireless/ath/ath9k/Kconfig"

# 5. Injecting compiled modules into BUILD.bazel
echo "[5/6] Registering NetHunter modules in BUILD.bazel..."
cat << 'PYEOF' > patch_implicit.py
import re
import sys

bazel_file = sys.argv[1]
extra = """
    "net/sunrpc/auth_gss/rpcsec_gss_krb5.ko",
    "drivers/net/wireless/ath/ath.ko",
    "fs/nfs_common/grace.ko",
    "drivers/bluetooth/btmtk.ko",
    "fs/lockd/lockd.ko",
    "drivers/net/wireless/ralink/rt2x00/rt2800usb.ko",
    "drivers/bluetooth/btusb.ko",
    "drivers/net/wireless/ralink/rt2x00/rt2800lib.ko",
    "fs/nfsd/nfsd.ko",
    "net/dns_resolver/dns_resolver.ko",
    "fs/smb/common/cifs_arc4.ko",
    "drivers/net/wireless/realtek/rtl8xxxu/rtl8xxxu.ko",
    "drivers/usb/serial/option.ko",
    "drivers/net/wireless/ralink/rt2x00/rt2x00usb.ko",
    "fs/nfs/nfsv3.ko",
    "fs/nfs/nfsv4.ko",
    "drivers/usb/serial/ch341.ko",
    "fs/nfs/nfs.ko",
    "net/wireless/cfg80211.ko",
    "drivers/net/wireless/ath/ath9k/ath9k_common.ko",
    "drivers/net/usb/cdc_subset.ko",
    "fs/smb/client/cifs.ko",
    "net/sunrpc/sunrpc.ko",
    "drivers/bluetooth/btintel.ko",
    "fs/nls/nls_ucs2_utils.ko",
    "net/sunrpc/auth_gss/auth_rpcgss.ko",
    "drivers/net/wireless/ralink/rt2x00/rt2x00lib.ko",
    "net/packet/af_packet_diag.ko",
    "net/mac80211/mac80211.ko",
    "fs/smb/common/cifs_md4.ko",
    "drivers/bluetooth/btrtl.ko",
    "drivers/net/usb/rndis_host.ko",
    "drivers/usb/serial/pl2303.ko",
    "drivers/net/wireless/ath/ath9k/ath9k_hw.ko",
    "drivers/net/wireless/ath/ath9k/ath9k_htc.ko",
    "drivers/usb/serial/cp210x.ko",
    "drivers/usb/serial/usb_wwan.ko",
"""

with open(bazel_file, "r") as f:
    content = f.read()

# Make sure we don't duplicate
if "module_implicit_outs = get_gki_modules_list(\"arm64\") + get_kunit_modules_list(\"arm64\") +" not in content:
    content = re.sub(r'(module_implicit_outs = get_gki_modules_list\("arm64"\) \+ get_kunit_modules_list\("arm64"\))', r'\1 + [' + extra + ']', content)
    with open(bazel_file, "w") as f:
        f.write(content)
        print("  Patched BUILD.bazel with module list")
PYEOF
python3 patch_implicit.py "$BAZEL_FILE"
rm patch_implicit.py

# 6. Patching qcacld-3.0 for Packet Injection
echo "[6/6] Patching qcacld-3.0 for internal Wi-Fi Packet Injection..."
apply_patch "$KERNEL_PATCHES_FOLDER/common/canoe-peach-v2-qcacld-3.0-frame-injection-6.12.patch" "${WORKSPACE_ROOT}"

echo "=========================================="
echo "    Done Applying NetHunter Patches        "
echo "=========================================="

