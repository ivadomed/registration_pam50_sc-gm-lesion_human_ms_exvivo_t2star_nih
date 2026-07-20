#!/usr/bin/env python3
"""Keep only the largest connected component of a binary NIfTI mask.

Usage:
  python cleanup_largest_component.py <input> <output>
"""
import sys
import nibabel as nib
import numpy as np
from scipy.ndimage import label as cc_label


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    _, in_mask, out_mask = sys.argv
    img = nib.load(in_mask)
    d = np.asarray(img.dataobj).astype(bool)
    labeled, n = cc_label(d)
    if n > 1:
        sizes = np.bincount(labeled.ravel())
        sizes[0] = 0
        largest = np.argmax(sizes)
        d = (labeled == largest)
        print(f"  Kept largest CC ({sizes[largest]:,} vox), removed {n-1} smaller component(s)")
    else:
        print(f"  Single component ({d.sum():,} vox), no cleanup needed")
    nib.save(nib.Nifti1Image(d.astype(np.uint8), img.affine, img.header), out_mask)


if __name__ == "__main__":
    main()
