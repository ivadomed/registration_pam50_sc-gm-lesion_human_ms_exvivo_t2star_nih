#!/bin/bash
# PAM50 WM registration for sub-PML014 acq-S0 — correction iteration 1
#
# Changes vs wm_v1:
#   - Spinal levels: C1 (label=1, superior) + C2 (label=2, inferior)
#   - WM: largest connected component only (removes spurious fragments)
#   - Registration in PAM50 space (no -ref subject) — optimises at 0.5mm
#     for speed, then warp applied back to native 0.075mm
#   - Step 2: iter=20, smooth=0.5 (more iterations, less over-smoothing at borders)
#
# Launch with:  set_slot 2-3 bash prepare_and_register_wm3_sub-PML014_S0.sh

set -euo pipefail

SCT_BIN="/tmp/sct_src/bin"
SCT_PY="/tmp/sct_src/python/envs/venv_sct/bin/python"
export PATH="${SCT_BIN}:$PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT="/home/ge.polymtl.ca/pahoa/nih_project"
SUBJ="sub-PML014"
ACQ="S0"
ANAT_FILE="${PROJECT}/ms-exvivo-nih/${SUBJ}/anat/${SUBJ}_acq-${ACQ}_part-mag_T2star.nii.gz"
SEG_FILE="${PROJECT}/outputs/final_predictions/labels_ensemble/${SUBJ}/anat/S0_68.4cm_T2s_75i_TR45TE9_cor_18avg_Redo_3200_seg.nii.gz"
WS="${SCRIPT_DIR}/wm_registration_output_correction_2/${SUBJ}_acq-${ACQ}"

mkdir -p "${WS}"
cd "${WS}"

echo "=== Step 1: Extract segmentations from labels_ensemble ==="
cp "${ANAT_FILE}" _img_orig.nii.gz
cp "${SEG_FILE}"  _seg_orig.nii.gz

"${SCT_PY}" - <<'PYEOF'
import nibabel as nib, numpy as np
seg = nib.load("_seg_orig.nii.gz")
d, aff, hdr = np.asarray(seg.dataobj), seg.affine, seg.header
sc = (d > 0).astype(np.uint8)
wm = np.isin(d, [1, 3]).astype(np.uint8)
gm = np.isin(d, [2, 4]).astype(np.uint8)
nib.save(nib.Nifti1Image(sc, aff, hdr), "_sc_orig.nii.gz")
nib.save(nib.Nifti1Image(wm, aff, hdr), "_wm_orig.nii.gz")
nib.save(nib.Nifti1Image(gm, aff, hdr), "_gm_orig.nii.gz")
print(f"  SC: {sc.sum():,}  WM: {wm.sum():,}  GM: {gm.sum():,}")
PYEOF

echo ""
echo "=== Step 2: Z-flip (LPS → LPI) ==="
"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _img_orig.nii.gz  img_fixed.nii.gz
"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _sc_orig.nii.gz   sc_fixed.nii.gz
"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _wm_orig.nii.gz   wm_fixed.nii.gz
"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _gm_orig.nii.gz   gm_fixed.nii.gz
rm -f _img_orig.nii.gz _seg_orig.nii.gz _sc_orig.nii.gz _wm_orig.nii.gz _gm_orig.nii.gz

echo ""
echo "=== Step 3: Keep largest WM connected component ==="
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
echo "=== Step 4: Build C1+C2 landmark file ==="
# After z-flip, superior end is at high z_vox.
# User-confirmed from visualization: chunk spans C1 (superior) → C2 (inferior).
# PAM50: C1=label 1 (z_vox 970-984), C2=label 2 (z_vox 949-969).
"${SCT_PY}" - <<'PYEOF'
import nibabel as nib, numpy as np
sc = nib.load("sc_fixed.nii.gz")
d  = np.asarray(sc.dataobj) > 0
out = np.zeros(d.shape, dtype=np.uint8)
for label, z_range, name in [(1, range(690, 660, -1), "C1"), (2, range(40, 70), "C2")]:
    for z in z_range:
        sl = d[:,:,z]
        if sl.sum() == 0: continue
        xs, ys = np.where(sl)
        out[int(xs.mean()), int(ys.mean()), z] = label
        print(f"  {name} anchor (label={label}) at z_vox={z}")
        break
nib.save(nib.Nifti1Image(out, sc.affine, sc.header), "_spinal_C1_C2.nii.gz")
PYEOF

echo ""
echo "=== Step 5: Register to PAM50 (PAM50 space, WM-driven) ==="
# No -ref subject: registration runs at PAM50 0.5mm resolution (faster),
# warp is applied to native 0.075mm data in subsequent steps.
# -s-template-id 4: compare against PAM50_wm instead of PAM50_cord.
# Step 2: iter=20, smooth=0.5 for better convergence at chunk borders.
sct_register_to_template \
    -i       img_fixed.nii.gz \
    -s       wm_fixed.nii.gz \
    -lspinal _spinal_C1_C2.nii.gz \
    -c       t2s \
    -s-template-id 4 \
    -ref     subject \
    -param   step=0,type=label,dof=Tx_Ty_Tz_Sz:step=1,type=seg,algo=centermassrot,smooth=1,slicewise=1:step=2,type=seg,algo=bsplinesyn,iter=20,smooth=0.5,gradStep=0.5 \
    -qc      qc \
    -qc-subject "${SUBJ}_${ACQ}"
rm -f _spinal_C1_C2.nii.gz

echo ""
echo "=== Step 6: Warp full PAM50 atlas to native subject space ==="
rm -rf label/
sct_warp_template \
    -d  img_fixed.nii.gz \
    -w  warp_template2anat.nii.gz \
    -a  1 \
    -ofolder label

echo ""
echo "=== Step 7: Warp subject T2* to PAM50 space at native resolution ==="
"${SCT_PY}" - <<'PYEOF'
import nibabel as nib, numpy as np
pam50 = nib.load("/tmp/sct_src/data/PAM50/template/PAM50_t2s.nii.gz")
d = pam50.get_fdata(dtype=np.float32)
# Cervical crop: C1-C2 region + generous padding
# C1: z=970-984, C2: z=949-969 → crop z=880:994 (covers C7-C1 + margin)
x0,x1, y0,y1, z0,z1 = 50, 90, 50, 90, 880, 994
cropped = d[x0:x1, y0:y1, z0:z1]
aff = pam50.affine.copy()
aff[:3, 3] = aff[:3, 3] + aff[:3, :3] @ np.array([x0, y0, z0])
nib.save(nib.Nifti1Image(cropped, aff, pam50.header), "_pam50_cervical_crop.nii.gz")
print(f"  PAM50 t2s cervical crop: {cropped.shape}")
PYEOF
sct_resample -i _pam50_cervical_crop.nii.gz -mm 0.075x0.075x0.075 -o _pam50_cervical_ref.nii.gz
sct_apply_transfo \
    -i img_fixed.nii.gz \
    -d _pam50_cervical_ref.nii.gz \
    -w warp_anat2template.nii.gz \
    -o anat2template_hires.nii.gz \
    -x linear
rm -f _pam50_cervical_crop.nii.gz _pam50_cervical_ref.nii.gz

echo ""
echo "=== Done ==="
echo "Overlay: img_fixed.nii.gz + label/atlas/PAM50_atlas_*.nii.gz"
echo "QC:      qc/index.html"
