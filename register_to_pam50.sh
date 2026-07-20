#!/usr/bin/env bash
# Register an ex vivo spinal cord chunk to the PAM50 template.
#
# Usage:
#   set_slot 2-3 bash register_to_pam50.sh <subject> <acq> [correction]
#
# Arguments:
#   subject     BIDS subject ID             e.g. sub-PML014
#   acq         acquisition label           e.g. S0
#   correction  registration variant: 1 or 2 (default: 2)
#               1 = PAM50 0.5mm space (faster)
#               2 = native 0.075mm space, atlas ready to use (recommended)
#
# Examples:
#   set_slot 2-3 bash register_to_pam50.sh sub-PML014 S0
#   set_slot 2-3 bash register_to_pam50.sh sub-PML014 S0 1
#   set_slot 2-3 bash register_to_pam50.sh sub-NDRI240907329299 S1 2

set -euo pipefail

SUBJ="${1:-}"
ACQ="${2:-}"
CORRECTION="${3:-2}"

if [ -z "${SUBJ}" ] || [ -z "${ACQ}" ]; then
    echo "Usage: set_slot 2-3 bash register_to_pam50.sh <subject> <acq> [correction]"
    echo "  subject     e.g. sub-PML014"
    echo "  acq         e.g. S0"
    echo "  correction  1 or 2 (default: 2)"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/scripts/register_${SUBJ}_acq-${ACQ}_correction${CORRECTION}.sh"

if [ ! -f "${SCRIPT}" ]; then
    echo "Error: no script found for ${SUBJ} acq-${ACQ} correction${CORRECTION}"
    echo "Expected: ${SCRIPT}"
    exit 1
fi

echo "PAM50 registration: ${SUBJ} acq-${ACQ} correction${CORRECTION}"
echo ""
bash "${SCRIPT}"
