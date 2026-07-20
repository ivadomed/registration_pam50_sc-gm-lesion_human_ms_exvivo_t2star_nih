#!/bin/bash
# PAM50 registration for sub-NDRI240907329299 acq-S1 (sacral chunk, z-inverted).
#
# Goal: bring PAM50 WM tract atlas + GM regions into native 0.075mm subject space
# for parcellation. Spinal level positions (S1-S5) are known from the vertebrae
# prediction (vertebrae_fixed.nii.gz) and are INPUTS to registration, not outputs.
# Registration's job is to find the correct cross-sectional tract layout in native
# subject space (where in the cross-section is CST, dorsal horn, etc.)
#
# Launch with:  set_slot 1 bash prepare_and_register.sh
#
# Cord orientation fix: chunk was mounted upside-down. Affine-only z-flip
# (fix_z_inversion.py) corrects the orientation without touching voxel data.

set -euo pipefail

SCT_BIN="/tmp/sct_src/bin"
SCT_PY="/tmp/sct_src/python/envs/venv_sct/bin/python"
export PATH="${SCT_BIN}:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="/home/ge.polymtl.ca/pahoa/nih_project"
SUBJ="sub-NDRI240907329299"
ACQ="S1"
BASE="${SUBJ}_acq-${ACQ}_part-mag_T2star"
DERIV="${PROJECT}/ms-exvivo-nih/derivatives/combined_3d_pred_for_registration/${SUBJ}/anat"
WS="${SCRIPT_DIR}/sc_registration_output/${SUBJ}_acq-${ACQ}"
PAM50="/tmp/sct_src/data/PAM50/template"

mkdir -p "${WS}"
cd "${WS}"

echo "=== Step 1: Prepare inputs (copy + z-flip) ==="
cp "${PROJECT}/ms-exvivo-nih/${SUBJ}/anat/${BASE}.nii.gz"  _img_orig.nii.gz
cp "${DERIV}/${BASE}_label-SC_seg.nii.gz"                  _sc_orig.nii.gz
cp "${DERIV}/${BASE}_label-WM_seg.nii.gz"                  _wm_orig.nii.gz
cp "${DERIV}/${BASE}_label-GM_seg.nii.gz"                  _gm_orig.nii.gz
cp "${DERIV}/${BASE}_label-vertebrae_seg.nii.gz"            _vertebrae_orig.nii.gz

"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _img_orig.nii.gz        img_fixed.nii.gz
"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _sc_orig.nii.gz         sc_fixed.nii.gz
"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _wm_orig.nii.gz         wm_fixed.nii.gz
"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _gm_orig.nii.gz         gm_fixed.nii.gz
"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _vertebrae_orig.nii.gz  vertebrae_fixed.nii.gz
rm -f _img_orig.nii.gz _sc_orig.nii.gz _wm_orig.nii.gz _gm_orig.nii.gz _vertebrae_orig.nii.gz

echo ""
echo "=== Step 2: Build S1+S5 landmark file ==="
# Two-point initialization: S1 (val=25, z=58) + S5 (val=29, z=244).
# Constrains both z-translation AND z-scale (PAM50 sacral = 24mm, subject = 13.9mm).
# '-ref subject' allows max 2 spinal labels, so we use the two endpoints.
"${SCT_PY}" - <<'PYEOF'
import nibabel as nib, numpy as np
img = nib.load("vertebrae_fixed.nii.gz")
data = np.asarray(img.dataobj).copy()
out = np.zeros_like(data)
out[data == 25] = 25
out[data == 29] = 29
nib.save(nib.Nifti1Image(out, img.affine, img.header), "_spinal_S1_S5.nii.gz")
for v in [25, 29]:
    z = np.where(out == v)[2][0]
    print(f"  S{v-24} (val={v}) at z_vox={z}")
PYEOF

echo ""
echo "=== Step 3: Register to PAM50 (native 0.075mm, seg-driven) ==="
# -lspinal: S1+S5 two-point anchor (translation + z-scale initialization)
# -s sc_fixed.nii.gz: SC cord — only structure present throughout S1-S5 in PAM50
#   (PAM50 WM atlas is absent at S4-S5; SC cord exists all the way down)
# -c t2: PAM50_t2 has sacral content (PAM50_t2s is empty at L1/sacral)
# -ref subject: all outputs land in native 0.075mm subject space
# param: pure segmentation steps — avoids T2* vs T2 contrast mismatch entirely
sct_register_to_template \
    -i       img_fixed.nii.gz \
    -s       sc_fixed.nii.gz \
    -lspinal _spinal_S1_S5.nii.gz \
    -c       t2 \
    -ref     subject \
    -param   step=0,type=label,dof=Tx_Ty_Tz_Sz:step=1,type=seg,algo=centermassrot,smooth=1,slicewise=1:step=2,type=seg,algo=bsplinesyn,iter=10,smooth=1,gradStep=0.5 \
    -qc      qc \
    -qc-subject "${SUBJ}_${ACQ}"
rm -f _spinal_S1_S5.nii.gz

echo ""
echo "=== Step 4: Warp full PAM50 atlas to native subject space ==="
# sct_warp_template applies warp to all template + atlas files in one call.
# Output layout:
#   label/template/  — PAM50_t2, PAM50_wm, PAM50_gm, PAM50_spinal_levels, ...
#   label/atlas/     — PAM50_atlas_00..35 (30 WM tracts + 6 GM regions)
rm -rf label/
sct_warp_template \
    -d  img_fixed.nii.gz \
    -w  warp_template2anat.nii.gz \
    -a  1 \
    -ofolder label

echo ""
echo "=== Step 5: Warp subject T2* to PAM50 space at native resolution ==="
# The PAM50 template is 0.5mm — using it directly as the destination grid would
# downsample the 0.075mm subject data and lose all fine detail. Instead, crop
# PAM50 to the sacral cord region and upsample the grid to 0.075mm so the output
# keeps the full subject resolution in PAM50 coordinate space.
"${SCT_PY}" - <<'PYEOF'
import nibabel as nib, numpy as np
pam50 = nib.load("/tmp/sct_src/data/PAM50/template/PAM50_t2.nii.gz")
d = pam50.get_fdata(dtype=np.float32)
# cord bounding box at sacral level + 20-voxel padding (PAM50 0.5mm space)
x0,x1, y0,y1, z0,z1 = 43,98, 44,96, 30,131
cropped = d[x0:x1, y0:y1, z0:z1]
aff = pam50.affine.copy()
aff[:3, 3] = aff[:3, 3] + aff[:3, :3] @ np.array([x0, y0, z0])
nib.save(nib.Nifti1Image(cropped, aff, pam50.header), "_pam50_sacral_crop.nii.gz")
PYEOF
sct_resample -i _pam50_sacral_crop.nii.gz -mm 0.075x0.075x0.075 -o _pam50_sacral_ref.nii.gz
sct_apply_transfo \
    -i img_fixed.nii.gz \
    -d _pam50_sacral_ref.nii.gz \
    -w warp_anat2template.nii.gz \
    -o anat2template_hires.nii.gz \
    -x linear
rm -f _pam50_sacral_crop.nii.gz _pam50_sacral_ref.nii.gz

echo ""
echo "=== Done ==="
echo ""
echo "Inputs (0.075mm subject space):"
echo "  ${WS}/img_fixed.nii.gz              T2* anatomical"
echo "  ${WS}/wm_fixed.nii.gz               WM segmentation"
echo "  ${WS}/gm_fixed.nii.gz               GM segmentation"
echo "  ${WS}/vertebrae_fixed.nii.gz        Spinal level midpoints (S1-S5)"
echo ""
echo "Registration:"
echo "  ${WS}/warp_template2anat.nii.gz     PAM50 → subject"
echo "  ${WS}/warp_anat2template.nii.gz     subject → PAM50"
echo "  ${WS}/anat2template_hires.nii.gz    T2* in PAM50 space at 0.075mm (sacral crop)"
echo ""
echo "Atlas in subject space:"
echo "  ${WS}/label/template/PAM50_t2.nii.gz"
echo "  ${WS}/label/template/PAM50_wm.nii.gz"
echo "  ${WS}/label/template/PAM50_gm.nii.gz"
echo "  ${WS}/label/template/PAM50_spinal_levels.nii.gz"
echo "  ${WS}/label/atlas/PAM50_atlas_04.nii.gz  (L lateral CST)"
echo "  ${WS}/label/atlas/PAM50_atlas_05.nii.gz  (R lateral CST)"
echo "  ${WS}/label/atlas/PAM50_atlas_22.nii.gz  (L ventral CST)"
echo "  ${WS}/label/atlas/PAM50_atlas_23.nii.gz  (R ventral CST)"
echo "  ${WS}/label/atlas/PAM50_atlas_34.nii.gz  (L dorsal horn)"
echo "  ${WS}/label/atlas/PAM50_atlas_35.nii.gz  (R dorsal horn)"
echo "  ${WS}/label/atlas/PAM50_atlas_30.nii.gz  (L ventral horn)"
echo "  ${WS}/label/atlas/PAM50_atlas_31.nii.gz  (R ventral horn)"
echo "  ... (all 36 files in label/atlas/)"
echo ""
echo "QC report: ${WS}/qc/index.html"
