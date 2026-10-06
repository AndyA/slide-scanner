import os
from datetime import UTC, datetime

import numpy as np
import sane
from lib.constants import SCANS_DIR
from lib.peer_files import PeerFiles

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

pf = PeerFiles(dir=scan_dir)

os.makedirs(scan_dir, exist_ok=True)


print(f"{RGB_SOURCE} -> image.tiff")
img = scan(devname, RGB_SOURCE, RESOLUTION)
pf.save("image", img, photometric="rgb")

print(f"{IR_SOURCE} -> ir.tiff")
ir = scan(devname, IR_SOURCE, RESOLUTION)
pf.save("ir", ir[:, :, 0], photometric="minisblack")
