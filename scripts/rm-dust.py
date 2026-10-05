import glob
import os

import cv2
import numpy as np
from tifffile import imread, imwrite

SCANS_DIR = "scans"


def foo(dir: str, img: np.ndarray) -> None:
    blur_sm = cv2.blur(img, (5, 5))
    imwrite(os.path.join(dir, "ir.blur_sm.tiff"), blur_sm, photometric="rgb")
    blur_bg = cv2.blur(img, (21, 21))
    imwrite(os.path.join(dir, "ir.blur_bg.tiff"), blur_bg, photometric="rgb")
    diff = blur_sm - blur_bg
    # print(diff.shape, diff.dtype)
    imwrite(os.path.join(dir, "ir.diff.tiff"), diff, photometric="rgb")


def rm_dust(
    dir: str,
    img: np.ndarray,
    ir: np.ndarray,
    threshold: float = 0.95,
    radius: float = 0.95,
) -> np.ndarray:
    alpha = ((ir[:, :, 0] + ir[:, :, 1] + ir[:, :, 2]) / 3).astype(np.uint16)

    kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (7, 7))
    eroded = cv2.erode(alpha, kernel, iterations=1)
    imwrite(os.path.join(dir, "ir.eroded.tiff"), eroded, photometric="minisblack")
    cutoff = eroded.max() * threshold
    mask = ((eroded < cutoff) * 255).astype(np.uint8)
    imwrite(os.path.join(dir, "ir.mask.tiff"), mask, photometric="minisblack")
    dilated = cv2.dilate(mask, kernel, iterations=1)
    imwrite(os.path.join(dir, "ir.dilated.tiff"), dilated, photometric="minisblack")
    r = cv2.inpaint(img[:, :, 0], dilated, radius, cv2.INPAINT_NS)
    g = cv2.inpaint(img[:, :, 1], dilated, radius, cv2.INPAINT_NS)
    b = cv2.inpaint(img[:, :, 2], dilated, radius, cv2.INPAINT_NS)
    return np.stack([r, g, b])


for img_file in glob.glob(os.path.join(SCANS_DIR, "**", "image.tiff"), recursive=True):
    dir = os.path.dirname(img_file)
    out_file = os.path.join(dir, "ir.cleaned.tiff")
    # if os.path.exists(out_file):
    #     continue
    print(f"Processing {img_file}")
    img = imread(img_file)
    ir = imread(os.path.join(dir, "ir.tiff"))
    foo(dir, ir)
    clean = rm_dust(dir, img, ir, threshold=0.10)
    imwrite(out_file, clean, photometric="rgb")
