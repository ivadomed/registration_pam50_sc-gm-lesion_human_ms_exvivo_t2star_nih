#!/bin/bash
# PAM50 registration for sub-PML014 acq-S0 (thoracic chunk, z-inverted).
#
# Goal: bring PAM50 WM tract atlas + GM regions into native 0.075mm subject space
# for parcellation. Vertebral level auto-detected from cord cross-sectional area
# matching against PAM50 profile: whole-chunk mean ~47mm² → T2 (PAM50: 48mm²),
# chunk spans approximately T2–T4.
#
# Chunk is mounted upside-down (same as sacral subject): z-flip needed (LPS → LPI).
# Uses PAM50_t2s template (-c t2s) since data is T2*w and PAM50_t2s has full
# thoracic content.
#
# Launch with:  set_slot 1 bash prepare_and_register_PML014_S0.sh

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
WS="${SCRIPT_DIR}/sc_registration_output/${SUBJ}_acq-${ACQ}"

mkdir -p "${WS}"
cd "${WS}"

echo "=== Step 1: Extract segmentations from labels_ensemble ==="
# val 1=healthy WM, 2=healthy GM, 3=lesion WM, 4=lesion GM
# SC = all non-zero, WM = val 1|3, GM = val 2|4
cp "${ANAT_FILE}" _img_orig.nii.gz
cp "${SEG_FILE}"  _seg_orig.nii.gz

"${SCT_PY}" - <<'PYEOF'
import nibabel as nib, numpy as np

seg = nib.load("_seg_orig.nii.gz")
d   = np.asarray(seg.dataobj)
aff, hdr = seg.affine, seg.header

sc = (d > 0).astype(np.uint8)
wm = np.isin(d, [1, 3]).astype(np.uint8)
gm = np.isin(d, [2, 4]).astype(np.uint8)

nib.save(nib.Nifti1Image(sc, aff, hdr), "_sc_orig.nii.gz")
nib.save(nib.Nifti1Image(wm, aff, hdr), "_wm_orig.nii.gz")
nib.save(nib.Nifti1Image(gm, aff, hdr), "_gm_orig.nii.gz")
print(f"  SC: {sc.sum():,} voxels  WM: {wm.sum():,}  GM: {gm.sum():,}")
PYEOF

echo ""
echo "=== Step 2: Z-flip (cord mounted upside-down, LPS → LPI) ==="
"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _img_orig.nii.gz  img_fixed.nii.gz
"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _sc_orig.nii.gz   sc_fixed.nii.gz
"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _wm_orig.nii.gz   wm_fixed.nii.gz
"${SCT_PY}" "${SCRIPT_DIR}/fix_z_inversion.py" _gm_orig.nii.gz   gm_fixed.nii.gz
rm -f _img_orig.nii.gz _seg_orig.nii.gz _sc_orig.nii.gz _wm_orig.nii.gz _gm_orig.nii.gz

echo ""
echo "=== Step 3: Build T2+T4 landmark file (auto-detected from cord area) ==="
# After z-flip, superior end of cord is at high z_vox (z≈720).
# Cord area matching: whole-chunk mean ≈47mm² → center = T2 (PAM50: 48mm²).
# Two-point anchor at T2 (superior) + T4 (inferior) constrains z-translation + z-scale.
# PAM50 T2-T4 span = 111 voxels × 0.5mm = 55.5mm ≈ our chunk 54.8mm (only 1% mismatch).
"${SCT_PY}" - <<'PYEOF'
import nibabel as nib, numpy as np

sc = nib.load("sc_fixed.nii.gz")
d  = np.asarray(sc.dataobj) > 0
out = np.zeros(d.shape, dtype=np.uint8)

# Superior anchor: T2 = PAM50 spinal level label 9
for z in range(725, 700, -1):
    sl = d[:,:,z]
    if sl.sum() == 0:
        continue
    xs, ys = np.where(sl)
    out[int(xs.mean()), int(ys.mean()), z] = 9
    print(f"  T2 anchor (label=9)  at z_vox={z}")
    break

# Inferior anchor: T4 = PAM50 spinal level label 11
for z in range(5, 30):
    sl = d[:,:,z]
    if sl.sum() == 0:
        continue
    xs, ys = np.where(sl)
    out[int(xs.mean()), int(ys.mean()), z] = 11
    print(f"  T4 anchor (label=11) at z_vox={z}")
    break

nib.save(nib.Nifti1Image(out, sc.affine, sc.header), "_spinal_T2_T4.nii.gz")
PYEOF

echo ""
echo "=== Step 4: Register to PAM50 (native 0.075mm, seg-driven) ==="
# -c t2s: use PAM50_t2s template (T2*-weighted; full thoracic content confirmed)
# -lspinal: T2+T4 two-point anchor for z-translation + z-scale initialization
# -s sc_fixed.nii.gz: SC cord for segmentation-driven registration
# -ref subject: all outputs in native 0.075mm subject space
sct_register_to_template \
    -i       img_fixed.nii.gz \
    -s       sc_fixed.nii.gz \
    -lspinal _spinal_T2_T4.nii.gz \
    -c       t2s \
    -ref     subject \
    -param   step=0,type=label,dof=Tx_Ty_Tz_Sz:step=1,type=seg,algo=centermassrot,smooth=1,slicewise=1:step=2,type=seg,algo=bsplinesyn,iter=10,smooth=1,gradStep=0.5 \
    -qc      qc \
    -qc-subject "${SUBJ}_${ACQ}"
rm -f _spinal_T2_T4.nii.gz

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
# Crop PAM50_t2s to T1-T5 region (covers T2-T4 chunk with margin),
# upsample the grid to 0.075mm to preserve subject resolution in the output.
"${SCT_PY}" - <<'PYEOF'
import nibabel as nib, numpy as np
pam50 = nib.load("/tmp/sct_src/data/PAM50/template/PAM50_t2s.nii.gz")
d = pam50.get_fdata(dtype=np.float32)
# Thoracic cord bounding box (PAM50 0.5mm voxels):
#   x: 50:90 (cord center 70, ±20 voxels = ±10mm)
#   y: 50:90 (cord center 70, ±20 voxels = ±10mm)
#   z: 587:797 (T5 bottom −10 pad to T1 top +10 pad = 105mm coverage)
x0,x1, y0,y1, z0,z1 = 50, 90, 50, 90, 587, 797
cropped = d[x0:x1, y0:y1, z0:z1]
aff = pam50.affine.copy()
aff[:3, 3] = aff[:3, 3] + aff[:3, :3] @ np.array([x0, y0, z0])
nib.save(nib.Nifti1Image(cropped, aff, pam50.header), "_pam50_thoracic_crop.nii.gz")
print(f"  PAM50 t2s thoracic crop: {cropped.shape}, max={cropped.max():.0f}")
PYEOF
sct_resample -i _pam50_thoracic_crop.nii.gz -mm 0.075x0.075x0.075 -o _pam50_thoracic_ref.nii.gz
sct_apply_transfo \
    -i img_fixed.nii.gz \
    -d _pam50_thoracic_ref.nii.gz \
    -w warp_anat2template.nii.gz \
    -o anat2template_hires.nii.gz \
    -x linear
rm -f _pam50_thoracic_crop.nii.gz _pam50_thoracic_ref.nii.gz

echo ""
echo "=== Done ==="
echo ""
echo "Inputs (0.075mm subject space):"
echo "  ${WS}/img_fixed.nii.gz         T2* anatomical (z-corrected)"
echo "  ${WS}/sc_fixed.nii.gz          SC segmentation"
echo "  ${WS}/wm_fixed.nii.gz          WM segmentation"
echo "  ${WS}/gm_fixed.nii.gz          GM segmentation"
echo ""
echo "Registration warps:"
echo "  ${WS}/warp_template2anat.nii.gz   PAM50 → subject"
echo "  ${WS}/warp_anat2template.nii.gz   subject → PAM50"
echo "  ${WS}/anat2template_hires.nii.gz  T2* in PAM50 space at 0.075mm"
echo ""
echo "Atlas in subject space (overlay on img_fixed.nii.gz):"
echo "  ${WS}/label/atlas/PAM50_atlas_04.nii.gz  (L lateral CST)"
echo "  ${WS}/label/atlas/PAM50_atlas_05.nii.gz  (R lateral CST)"
echo "  ${WS}/label/atlas/PAM50_atlas_22.nii.gz  (L ventral CST)"
echo "  ${WS}/label/atlas/PAM50_atlas_23.nii.gz  (R ventral CST)"
echo "  ${WS}/label/atlas/PAM50_atlas_30.nii.gz  (L ventral horn)"
echo "  ${WS}/label/atlas/PAM50_atlas_31.nii.gz  (R ventral horn)"
echo "  ${WS}/label/atlas/PAM50_atlas_34.nii.gz  (L dorsal horn)"
echo "  ${WS}/label/atlas/PAM50_atlas_35.nii.gz  (R dorsal horn)"
echo "  ... (all 36 files in label/atlas/)"
echo ""
echo "QC report: ${WS}/qc/index.html"
