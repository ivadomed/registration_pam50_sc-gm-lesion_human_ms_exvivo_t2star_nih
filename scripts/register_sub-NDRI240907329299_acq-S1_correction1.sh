#!/usr/bin/env bash
# Register sub-NDRI240907329299 acq-S1 (sacral, S2-S3) to PAM50 — correction 1
#
# Segmentation source : combined_3d_pred_for_registration (separate SC/WM/GM/vertebrae)
# Spinal anchors      : S2 + S3 from vertebrae prediction (PAM50 labels 26, 27)
# Registration space  : PAM50 0.5mm (no -ref subject)
# Template seg used   : PAM50_wm (-s-template-id 4, present at S2-S3)
# Z-flip              : affine-only correction (chunk mounted upside-down)
#
# Launch: set_slot 2-3 bash scripts/register_sub-NDRI240907329299_acq-S1_correction1.sh

set -euo pipefail

SCT_BIN="/tmp/sct_src/bin"
SCT_PY="/tmp/sct_src/python/envs/venv_sct/bin/python"
export PATH="${SCT_BIN}:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="/home/ge.polymtl.ca/pahoa/nih_project"
SUBJ="sub-NDRI240907329299"
ACQ="S1"
BASE="${SUBJ}_acq-${ACQ}_part-mag_T2star"

DERIV="${PROJECT}/ms-exvivo-nih/derivatives/combined_3d_pred_for_registration/${SUBJ}/anat"
OUT="${SCRIPT_DIR}/results/correction_1/${SUBJ}_acq-${ACQ}"

mkdir -p "${OUT}"
cd "${OUT}"

echo "=== Step 1: Copy inputs and z-flip (LPS → LPI) ==="
cp "${PROJECT}/ms-exvivo-nih/${SUBJ}/anat/${BASE}.nii.gz" _img_orig.nii.gz
cp "${DERIV}/${BASE}_label-SC_seg.nii.gz"                 _sc_orig.nii.gz
cp "${DERIV}/${BASE}_label-WM_seg.nii.gz"                 _wm_orig.nii.gz
cp "${DERIV}/${BASE}_label-GM_seg.nii.gz"                 _gm_orig.nii.gz
cp "${DERIV}/${BASE}_label-vertebrae_seg.nii.gz"           _vertebrae_orig.nii.gz
for f in img sc wm gm vertebrae; do
    "${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _${f}_orig.nii.gz ${f}_fixed.nii.gz
done
rm -f _img_orig.nii.gz _sc_orig.nii.gz _wm_orig.nii.gz _gm_orig.nii.gz _vertebrae_orig.nii.gz

echo ""
echo "=== Step 2: Keep largest WM connected component ==="
"${SCT_PY}" "${SCRIPT_DIR}/cleanup_largest_component.py" wm_fixed.nii.gz wm_fixed.nii.gz

echo ""
echo "=== Step 3: Build spinal level landmarks (S2 superior, S3 inferior) ==="
"${SCT_PY}" "${SCRIPT_DIR}/build_landmarks_sacral.py" vertebrae_fixed.nii.gz _landmarks_S2_S3.nii.gz

echo ""
echo "=== Step 4: Register to PAM50 (PAM50 0.5mm space) ==="
# -c t2 : PAM50_t2s is empty at sacral; PAM50_t2 has full sacral content.
# -s-template-id 4 : PAM50_wm present at S2-S3 (absent at S4-S5).
# step=2 bsplinesyn: iter=20, smooth=0.5 for tight convergence at chunk borders.
sct_register_to_template \
    -i       img_fixed.nii.gz \
    -s       wm_fixed.nii.gz \
    -lspinal _landmarks_S2_S3.nii.gz \
    -c       t2 \
    -s-template-id 4 \
    -param   step=0,type=label,dof=Tx_Ty_Tz_Sz:step=1,type=seg,algo=centermassrot,smooth=1,slicewise=1:step=2,type=seg,algo=bsplinesyn,iter=20,smooth=0.5,gradStep=0.5 \
    -qc      qc \
    -qc-subject "${SUBJ}_${ACQ}"
rm -f _landmarks_S2_S3.nii.gz

echo ""
echo "=== Step 5: Warp PAM50 atlas to subject space ==="
rm -rf label/
sct_warp_template \
    -d  img_fixed.nii.gz \
    -w  warp_template2anat.nii.gz \
    -a  1 \
    -ofolder label

echo ""
echo "=== Done: ${OUT} ==="
