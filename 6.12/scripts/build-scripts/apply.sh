#!/bin/bash
set -euo pipefail

./00-clean_kernel.sh && ./01_apply_ksu_susfs.sh && ./02_apply_bbg.sh && ./03_apply_optimizations.sh && ./04_apply_ntsync.sh && ./05_apply_net_features.sh && ./06_apply_droidspaces.sh && ./07_apply_misc_features.sh && ./08_inject_fragments.sh && ./09_apply_nethunter.sh
