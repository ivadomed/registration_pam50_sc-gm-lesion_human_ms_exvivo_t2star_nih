#!/usr/bin/env python3
"""Build a one-voxel spinal level landmark file for S2 and S3 from vertebrae labels.

Reads a vertebrae segmentation where values follow PAM50 conventions:
  S2=26, S3=27 (1-7=C1-C7, 8-19=T1-T12, 20-24=L1-L5, 25-29=S1-S5)

MARGIN keeps anchors away from volume edges to prevent IndexError during
SCT's internal 1mm resampling of the landmark file.

Usage:
  python build_landmarks_sacral.py <vertebrae_seg> <output_landmarks>
"""
import sys
import nibabel as nib
import numpy as np

MARGIN = 40  # min voxels from volume edge


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    _, in_vert, out_landmarks = sys.argv
    img = nib.load(in_vert)
    data = np.asarray(img.dataobj).copy()
    out = np.zeros_like(data)
    NZ = data.shape[2]
    for v, name in [(26, "S2"), (27, "S3")]:
        zs = np.where(data == v)[2]
        if len(zs) == 0:
            print(f"  WARNING: {name} (val={v}) not found in vertebrae labels!")
            continue
        z = int(np.clip(zs.mean(), MARGIN, NZ - 1 - MARGIN))
        mask = data[:, :, z] == v
        if not mask.any():
            mask = data[:, :, zs[0]] == v
        xs, ys = np.where(mask)
        out[int(xs.mean()), int(ys.mean()), z] = v
        print(f"  {name} anchor (label={v}) at z_vox={z}")
    nib.save(nib.Nifti1Image(out, img.affine, img.header), out_landmarks)


if __name__ == "__main__":
    main()
