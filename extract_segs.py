#!/usr/bin/env python3
"""Extract SC / WM / GM binary masks from a multi-label segmentation.

Label convention (labels_ensemble):
  1 = healthy WM   2 = healthy GM   3 = lesion WM   4 = lesion GM
  SC = all non-zero,  WM = 1|3,  GM = 2|4

Usage:
  python extract_segs.py <input_seg> <output_sc> <output_wm> <output_gm>
"""
import sys
import nibabel as nib
import numpy as np


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    _, in_seg, out_sc, out_wm, out_gm = sys.argv
    seg = nib.load(in_seg)
    d, aff, hdr = np.asarray(seg.dataobj), seg.affine, seg.header
    sc = (d > 0).astype(np.uint8)
    wm = np.isin(d, [1, 3]).astype(np.uint8)
    gm = np.isin(d, [2, 4]).astype(np.uint8)
    for mask, path in [(sc, out_sc), (wm, out_wm), (gm, out_gm)]:
        nib.save(nib.Nifti1Image(mask, aff, hdr), path)
    print(f"  SC: {sc.sum():,}  WM: {wm.sum():,}  GM: {gm.sum():,} voxels")


if __name__ == "__main__":
    main()
