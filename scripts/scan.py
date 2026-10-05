import os
from datetime import UTC, datetime

import numpy as np
import sane
from tifffile import imwrite

SCANS_DIR = "scans"
RESOLUTION = 1800

RGB_SOURCE = "Transparency Adapter"
IR_SOURCE = "Transparency Adapter Infrared"


def scan(
    devname: str,
    source: str,
    resolution: int = 7200,
    mode: str = "Color",
    depth: int = 16,
) -> np.ndarray:
    dev = sane.open(devname)

    dev.mode = mode
    dev.depth = depth
    dev.resolution = resolution
    dev.source = source

    dev.start()
    arr = dev.arr_snap()
    dev.close()
    return arr


sane.init()
devices = sane.get_devices(localOnly=True)

if len(devices) != 1:
    raise ValueError("Expected one scanner")

devname = devices[0][0]
print(f"Using {devname}")

scan_dir = os.path.join(
    SCANS_DIR,
    datetime.now(UTC).strftime("%Y/%m/%d/%H%M%S") + "-" + str(RESOLUTION),
)
os.makedirs(scan_dir, exist_ok=True)


img_file = os.path.join(scan_dir, "image.tiff")
print(f"{RGB_SOURCE} -> {img_file}")
img = scan(devname, RGB_SOURCE, RESOLUTION)
imwrite(
    img_file,
    img,
    photometric="rgb",
    compression="zlib",
    compressionargs={"level": 8},
    predictor=True,
)

ir_file = os.path.join(scan_dir, "ir.tiff")
print(f"{IR_SOURCE} -> {ir_file}")
ir = scan(devname, IR_SOURCE, RESOLUTION)
imwrite(
    ir_file,
    ir[:, :, 0],
    photometric="minisblack",
    compression="zlib",
    compressionargs={"level": 8},
    predictor=True,
)
