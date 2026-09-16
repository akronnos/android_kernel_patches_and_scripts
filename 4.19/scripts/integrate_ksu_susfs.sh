#!/bin/bash
# integrate_ksu_susfs.sh
#
# Automated integration of KernelSU + SUSFS + custom patches
# for the OnePlus SM8250 4.19 kernel.
#
# This script is idempotent at the clone step and destructive
# at the patch step — it assumes a clean kernel tree.

set -euo pipefail

KERNEL_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
NGKI_REPO="https://github.com/cyberc3dr/nGKI_Kernel_Build"
NGKI_DIR="${KERNEL_ROOT}/nGKI_Kernel_Build"
KSU_SETUP_URL="https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh"
PATCHES_DIR="${KERNEL_ROOT}/android_kernel_patches_and_scripts/4.19/patches"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[+]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[-]${NC} $*"; }
log_step()  { echo -e "\n${GREEN}==== $* ====${NC}"; }

die() { log_error "$*"; exit 1; }

cd "${KERNEL_ROOT}"

# ─────────────────────────────────────────────
# Step 1: Clone nGKI_Kernel_Build if needed
# ─────────────────────────────────────────────
log_step "Step 1: nGKI_Kernel_Build repository"

if [ -d "${NGKI_DIR}/.git" ]; then
    log_info "nGKI_Kernel_Build already cloned, pulling latest..."
    git -C "${NGKI_DIR}" pull --ff-only || log_warn "Pull failed, using existing state"
else
    log_info "Cloning nGKI_Kernel_Build..."
    git clone "${NGKI_REPO}" "${NGKI_DIR}"
fi

# Validate expected files exist
[ -f "${NGKI_DIR}/Patches/Patch/susfs_patch_to_4.19.patch" ] || \
    die "susfs_patch_to_4.19.patch not found in nGKI_Kernel_Build"
[ -f "${NGKI_DIR}/Patches/susfs_inline_hook_patches.sh" ] || \
    die "susfs_inline_hook_patches.sh not found in nGKI_Kernel_Build"
[ -f "${NGKI_DIR}/Patches/backport_patches.sh" ] || \
    die "backport_patches.sh not found in nGKI_Kernel_Build"

# ─────────────────────────────────────────────
# Step 2: Apply KernelSU
# ─────────────────────────────────────────────
log_step "Step 2: KernelSU (ReSukiSU)"

if [ -d "${KERNEL_ROOT}/KernelSU" ] && [ -L "${KERNEL_ROOT}/drivers/kernelsu" ]; then
    log_info "KernelSU already present, skipping setup."
else
    log_info "Running KernelSU setup..."
    curl -LSs "${KSU_SETUP_URL}" | bash -
fi

[ -d "${KERNEL_ROOT}/drivers/kernelsu" ] || \
    die "KernelSU setup failed — drivers/kernelsu not found"

# ─────────────────────────────────────────────
# Step 3: Apply SUSFS base patch
# ─────────────────────────────────────────────
log_step "Step 3: SUSFS base patch (susfs_patch_to_4.19.patch)"

SUSFS_PATCH="${NGKI_DIR}/Patches/Patch/susfs_patch_to_4.19.patch"

log_info "Applying SUSFS base patch..."
patch -p1 --forward < "${SUSFS_PATCH}" || true

# Collect .rej files
mapfile -t REJ_FILES < <(find "${KERNEL_ROOT}" -maxdepth 4 -name "*.rej" -type f 2>/dev/null)

if [ ${#REJ_FILES[@]} -gt 0 ]; then
    log_warn "SUSFS patch produced ${#REJ_FILES[@]} reject file(s):"
    for rej in "${REJ_FILES[@]}"; do
        echo "  - ${rej#${KERNEL_ROOT}/}"
    done

    # ─────────────────────────────────────────
    # Step 3.1: Attempt to fix rejects using fix patches
    # ─────────────────────────────────────────
    log_step "Step 3.1: Applying fix patches for SUSFS rejects"

    FIX_DIR="${PATCHES_DIR}/oneplus/susfs"
    UNFIXED_REJECTS=()

    for rej in "${REJ_FILES[@]}"; do
        # Derive the source file from the .rej path
        src_file="${rej%.rej}"
        src_rel="${src_file#${KERNEL_ROOT}/}"

        # Find a matching fix patch
        # Convention: fix_<basename_without_ext>.patch or fix_<dirname_basename>.patch
        base_name="$(basename "${src_file}" .c)"
        dir_name="$(basename "$(dirname "${src_file}")")"

        fix_patch=""
        # Try: fix_<basename>.patch
        if [ -f "${FIX_DIR}/fix_${base_name}.patch" ]; then
            fix_patch="${FIX_DIR}/fix_${base_name}.patch"
        # Try: fix_<dir>_<basename>.patch (e.g., fix_proc_task_mmu.patch)
        elif [ -f "${FIX_DIR}/fix_${dir_name}_${base_name}.patch" ]; then
            fix_patch="${FIX_DIR}/fix_${dir_name}_${base_name}.patch"
        fi

        if [ -n "${fix_patch}" ]; then
            fix_name="$(basename "${fix_patch}")"
            log_info "Testing fix patch: ${fix_name} for ${src_rel}"

            # Dry-run the fix patch to verify it applies
            if patch -p1 --dry-run --forward < "${fix_patch}" > /dev/null 2>&1; then
                # Verify the fix patch targets the same file that has rejects
                fix_targets=$(grep "^diff --git\|^---" "${fix_patch}" | grep -oP 'b/\K.*' | head -1)
                if [ "${fix_targets}" = "${src_rel}" ]; then
                    log_info "Fix patch ${fix_name} applies cleanly — applying"
                    patch -p1 --forward < "${fix_patch}"
                    rm -f "${rej}"
                    # Clean up .orig files from the base patch
                    rm -f "${src_file}.orig"
                    log_info "Fixed: ${src_rel}"
                else
                    log_info "Fix patch ${fix_name} applies cleanly — applying (targets: ${fix_targets})"
                    patch -p1 --forward < "${fix_patch}"
                    rm -f "${rej}"
                    rm -f "${src_file}.orig"
                    log_info "Fixed: ${src_rel}"
                fi
            else
                log_error "Fix patch ${fix_name} does NOT apply cleanly"
                UNFIXED_REJECTS+=("${rej}")
            fi
        else
            log_warn "No fix patch found for: ${src_rel}"
            UNFIXED_REJECTS+=("${rej}")
        fi
    done

    if [ ${#UNFIXED_REJECTS[@]} -gt 0 ]; then
        log_error "The following rejects could not be resolved:"
        for rej in "${UNFIXED_REJECTS[@]}"; do
            echo "  - ${rej#${KERNEL_ROOT}/}"
        done
        die "Manual intervention required for ${#UNFIXED_REJECTS[@]} reject(s)"
    else
        log_info "All SUSFS rejects resolved successfully."
    fi
else
    log_info "SUSFS base patch applied cleanly — no rejects."
fi

# Clean up .orig files from the base patch
find "${KERNEL_ROOT}" -maxdepth 4 -name "*.orig" -type f -delete 2>/dev/null || true

# ─────────────────────────────────────────────
# Step 4: SUSFS inline hook patches
# ─────────────────────────────────────────────
log_step "Step 4: SUSFS inline hook patches"

chmod +x "${NGKI_DIR}/Patches/susfs_inline_hook_patches.sh"
"${NGKI_DIR}/Patches/susfs_inline_hook_patches.sh"

# ─────────────────────────────────────────────
# Step 5: Backport patches (KernelSU compat)
# ─────────────────────────────────────────────
log_step "Step 5: Backport patches"

chmod +x "${NGKI_DIR}/Patches/backport_patches.sh"
"${NGKI_DIR}/Patches/backport_patches.sh"

# ─────────────────────────────────────────────
# Step 6: Apply custom patches (ntsync, bbr3, etc.)
# ─────────────────────────────────────────────
log_step "Step 6: Custom patches"

apply_patch() {
    local patch_file="$1"
    local patch_name
    patch_name="$(basename "${patch_file}")"

    if patch -p1 --dry-run --forward < "${patch_file}" > /dev/null 2>&1; then
        log_info "Applying: ${patch_name}"
        patch -p1 --forward < "${patch_file}"
    else
        # Check if already applied (reversed dry-run succeeds)
        if patch -p1 --dry-run --reverse < "${patch_file}" > /dev/null 2>&1; then
            log_warn "Already applied, skipping: ${patch_name}"
        else
            log_error "FAILED to apply: ${patch_name}"
            return 1
        fi
    fi
    return 0
}

PATCH_FAILURES=0

# 6a: Common patches — ntsync
if [ -f "${PATCHES_DIR}/common/ntsync_backport.patch" ]; then
    apply_patch "${PATCHES_DIR}/common/ntsync_backport.patch" || ((PATCH_FAILURES++))
fi

# 6b: Common patches — bbr3 (applied in order)
if [ -d "${PATCHES_DIR}/common/bbr3" ]; then
    log_info "Applying BBRv3 patch series..."
    for bbr_patch in "${PATCHES_DIR}/common/bbr3/"*.patch; do
        [ -f "${bbr_patch}" ] || continue
        apply_patch "${bbr_patch}" || ((PATCH_FAILURES++))
    done
fi

# 6c: Any other common patches (excluding bbr3 dir and ntsync which are handled above)
for patch_file in "${PATCHES_DIR}/common/"*.patch; do
    [ -f "${patch_file}" ] || continue
    patch_name="$(basename "${patch_file}")"
    [ "${patch_name}" = "ntsync_backport.patch" ] && continue
    apply_patch "${patch_file}" || ((PATCH_FAILURES++))
done

# ─────────────────────────────────────────────
# Step 7: Cleanup
# ─────────────────────────────────────────────
log_step "Step 7: Cleanup"

find "${KERNEL_ROOT}" -maxdepth 5 -name "*.orig" -type f -delete 2>/dev/null || true
find "${KERNEL_ROOT}" -maxdepth 5 -name "*.rej" -type f -delete 2>/dev/null || true
log_info "Removed leftover .orig and .rej files."

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────
log_step "Summary"

echo ""
log_info "KernelSU:     integrated"
log_info "SUSFS:        patched + inline hooks + backports"
log_info "ntsync:       $([ -f drivers/misc/ntsync.c ] && echo 'applied' || echo 'not found')"
log_info "BBRv3:        $([ -f net/ipv4/tcp_plb.c ] && echo 'applied' || echo 'not found')"

if [ "${PATCH_FAILURES}" -gt 0 ]; then
    echo ""
    log_error "${PATCH_FAILURES} custom patch(es) failed to apply."
    exit 1
fi

echo ""
log_info "All patches applied successfully."
log_info "Enable CONFIG_KSU_SUSFS=y, CONFIG_NTSYNC=y, CONFIG_TCP_CONG_BBR=y in your defconfig."
