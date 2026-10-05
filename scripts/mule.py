import glob
import os

import numpy as np
from tifffile import imread, imwrite

SCANS_DIR = "scans"

for img_file in glob.glob(os.path.join(SCANS_DIR, "**", "ir.tiff"), recursive=True):
    print(f"Processing {img_file}")
    dir = os.path.dirname(img_file)
    img = imread(img_file)
    min = img.min()
    max = img.max()
    for pc in range(0, 100, 5):
        cutoff = int(((max - min) / 100 * pc) + min)
        out_file = os.path.join(dir, f"mule.threshold-{pc}.tiff")
        print(f"  {out_file}")
        threshold = ((img < cutoff) * 255).astype(np.uint8)
        imwrite(out_file, threshold, photometric="minisblack")
