import os
from datetime import UTC, datetime

import sane
from tifffile import imwrite

SCANS_DIR = "scans"
RESOLUTION = 1800

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

scans = [
    ("Transparency Adapter", ""),
    ("Transparency Adapter Infrared", "_ir"),
]

for source, suffix in scans:
    file = os.path.join(scan_dir, f"rgbu16{suffix}.tiff")
    print(f"{source} -> {file}")
    dev = sane.open(devname)

    dev.mode = "Color"
    dev.depth = 16
    dev.resolution = RESOLUTION
    dev.source = source

    dev.start()
    arr = dev.arr_snap()
    imwrite(file, arr, photometric="rgb")

    dev.close()
