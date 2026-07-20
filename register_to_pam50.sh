#!/usr/bin/env bash
# Register an ex vivo spinal cord chunk to the PAM50 template.
#
# Usage:
#   set_slot 2-3 bash register_to_pam50.sh <subject> <acq> [variant]
#
# Arguments:
#   subject   BIDS subject ID          e.g. sub-PML014
#   acq       acquisition label        e.g. S0
#   variant   pam50_space_registration  — registration solved in PAM50 0.5mm space
#             native_space_registration — registration solved in native 0.075mm space (default)
#             (short forms accepted: pam50 | native)
#
# Examples:
#   set_slot 2-3 bash register_to_pam50.sh sub-PML014 S0
#   set_slot 2-3 bash register_to_pam50.sh sub-PML014 S0 pam50
#   set_slot 2-3 bash register_to_pam50.sh sub-NDRI240907329299 S1 native

set -euo pipefail

SUBJ="${1:-}"
ACQ="${2:-}"
VARIANT="${3:-native}"

if [ -z "${SUBJ}" ] || [ -z "${ACQ}" ]; then
    echo "Usage: set_slot 2-3 bash register_to_pam50.sh <subject> <acq> [variant]"
    echo "  variant: pam50 | native (default: native)"
    exit 1
fi

# Normalize short forms
case "${VARIANT}" in
    pam50|pam50_space)  VARIANT="pam50_space_registration" ;;
    native|native_space) VARIANT="native_space_registration" ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${SCRIPT_DIR}/scripts/register_${SUBJ}_acq-${ACQ}_${VARIANT}.sh"

if [ ! -f "${SCRIPT}" ]; then
    echo "Error: script not found: ${SCRIPT}"
    exit 1
fi

echo "PAM50 registration: ${SUBJ} acq-${ACQ} [${VARIANT}]"
echo ""
bash "${SCRIPT}"
