#!/bin/bash
# integrate_ksu_susfs.sh
#
# Automated integration of KernelSU + SUSFS + custom patches
# for the OnePlus SM8250 4.19 kernel.
#
# Features:
#   - Idempotent: safe to run multiple times on the same tree
#   - Feature-selectable: toggle features via flags or environment
#
# Usage:
#   ./integrate_ksu_susfs.sh [OPTIONS]
#
# Options:
#   --all             Enable all features (default)
#   --no-kernelsu     Disable KernelSU
#   --no-susfs        Disable SUSFS
#   --no-nomount      Disable NoMount
#   --no-droidspaces  Disable Droidspaces
#   --no-bbg          Disable Baseband Guard
#   --no-vpnhide      Disable VPNHide
#   --no-ntsync       Disable ntsync
#   --no-bbr3         Disable BBRv3
#   -h, --help        Show this help

set -euo pipefail

KERNEL_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
NGKI_REPO="https://github.com/cyberc3dr/nGKI_Kernel_Build"
NGKI_DIR="${KERNEL_ROOT}/nGKI_Kernel_Build"
KSU_SETUP_URL="https://raw.githubusercontent.com/ReSukiSU/ReSukiSU/main/kernel/setup.sh"
PATCHES_DIR="${KERNEL_ROOT}/android_kernel_patches_and_scripts/4.19/patches"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[+]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
log_error() { echo -e "${RED}[-]${NC} $*"; }
log_step()  { echo -e "\n${GREEN}==== $* ====${NC}"; }
log_skip()  { echo -e "${CYAN}[~]${NC} $* (disabled)"; }

die() { log_error "$*"; exit 1; }

# ─────────────────────────────────────────────
# Feature flags (all enabled by default)
# ─────────────────────────────────────────────
FEAT_KERNELSU=1
FEAT_SUSFS=1
FEAT_NOMOUNT=1
FEAT_DROIDSPACES=1
FEAT_BBG=1
FEAT_VPNHIDE=1
FEAT_NTSYNC=1
FEAT_BBR3=1

show_help() {
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# //'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --all)            ;; # all already enabled
        --no-kernelsu)    FEAT_KERNELSU=0 ;;
        --no-susfs)       FEAT_SUSFS=0 ;;
        --no-nomount)     FEAT_NOMOUNT=0 ;;
        --no-droidspaces) FEAT_DROIDSPACES=0 ;;
        --no-bbg)         FEAT_BBG=0 ;;
        --no-vpnhide)     FEAT_VPNHIDE=0 ;;
        --no-ntsync)      FEAT_NTSYNC=0 ;;
        --no-bbr3)        FEAT_BBR3=0 ;;
        -h|--help)        show_help ;;
        *)                die "Unknown option: $1" ;;
    esac
    shift
done

cd "${KERNEL_ROOT}"

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

# Idempotent patch application.
# Returns 0 on success (applied or already applied), 1 on failure.
apply_patch() {
    local patch_file="$1"
    local patch_name
    patch_name="$(basename "${patch_file}")"

    if patch -p1 --dry-run --forward < "${patch_file}" > /dev/null 2>&1; then
        log_info "Applying: ${patch_name}"
        patch -p1 --forward < "${patch_file}"
    elif patch -p1 --dry-run --reverse < "${patch_file}" > /dev/null 2>&1; then
        log_warn "Already applied, skipping: ${patch_name}"
    else
        log_error "FAILED to apply: ${patch_name}"
        return 1
    fi
    return 0
}

# ─────────────────────────────────────────────
# Step 1: Clone nGKI_Kernel_Build if needed
# ─────────────────────────────────────────────
log_step "Step 1: nGKI_Kernel_Build repository"

if [ -d "${NGKI_DIR}/.git" ]; then
    log_info "nGKI_Kernel_Build already cloned, pulling latest..."
    git -C "${NGKI_DIR}" pull --ff-only 2>/dev/null || log_warn "Pull failed, using existing state"
else
    log_info "Cloning nGKI_Kernel_Build..."
    git clone "${NGKI_REPO}" "${NGKI_DIR}"
fi

# ─────────────────────────────────────────────
# Step 2: KernelSU (ReSukiSU)
# ─────────────────────────────────────────────
if [ "${FEAT_KERNELSU}" -eq 1 ]; then
    log_step "Step 2: KernelSU (ReSukiSU)"

    if [ -d "${KERNEL_ROOT}/KernelSU" ] && [ -L "${KERNEL_ROOT}/drivers/kernelsu" ]; then
        log_info "KernelSU already present, skipping setup."
    else
        log_info "Running KernelSU setup..."
        curl -LSs "${KSU_SETUP_URL}" | bash -
    fi

    [ -d "${KERNEL_ROOT}/drivers/kernelsu" ] || \
        die "KernelSU setup failed — drivers/kernelsu not found"
else
    log_step "Step 2: KernelSU"
    log_skip "KernelSU"
fi

# ─────────────────────────────────────────────
# Step 2.1: NoMount
# ─────────────────────────────────────────────
if [ "${FEAT_NOMOUNT}" -eq 1 ]; then
    log_step "Step 2.1: NoMount"

    if [ -d "${KERNEL_ROOT}/NoMount" ] && [ -d "${KERNEL_ROOT}/fs/nomount" ]; then
        log_info "NoMount already present, skipping setup."
    else
        log_info "Running NoMount setup..."
        curl -LSs "https://raw.githubusercontent.com/maxsteeel/nomount/refs/heads/dev/kernel/setup.sh" | bash -
    fi

    [ -d "${KERNEL_ROOT}/fs/nomount" ] || \
        die "NoMount setup failed — fs/nomount not found"
else
    log_step "Step 2.1: NoMount"
    log_skip "NoMount"
fi

# ─────────────────────────────────────────────
# Step 2.2: Droidspaces
# ─────────────────────────────────────────────
if [ "${FEAT_DROIDSPACES}" -eq 1 ]; then
    log_step "Step 2.2: Droidspaces"

    DROID_DIR="${NGKI_DIR}/Patches/Droidspaces"

    if [ -f "arch/arm64/configs/vendor/droidspaces.config" ]; then
        log_info "droidspaces.config already present."
    else
        cp "${PATCHES_DIR}/common/droidspaces.config" "arch/arm64/configs/vendor/"
        log_info "Copied droidspaces.config"
    fi

    if [ -f "net/netfilter/xt_qtaguid.c" ]; then
        if ! grep -q "UPSTREAM FIX: avoid kernel panic" "net/netfilter/xt_qtaguid.c" 2>/dev/null; then
            log_info "Patching xt_qtaguid.c for Droidspaces..."
            spatch --sp-file "${DROID_DIR}/fix_kernel_panic_in_xt_qtaguid.cocci" --in-place net/netfilter/xt_qtaguid.c
        else
            log_info "xt_qtaguid.c already patched."
        fi
    fi

    if [ -f "kernel/cgroup/cgroup.c" ] && ! grep -q "kernfs_create_link" "kernel/cgroup/cgroup.c"; then
        log_info "Patching kernel/cgroup/cgroup.c for Droidspaces..."
        spatch --sp-file "${DROID_DIR}/fix_restore_cgroup_file_prefix_handling.cocci" --in-place kernel/cgroup/cgroup.c
    elif [ -f "kernel/cgroup.c" ] && ! grep -q "kernfs_create_link" "kernel/cgroup.c"; then
        log_info "Patching kernel/cgroup.c for Droidspaces..."
        spatch --sp-file "${DROID_DIR}/fix_restore_cgroup_file_prefix_handling.cocci" --in-place kernel/cgroup.c
    else
        log_info "cgroup.c already patched or not applicable."
    fi
else
    log_step "Step 2.2: Droidspaces"
    log_skip "Droidspaces"
fi

# ─────────────────────────────────────────────
# Step 2.3: Baseband Guard
# ─────────────────────────────────────────────
if [ "${FEAT_BBG}" -eq 1 ]; then
    log_step "Step 2.3: Baseband Guard"

    if [ -d "${KERNEL_ROOT}/security/baseband-guard" ]; then
        log_info "Baseband Guard already present, skipping setup."
    else
        log_info "Running Baseband Guard setup..."
        curl -LSs "https://github.com/vc-teahouse/Baseband-guard/raw/main/setup.sh" | bash -
    fi

    [ -d "${KERNEL_ROOT}/security/baseband-guard" ] || \
        die "Baseband Guard setup failed — security/baseband-guard not found"
else
    log_step "Step 2.3: Baseband Guard"
    log_skip "Baseband Guard"
fi

# ─────────────────────────────────────────────
# Step 2.4: VPNHide
# ─────────────────────────────────────────────
if [ "${FEAT_VPNHIDE}" -eq 1 ]; then
    log_step "Step 2.4: VPNHide"

    if [ -d "${KERNEL_ROOT}/security/vpnhide" ]; then
        log_info "VPNHide already present, skipping setup."
    else
        log_info "Running VPNHide setup..."
        rm -rf /tmp/vpnhide
        git clone https://github.com/soranerai/vpnhide_next_backend /tmp/vpnhide
        chmod +x /tmp/vpnhide/kpatch/scripts/apply.sh
        /tmp/vpnhide/kpatch/scripts/apply.sh . upstream-4.19
    fi

    [ -d "${KERNEL_ROOT}/security/vpnhide" ] || \
        die "VPNHide setup failed — security/vpnhide not found"
else
    log_step "Step 2.4: VPNHide"
    log_skip "VPNHide"
fi

# ─────────────────────────────────────────────
# Step 3: SUSFS
# ─────────────────────────────────────────────
if [ "${FEAT_SUSFS}" -eq 1 ]; then
    log_step "Step 3: SUSFS base patch"

    [ -f "${NGKI_DIR}/Patches/Patch/susfs_patch_to_4.19.patch" ] || \
        die "susfs_patch_to_4.19.patch not found"

    SUSFS_PATCH="${NGKI_DIR}/Patches/Patch/susfs_patch_to_4.19.patch"

    # Check if SUSFS is already applied (key marker file)
    if [ -f "${KERNEL_ROOT}/fs/susfs.c" ]; then
        log_info "SUSFS appears already applied (fs/susfs.c exists), skipping base patch."
    else
        log_info "Applying SUSFS base patch..."
        patch -p1 --forward < "${SUSFS_PATCH}" || true

        # Collect .rej files
        mapfile -t REJ_FILES < <(find "${KERNEL_ROOT}" -maxdepth 4 -name "*.rej" -type f 2>/dev/null)

        if [ ${#REJ_FILES[@]} -gt 0 ]; then
            log_warn "SUSFS patch produced ${#REJ_FILES[@]} reject file(s):"
            for rej in "${REJ_FILES[@]}"; do
                echo "  - ${rej#${KERNEL_ROOT}/}"
            done

            log_step "Step 3.1: Applying fix patches for SUSFS rejects"

            FIX_DIR="${PATCHES_DIR}/oneplus/susfs"
            UNFIXED_REJECTS=()

            for rej in "${REJ_FILES[@]}"; do
                src_file="${rej%.rej}"
                src_rel="${src_file#${KERNEL_ROOT}/}"
                base_name="$(basename "${src_file}" .c)"
                dir_name="$(basename "$(dirname "${src_file}")")"

                fix_patch=""
                if [ -f "${FIX_DIR}/fix_${base_name}.patch" ]; then
                    fix_patch="${FIX_DIR}/fix_${base_name}.patch"
                elif [ -f "${FIX_DIR}/fix_${dir_name}_${base_name}.patch" ]; then
                    fix_patch="${FIX_DIR}/fix_${dir_name}_${base_name}.patch"
                fi

                if [ -n "${fix_patch}" ]; then
                    fix_name="$(basename "${fix_patch}")"
                    log_info "Testing fix patch: ${fix_name} for ${src_rel}"

                    if patch -p1 --dry-run --forward < "${fix_patch}" > /dev/null 2>&1; then
                        log_info "Fix patch ${fix_name} applies cleanly — applying"
                        patch -p1 --forward < "${fix_patch}"
                        rm -f "${rej}" "${src_file}.orig"
                        log_info "Fixed: ${src_rel}"
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

        find "${KERNEL_ROOT}" -maxdepth 4 -name "*.orig" -type f -delete 2>/dev/null || true
    fi

    # Step 4: SUSFS inline hook patches (idempotent — the scripts check internally)
    log_step "Step 4: SUSFS inline hook patches"
    chmod +x "${NGKI_DIR}/Patches/susfs_inline_hook_patches.sh"
    "${NGKI_DIR}/Patches/susfs_inline_hook_patches.sh"

    # Fixup: susfs_inline_hook_patches.sh expects "unsigned int lookup_flags = 0;" in vfs_statx,
    # but 4.19.325 has "unsigned int lookup_flags = LOOKUP_FOLLOW | LOOKUP_AUTOMOUNT;".
    # Ensure struct filename *fname is declared in vfs_statx() under CONFIG_KSU_SUSFS.
    if grep -q "ksu_handle_stat" fs/stat.c && ! grep -q "struct filename \*fname" fs/stat.c; then
        log_info "Fixing missing fname declaration in fs/stat.c..."
        sed -i '/unsigned int lookup_flags = LOOKUP_FOLLOW | LOOKUP_AUTOMOUNT;/a\#ifdef CONFIG_KSU_SUSFS\n\tstruct filename *fname = NULL;\n#endif' fs/stat.c
    fi

    # Step 5: Backport patches (idempotent — the scripts check internally)
    log_step "Step 5: Backport patches"
    chmod +x "${NGKI_DIR}/Patches/backport_patches.sh"
    "${NGKI_DIR}/Patches/backport_patches.sh"
else
    log_step "Step 3: SUSFS"
    log_skip "SUSFS (also skipping inline hooks and backport patches)"
fi

# ─────────────────────────────────────────────
# Step 6: Custom patches (ntsync, bbr3)
# ─────────────────────────────────────────────
log_step "Step 6: Custom patches"

PATCH_FAILURES=0

# 6a: ntsync
if [ "${FEAT_NTSYNC}" -eq 1 ]; then
    if [ -f "${PATCHES_DIR}/common/ntsync_backport.patch" ]; then
        apply_patch "${PATCHES_DIR}/common/ntsync_backport.patch" || ((PATCH_FAILURES++))
    fi
else
    log_skip "ntsync"
fi

# 6b: BBRv3
if [ "${FEAT_BBR3}" -eq 1 ]; then
    if [ -d "${PATCHES_DIR}/common/bbr3" ]; then
        log_info "Applying BBRv3 patch series..."
        for bbr_patch in "${PATCHES_DIR}/common/bbr3/"*.patch; do
            [ -f "${bbr_patch}" ] || continue
            apply_patch "${bbr_patch}" || ((PATCH_FAILURES++))
        done
    fi
else
    log_skip "BBRv3"
fi

# 6c: Any other common patches
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
feat_status() {
    local flag=$1 name=$2 check=$3
    if [ "${flag}" -eq 1 ]; then
        if eval "${check}"; then
            log_info "${name}: applied"
        else
            log_error "${name}: MISSING"
        fi
    else
        log_skip "${name}"
    fi
}

feat_status "${FEAT_KERNELSU}"    "KernelSU      " "[ -d drivers/kernelsu ]"
feat_status "${FEAT_NOMOUNT}"     "NoMount        " "[ -d fs/nomount ]"
feat_status "${FEAT_DROIDSPACES}" "Droidspaces    " "[ -f arch/arm64/configs/vendor/droidspaces.config ]"
feat_status "${FEAT_BBG}"         "Baseband Guard " "[ -d security/baseband-guard ]"
feat_status "${FEAT_VPNHIDE}"    "VPNHide        " "[ -d security/vpnhide ]"
feat_status "${FEAT_SUSFS}"      "SUSFS          " "[ -f fs/susfs.c ]"
feat_status "${FEAT_NTSYNC}"     "ntsync         " "[ -f drivers/misc/ntsync.c ]"
feat_status "${FEAT_BBR3}"       "BBRv3          " "[ -f net/ipv4/tcp_plb.c ]"

if [ "${PATCH_FAILURES}" -gt 0 ]; then
    echo ""
    log_error "${PATCH_FAILURES} custom patch(es) failed to apply."
    exit 1
fi

echo ""
log_info "All patches applied successfully."
