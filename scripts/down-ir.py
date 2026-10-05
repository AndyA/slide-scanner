import glob
import os

import cv2
import numpy as np
from tifffile import imread, imwrite

SCANS_DIR = "scans"


for img_file in glob.glob(
    os.path.join(SCANS_DIR, "**", "rgbu16_ir.tiff"), recursive=True
):
    img = imread(img_file)
    if len(img.shape) == 3 and img.shape[-1] > 1:
        print(f"Processing {img_file}")
        imwrite(img_file, img[:, :, 0], photometric="minisblack")
