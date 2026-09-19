#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Usage:
#   ./build.sh [OPTIONS] [-- CONFIG_KEY=val ...]
#
# Options:
#   --menuconfig      Open menuconfig after injecting configs (before build)
#   --no-clean        Skip rm -rf out (incremental build)
#   -j N              Override thread count (default: nproc --all)
#   -h, --help        Show this help
#
# Custom configs (after --):
#   Any CONFIG_* arguments after -- are applied via scripts/config.
#   Prefix with - to disable, no prefix or + to enable, key=val to set.
#
# Examples:
#   ./build.sh                                  # standard build
#   ./build.sh --menuconfig                     # open menuconfig before compile
#   ./build.sh -- CONFIG_IKCONFIG=y             # enable IKCONFIG
#   ./build.sh -- -CONFIG_DEBUG_INFO            # disable DEBUG_INFO
#   ./build.sh -- CONFIG_LOCALVERSION=-custom   # set string value
#   ./build.sh --menuconfig -- CONFIG_IKCONFIG=y -CONFIG_DEBUG_INFO
# ─────────────────────────────────────────────

KERNEL_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "${KERNEL_ROOT}"

# Kernel details
export ARCH=arm64
export SUBARCH=arm64

# Toolchain setup
NDK_BIN="/home/akronnos/Singularity/android-ndk-r29/toolchains/llvm/prebuilt/linux-x86_64/bin"
export PATH="${NDK_BIN}:${PATH}"
export LLVM=1

# Defaults
DO_MENUCONFIG=0
DO_CLEAN=1
JOBS=$(nproc --all)
CUSTOM_CONFIGS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --menuconfig)   DO_MENUCONFIG=1; shift ;;
        --no-clean)     DO_CLEAN=0; shift ;;
        -j)             JOBS="$2"; shift 2 ;;
        -h|--help)      sed -n '/^# Usage:/,/^# ---/p' "$0" | sed 's/^# //'; exit 0 ;;
        --)             shift; CUSTOM_CONFIGS=("$@"); break ;;
        *)              echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo "=================================="
echo "    Building Singularity Kernel   "
echo "=================================="

if [ "${DO_CLEAN}" -eq 1 ]; then
    rm -rf out
fi
mkdir -p out

# Base config + oplus + droidspaces specific fragments
make O=out vendor/kona-perf_defconfig vendor/oplus.config vendor/droidspaces.config

# Strip -dirty suffix from kernel version
sed -i "s/printf '%s' -dirty//g" scripts/setlocalversion

# Inject our custom features
echo "Injecting feature configs..."
scripts/config --file out/.config --enable CONFIG_KSU
scripts/config --file out/.config --enable CONFIG_KSU_SUSFS
scripts/config --file out/.config --enable CONFIG_NTSYNC
scripts/config --file out/.config --enable CONFIG_BBG
scripts/config --file out/.config --enable CONFIG_BBG_BLOCK_BOOT
scripts/config --file out/.config --enable CONFIG_VPNHIDE

# Update CONFIG_LSM to append baseband_guard if not already present
if grep -q "CONFIG_LSM=" out/.config; then
    LSM_VAL=$(grep "CONFIG_LSM=" out/.config | cut -d'=' -f2 | tr -d '"')
    if [[ ! "$LSM_VAL" == *"baseband_guard"* ]]; then
        scripts/config --file out/.config --set-str LSM "${LSM_VAL},baseband_guard"
    fi
fi

# Apply custom configs passed after --
if [ ${#CUSTOM_CONFIGS[@]} -gt 0 ]; then
    echo "Applying ${#CUSTOM_CONFIGS[@]} custom config(s)..."
    for cfg in "${CUSTOM_CONFIGS[@]}"; do
        if [[ "${cfg}" == -CONFIG_* ]]; then
            # Disable: -CONFIG_FOO
            key="${cfg#-}"
            echo "  Disabling ${key}"
            scripts/config --file out/.config --disable "${key}"
        elif [[ "${cfg}" == *=y ]]; then
            # Enable: CONFIG_FOO=y
            key="${cfg%%=*}"
            echo "  Enabling ${key}"
            scripts/config --file out/.config --enable "${key}"
        elif [[ "${cfg}" == *=n ]]; then
            # Disable: CONFIG_FOO=n
            key="${cfg%%=*}"
            echo "  Disabling ${key}"
            scripts/config --file out/.config --disable "${key}"
        elif [[ "${cfg}" == *=m ]]; then
            # Module: CONFIG_FOO=m
            key="${cfg%%=*}"
            echo "  Module ${key}"
            scripts/config --file out/.config --module "${key}"
        elif [[ "${cfg}" == *=* ]]; then
            # Set value: CONFIG_FOO=bar or CONFIG_FOO="string"
            key="${cfg%%=*}"
            val="${cfg#*=}"
            echo "  Setting ${key}=${val}"
            scripts/config --file out/.config --set-str "${key#CONFIG_}" "${val}"
        else
            # Bare CONFIG_FOO — treat as enable
            echo "  Enabling ${cfg}"
            scripts/config --file out/.config --enable "${cfg}"
        fi
    done
fi

# Refresh config to resolve dependencies
make O=out olddefconfig

# Menuconfig if requested
if [ "${DO_MENUCONFIG}" -eq 1 ]; then
    echo ""
    echo "Opening menuconfig — save and exit to continue build..."
    make O=out menuconfig
fi

# Build the kernel
echo "Compiling kernel with -j${JOBS}..."
make O=out -j"${JOBS}"

# Check build artifact
IMAGE="out/arch/arm64/boot/Image"
if [ ! -f "$IMAGE" ]; then
    echo "ERROR: Kernel compilation failed. Image not found."
    exit 1
fi

echo "=================================="
echo "      Packaging AnyKernel3        "
echo "=================================="

if [ ! -d "ak3" ]; then
    echo "ERROR: ak3 directory not found. Cannot package."
    exit 1
fi

# Copy the built image into the ak3 directory
cp "$IMAGE" ak3/Image

# Create the zip
cd ak3
ZIP_NAME="Singularity-Kernel-SM8250-$(date +%Y%m%d-%H%M).zip"
zip -r9 "../${ZIP_NAME}" ./* -x "*.git*" -x "README.md" -x "*placeholder"
cd ..

echo ""
echo "SUCCESS: Kernel packaged successfully as ${ZIP_NAME}"
