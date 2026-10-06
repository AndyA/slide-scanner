import glob
import os

import numpy as np
from lib.constants import SCANS_DIR
from lib.job_files import JobFiles


def normalise(jf: JobFiles) -> None:
    img = jf.load("image")
    # print(f"Image range: {img.min()} - {img.max()}")
    scale = max(img.shape[0], img.shape[1]) / 2560
    base = img.min()
    scale = 65535 / (img.max() - base)
    norm = ((img - base) * scale).astype(np.uint16)
    jf.save("norm", norm, photometric="rgb")


for img_file in glob.glob(os.path.join(SCANS_DIR, "**", "image.tiff"), recursive=True):
    jf = JobFiles.from_file(img_file)
    if os.path.exists(jf.tiff_name("norm")):
        continue
    print(f"Normalising {img_file}")
    normalise(jf)
