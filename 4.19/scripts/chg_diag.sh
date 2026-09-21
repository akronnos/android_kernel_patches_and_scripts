#!/bin/sh
# chg_diag.sh - Diagnostic script for OnePlus SM8250 charging status
# Run via adb shell (with root) or Termux (with su)

cat << "EOF"
============================================================
           OnePlus SM8250 Charging Diagnostic Tool          
============================================================
EOF

if [ "$(id -u)" -ne 0 ]; then
    echo "[!] Warning: Not running as root. Some sysfs/dmesg nodes may be unreadable."
    echo "    Run: su -c 'sh $0' or adb root"
fi

echo ""
echo "--- [1] Battery Status (/sys/class/power_supply/battery) ---"
BAT_DIR="/sys/class/power_supply/battery"
if [ -d "$BAT_DIR" ]; then
    STATUS=$(cat "$BAT_DIR/status" 2>/dev/null)
    CAPACITY=$(cat "$BAT_DIR/capacity" 2>/dev/null)
    TEMP=$(cat "$BAT_DIR/temp" 2>/dev/null)
    VOLT_UV=$(cat "$BAT_DIR/voltage_now" 2>/dev/null)
    CURR_UA=$(cat "$BAT_DIR/current_now" 2>/dev/null)
    CHARGE_TYPE=$(cat "$BAT_DIR/charge_type" 2>/dev/null)

    # Calculate volts, amps, watts
    VOLT_V=$(awk "BEGIN {printf \"%.3f\", ${VOLT_UV:-0} / 1000000}")
    CURR_MA=$(awk "BEGIN {printf \"%.1f\", ${CURR_UA:-0} / 1000}")
    PWR_W=$(awk "BEGIN {printf \"%.2f\", (${VOLT_UV:-0} / 1000000) * (${CURR_UA:-0} / 1000000)}")
    TEMP_C=$(awk "BEGIN {printf \"%.1f\", ${TEMP:-0} / 10}")

    echo "  Status        : $STATUS"
    echo "  Capacity (SOC): $CAPACITY %"
    echo "  Battery Temp  : $TEMP_C °C"
    echo "  Battery Volt  : $VOLT_V V ($VOLT_UV uV)"
    echo "  Battery Curr  : $CURR_MA mA ($CURR_UA uA)"
    echo "  Battery Power : $PWR_W W"
    echo "  Charge Type   : $CHARGE_TYPE"
else
    echo "  [!] Battery node not found at $BAT_DIR"
fi

echo ""
echo "--- [2] USB Power Supply (/sys/class/power_supply/usb) ---"
USB_DIR="/sys/class/power_supply/usb"
if [ -d "$USB_DIR" ]; then
    USB_ONLINE=$(cat "$USB_DIR/online" 2>/dev/null)
    USB_TYPE=$(cat "$USB_DIR/type" 2>/dev/null)
    USB_REAL_TYPE=$(cat "$USB_DIR/real_type" 2>/dev/null)
    VBUS_UV=$(cat "$USB_DIR/voltage_now" 2>/dev/null)
    VBUS_MAX_UV=$(cat "$USB_DIR/voltage_max" 2>/dev/null)
    ICL_UA=$(cat "$USB_DIR/current_max" 2>/dev/null)
    PD_ACTIVE=$(cat "$USB_DIR/pd_active" 2>/dev/null)
    PD_AUTH=$(cat "$USB_DIR/pd_authentication" 2>/dev/null)

    VBUS_V=$(awk "BEGIN {printf \"%.3f\", ${VBUS_UV:-0} / 1000000}")
    ICL_MA=$(awk "BEGIN {printf \"%.1f\", ${ICL_UA:-0} / 1000}")
    IN_PWR_W=$(awk "BEGIN {printf \"%.2f\", (${VBUS_UV:-0} / 1000000) * (${ICL_UA:-0} / 1000000)}")

    echo "  Connected     : $USB_ONLINE"
    echo "  Reported Type : $USB_TYPE"
    echo "  Real Type     : $USB_REAL_TYPE"
    echo "  VBUS Voltage  : $VBUS_V V ($VBUS_UV uV)"
    echo "  VBUS Max Volt : $(awk "BEGIN {printf \"%.2f\", ${VBUS_MAX_UV:-0} / 1000000}") V"
    echo "  Input ICL Max : $ICL_MA mA ($ICL_UA uA)"
    echo "  Input Max Pwr : $IN_PWR_W W"
    echo "  PD Active     : $PD_ACTIVE"
    echo "  PD Authenticated: $PD_AUTH"
else
    echo "  [!] USB node not found at $USB_DIR"
fi

echo ""
echo "--- [3] USB Power Delivery State (/sys/class/usbpd/usbpd0) ---"
PD_DIR="/sys/class/usbpd/usbpd0"
if [ -d "$PD_DIR" ]; then
    echo "  Power Role    : $(cat "$PD_DIR/current_pr" 2>/dev/null)"
    echo "  Data Role     : $(cat "$PD_DIR/current_dr" 2>/dev/null)"
    echo "  Active Contract: $(cat "$PD_DIR/contract" 2>/dev/null)"
    echo ""
    echo "  Requested RDO (What phone asked):"
    cat "$PD_DIR/rdo_h" 2>/dev/null | sed 's/^/    /'
    echo ""
    echo "  Available Source PDOs (What charger/hub offered):"
    cat "$PD_DIR/pdo_h" 2>/dev/null | sed 's/^/    /'
else
    echo "  [!] usbpd0 node not found at $PD_DIR"
fi

echo ""
echo "--- [4] OPlus Procfs Charger State (/proc/charger) ---"
if [ -d "/proc/charger" ]; then
    echo "  input_current_now   : $(cat /proc/charger/input_current_now 2>/dev/null)"
    echo "  fastcharge_fail_cnt : $(cat /proc/charger/fastcharge_fail_count 2>/dev/null)"
    echo "  passedchg           : $(cat /proc/charger/passedchg 2>/dev/null)"
    echo "  hmac status         : $(cat /proc/charger/hmac 2>/dev/null)"
else
    echo "  [!] /proc/charger not found"
fi

echo ""
echo "--- [5] Recent Kernel Charging & USB-PD Logs (dmesg) ---"
dmesg | grep -E -i "oplus.*chg|smblib|usbpd|vooc|apsd|pd_select|pdo|icl" | tail -n 35 | sed 's/^/  /'

echo ""
echo "============================================================"
echo " Diagnostic complete. Please copy the output above."
echo "============================================================"
