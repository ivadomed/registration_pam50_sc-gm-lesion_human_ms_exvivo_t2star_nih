#!/usr/bin/env python3
"""Build a one-voxel spinal level landmark file for C1 and C2 from an SC mask.

After affine z-flip, the superior end of the chunk is at high z_vox.
Searches near the volume top for C1 and near the bottom for C2.
PAM50 spinal level label IDs: C1=1, C2=2.

Usage:
  python build_landmarks_cervical.py <sc_mask> <output_landmarks>
"""
import sys
import nibabel as nib
import numpy as np

# Search windows (z_vox after z-flip; C1 near top = high z, C2 near bottom = low z)
C1_SEARCH = range(690, 660, -1)
C2_SEARCH = range(40, 70)


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    _, in_sc, out_landmarks = sys.argv
    sc = nib.load(in_sc)
    d = np.asarray(sc.dataobj) > 0
    out = np.zeros(d.shape, dtype=np.uint8)
    for label, z_range, name in [(1, C1_SEARCH, "C1"), (2, C2_SEARCH, "C2")]:
        for z in z_range:
            sl = d[:, :, z]
            if sl.sum() == 0:
                continue
            xs, ys = np.where(sl)
            out[int(xs.mean()), int(ys.mean()), z] = label
            print(f"  {name} anchor (label={label}) at z_vox={z}")
            break
    nib.save(nib.Nifti1Image(out, sc.affine, sc.header), out_landmarks)


if __name__ == "__main__":
    main()
