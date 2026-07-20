#!/bin/bash
# PAM50 WM registration for sub-NDRI240907329299 acq-S1 — correction iteration 1
#
# Changes vs wm_v1:
#   - Spinal levels: S2 (label=26, superior) + S3 (label=27, inferior)
#     read from the existing vertebrae_fixed prediction labels
#   - WM: largest connected component only (removes spurious fragments)
#   - Registration in PAM50 space (no -ref subject) — optimises at 0.5mm
#     for speed, then warp applied back to native 0.075mm
#   - Step 2: iter=20, smooth=0.5 (more iterations, less over-smoothing at borders)
#
# Launch with:  set_slot 2-3 bash prepare_and_register_wm2_sub-NDRI240907329299_S1.sh

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
WS="${SCRIPT_DIR}/wm_registration_output_correction_1/${SUBJ}_acq-${ACQ}"

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
echo "=== Step 2: Keep largest WM connected component ==="
"${SCT_PY}" - <<'PYEOF'
import nibabel as nib, numpy as np
from scipy.ndimage import label as cc_label
wm = nib.load("wm_fixed.nii.gz")
d = np.asarray(wm.dataobj).astype(bool)
labeled, n = cc_label(d)
if n > 1:
    sizes = np.bincount(labeled.ravel())
    sizes[0] = 0
    largest = np.argmax(sizes)
    d = (labeled == largest)
    print(f"  Kept largest CC ({sizes[largest]:,} vox), removed {n-1} smaller component(s)")
else:
    print(f"  Single component ({d.sum():,} vox), no cleanup needed")
nib.save(nib.Nifti1Image(d.astype(np.uint8), wm.affine, wm.header), "wm_fixed.nii.gz")
PYEOF

echo ""
echo "=== Step 3: Build S2+S3 landmark file ==="
# S2=label 26 (superior after z-flip), S3=label 27 (inferior).
# PAM50: S2 z_vox=87-100, S3 z_vox=72-86. Span=28 voxels × 0.5mm = 14mm ≈ subject 13.9mm.
"${SCT_PY}" - <<'PYEOF'
import nibabel as nib, numpy as np
img = nib.load("vertebrae_fixed.nii.gz")
data = np.asarray(img.dataobj).copy()
out = np.zeros_like(data)
NZ = data.shape[2]
MARGIN = 40  # keep at least 3mm from edge after 1mm resampling
for v, name in [(26, "S2"), (27, "S3")]:
    zs = np.where(data == v)[2]
    if len(zs) == 0:
        print(f"  WARNING: {name} (val={v}) not found in vertebrae labels!")
        continue
    z = int(zs.mean())
    z = int(np.clip(z, MARGIN, NZ - 1 - MARGIN))
    xs, ys = np.where(data[:,:,z] == v) if (data[:,:,z] == v).any() else np.where(data[:,:,zs[0]] == v)
    out[int(xs.mean()), int(ys.mean()), z] = v
    print(f"  {name} (label={v}) at z_vox={z}")
nib.save(nib.Nifti1Image(out, img.affine, img.header), "_spinal_S2_S3.nii.gz")
PYEOF

echo ""
echo "=== Step 4: Register to PAM50 (PAM50 space, WM-driven) ==="
# No -ref subject: registration runs at PAM50 0.5mm resolution (faster).
# -s-template-id 4: compare against PAM50_wm.
# Note: PAM50_wm is absent at S4-S5 but present at S2-S3 used here.
# Step 2: iter=20, smooth=0.5 for better convergence at chunk borders.
sct_register_to_template \
    -i       img_fixed.nii.gz \
    -s       wm_fixed.nii.gz \
    -lspinal _spinal_S2_S3.nii.gz \
    -c       t2 \
    -s-template-id 4 \
    -param   step=0,type=label,dof=Tx_Ty_Tz_Sz:step=1,type=seg,algo=centermassrot,smooth=1,slicewise=1:step=2,type=seg,algo=bsplinesyn,iter=20,smooth=0.5,gradStep=0.5 \
    -qc      qc \
    -qc-subject "${SUBJ}_${ACQ}"
rm -f _spinal_S2_S3.nii.gz

echo ""
echo "=== Step 5: Warp full PAM50 atlas to native subject space ==="
rm -rf label/
sct_warp_template \
    -d  img_fixed.nii.gz \
    -w  warp_template2anat.nii.gz \
    -a  1 \
    -ofolder label

echo ""
echo "=== Step 6: Warp subject T2* to PAM50 space at native resolution ==="
"${SCT_PY}" - <<'PYEOF'
import nibabel as nib, numpy as np
pam50 = nib.load("/tmp/sct_src/data/PAM50/template/PAM50_t2.nii.gz")
d = pam50.get_fdata(dtype=np.float32)
# Sacral S2-S3 crop: z=72-100, with generous padding
x0,x1, y0,y1, z0,z1 = 43, 98, 44, 96, 50, 120
cropped = d[x0:x1, y0:y1, z0:z1]
aff = pam50.affine.copy()
aff[:3, 3] = aff[:3, 3] + aff[:3, :3] @ np.array([x0, y0, z0])
nib.save(nib.Nifti1Image(cropped, aff, pam50.header), "_pam50_sacral_crop.nii.gz")
print(f"  PAM50 t2 sacral crop: {cropped.shape}")
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
echo "Overlay: img_fixed.nii.gz + label/atlas/PAM50_atlas_*.nii.gz"
echo "QC:      qc/index.html"
