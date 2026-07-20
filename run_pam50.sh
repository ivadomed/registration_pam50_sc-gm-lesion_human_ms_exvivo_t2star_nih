#!/usr/bin/env bash
# Run PAM50 registration for a subject.
#
# Usage:
#   set_slot 1 bash run_pam50.sh sub-PML014 S0       # SC-based (default)
#   set_slot 1 bash run_pam50.sh sub-PML014 S0 wm    # WM-based (labels 1+3)

set -euo pipefail

SUBJ="${1:-}"
ACQ="${2:-}"
MODE="${3:-sc}"   # sc (default) or wm

if [ -z "$SUBJ" ] || [ -z "$ACQ" ]; then
    echo "Usage: set_slot 1 bash run_pam50.sh <subject> <acq> [sc|wm]"
    echo "  e.g. set_slot 1 bash run_pam50.sh sub-PML014 S0"
    echo "  e.g. set_slot 1 bash run_pam50.sh sub-PML014 S0 wm"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$MODE" = "wm" ]; then
    SCRIPT="${SCRIPT_DIR}/prepare_and_register_wm_${SUBJ}_${ACQ}.sh"
elif [ "$MODE" = "wm2" ]; then
    SCRIPT="${SCRIPT_DIR}/prepare_and_register_wm2_${SUBJ}_${ACQ}.sh"
elif [ "$MODE" = "wm3" ]; then
    SCRIPT="${SCRIPT_DIR}/prepare_and_register_wm3_${SUBJ}_${ACQ}.sh"
else
    SCRIPT="${SCRIPT_DIR}/prepare_and_register_${SUBJ}_${ACQ}.sh"
fi

if [ ! -f "$SCRIPT" ]; then
    echo "Error: no registration script found for ${SUBJ} acq-${ACQ} mode=${MODE}"
    echo "Expected: ${SCRIPT}"
    exit 1
fi

echo "PAM50 registration: ${SUBJ} acq-${ACQ} [${MODE}]"
echo ""
bash "$SCRIPT"
