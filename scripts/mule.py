import glob
import os

import cv2
import numpy as np
from lib.constants import SCANS_DIR
from lib.peer_files import PeerFiles


def thresholds(pf: PeerFiles) -> None:
    ir = pf.load("ir")
    min = ir.min()
    max = ir.max()
    for pc in range(5, 100, 5):
        cutoff = int(((max - min) / 100 * pc) + min)
        print(f"  threshold: {pc}%")
        threshold = ((ir < cutoff) * 255).astype(np.uint8)
        pf.save(f"mule.threshold-{pc}", threshold, photometric="minisblack")


def mean_thresholds(pf: PeerFiles) -> None:
    ir = pf.load("ir")
    blurred = cv2.GaussianBlur(ir, (75, 75), 0)
    pf.save("mule.blurred", blurred, photometric="minisblack")
    diff = ((ir < blurred * 0.9) * 255).astype(np.uint8)
    pf.save("mule.diff", diff, photometric="minisblack")

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (5, 5))
    mask = cv2.dilate(diff, kernel, iterations=1)
    pf.save("mule.fat", mask, photometric="minisblack")

    img = pf.load("image")
    radius = 0.95
    r = cv2.inpaint(img[:, :, 0], mask, radius, cv2.INPAINT_TELEA)
    g = cv2.inpaint(img[:, :, 1], mask, radius, cv2.INPAINT_TELEA)
    b = cv2.inpaint(img[:, :, 2], mask, radius, cv2.INPAINT_TELEA)
    fixed = np.stack([r, g, b])
    pf.save("mule.fixed", fixed, photometric="rgb")


for ir_file in glob.glob(os.path.join(SCANS_DIR, "**", "ir.tiff"), recursive=True):
    pf = PeerFiles.from_file(ir_file)
    print(f"Processing {ir_file}")
    mean_thresholds(pf)
