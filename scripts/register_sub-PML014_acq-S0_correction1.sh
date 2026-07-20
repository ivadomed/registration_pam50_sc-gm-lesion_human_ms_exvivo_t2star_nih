#!/usr/bin/env bash
# Register sub-PML014 acq-S0 (cervical, C1-C2) to PAM50 — correction 1
#
# Segmentation source : labels_ensemble (val 1|3=WM, 2|4=GM, >0=SC)
# Spinal anchors      : C1 (superior) + C2 (inferior), manually confirmed
# Registration space  : PAM50 0.5mm (no -ref subject)
# Template seg used   : PAM50_wm (-s-template-id 4)
# Z-flip              : affine-only correction (chunk mounted upside-down)
#
# Launch: set_slot 2-3 bash scripts/register_sub-PML014_acq-S0_correction1.sh

set -euo pipefail

SCT_BIN="/tmp/sct_src/bin"
SCT_PY="/tmp/sct_src/python/envs/venv_sct/bin/python"
export PATH="${SCT_BIN}:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="/home/ge.polymtl.ca/pahoa/nih_project"
SUBJ="sub-PML014"
ACQ="S0"

ANAT="${PROJECT}/ms-exvivo-nih/${SUBJ}/anat/${SUBJ}_acq-${ACQ}_part-mag_T2star.nii.gz"
SEG="${PROJECT}/outputs/final_predictions/labels_ensemble/${SUBJ}/anat/S0_68.4cm_T2s_75i_TR45TE9_cor_18avg_Redo_3200_seg.nii.gz"
OUT="${SCRIPT_DIR}/results/correction_1/${SUBJ}_acq-${ACQ}"

mkdir -p "${OUT}"
cd "${OUT}"

echo "=== Step 1: Extract SC / WM / GM segmentations ==="
cp "${ANAT}" _img_orig.nii.gz
cp "${SEG}"  _seg_orig.nii.gz
"${SCT_PY}" "${SCRIPT_DIR}/extract_segs.py" _seg_orig.nii.gz _sc_orig.nii.gz _wm_orig.nii.gz _gm_orig.nii.gz

echo ""
echo "=== Step 2: Z-flip affine (LPS → LPI, voxels unchanged) ==="
for f in img sc wm gm; do
    "${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _${f}_orig.nii.gz ${f}_fixed.nii.gz
done
rm -f _img_orig.nii.gz _seg_orig.nii.gz _sc_orig.nii.gz _wm_orig.nii.gz _gm_orig.nii.gz

echo ""
echo "=== Step 3: Keep largest WM connected component ==="
"${SCT_PY}" "${SCRIPT_DIR}/cleanup_largest_component.py" wm_fixed.nii.gz wm_fixed.nii.gz

echo ""
echo "=== Step 4: Build spinal level landmarks (C1 superior, C2 inferior) ==="
"${SCT_PY}" "${SCRIPT_DIR}/build_landmarks_cervical.py" sc_fixed.nii.gz _landmarks_C1_C2.nii.gz

echo ""
echo "=== Step 5: Register to PAM50 (PAM50 0.5mm space) ==="
# -s-template-id 4 : PAM50_wm has full cervical content.
# step=2 bsplinesyn: iter=20, smooth=0.5 for tight convergence at chunk borders.
sct_register_to_template \
    -i       img_fixed.nii.gz \
    -s       wm_fixed.nii.gz \
    -lspinal _landmarks_C1_C2.nii.gz \
    -c       t2s \
    -s-template-id 4 \
    -param   step=0,type=label,dof=Tx_Ty_Tz_Sz:step=1,type=seg,algo=centermassrot,smooth=1,slicewise=1:step=2,type=seg,algo=bsplinesyn,iter=20,smooth=0.5,gradStep=0.5 \
    -qc      qc \
    -qc-subject "${SUBJ}_${ACQ}"
rm -f _landmarks_C1_C2.nii.gz

echo ""
echo "=== Step 6: Warp PAM50 atlas to subject space ==="
rm -rf label/
sct_warp_template \
    -d  img_fixed.nii.gz \
    -w  warp_template2anat.nii.gz \
    -a  1 \
    -ofolder label

echo ""
echo "=== Done: ${OUT} ==="
