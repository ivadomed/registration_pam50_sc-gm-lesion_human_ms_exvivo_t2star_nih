"""
Fix z-axis inversion for ex vivo cord chunks mounted upside-down in the scanner.

Strategy: modify ONLY the affine — no voxel data is reordered.
The new affine negates the z voxel-size and shifts the origin so that the
anatomically superior end of the cord (S1) ends up at high physical z.

Input image (LPS):
  z_vox=5  → z_phys=0.375mm  (physically low = scanner inferior) = S1 end
  z_vox=244 → z_phys=18.3mm  (physically high = scanner superior) = S5/conus

After fix (LPI):
  z_vox=5  → z_phys=50.3mm  (physically high = anatomically SUPERIOR) = S1 ✓
  z_vox=244 → z_phys=36.4mm  (physically lower = more INFERIOR)       = S5 ✓
"""

import sys
import nibabel as nib
import numpy as np
from pathlib import Path


def fix_z_inversion(input_path: str, output_path: str) -> None:
    img = nib.load(input_path)
    old_affine = img.affine.copy()
    N = img.shape[2]

    new_affine = old_affine.copy()
    new_affine[2, 2] = -old_affine[2, 2]                              # negate z voxel size
    new_affine[2, 3] = old_affine[2, 2] * (N - 1) + old_affine[2, 3] # shift origin

    new_hdr = img.header.copy()
    new_hdr.set_qform(new_affine, code=1)
    new_hdr.set_sform(new_affine, code=1)

    # Preserve integer dtypes exactly (avoid float scaling artifacts in label files)
    if np.issubdtype(img.get_data_dtype(), np.integer):
        data = np.asarray(img.dataobj)  # raw voxels, no slope/intercept applied
    else:
        data = img.get_fdata(dtype=np.float32)
    new_img = nib.Nifti1Image(data, new_affine, new_hdr)
    nib.save(new_img, output_path)

    old_orient = nib.aff2axcodes(old_affine)
    new_orient = nib.aff2axcodes(new_affine)
    print(f"  {Path(input_path).name}: {old_orient} → {new_orient}  (affine-only, data unchanged)")


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Usage: fix_z_inversion.py <input.nii.gz> <output.nii.gz>")
        sys.exit(1)
    fix_z_inversion(sys.argv[1], sys.argv[2])
