import json
import os
from dataclasses import dataclass
from functools import cached_property
from typing import Any, Self

import numpy as np
from tifffile import imread, imwrite  # pyright: ignore[reportUnknownVariableType]


@dataclass(kw_only=True, frozen=True)
class PeerFiles:
    dir: str

    @classmethod
    def from_file(cls, name: str) -> Self:
        dir = os.path.dirname(name)
        return cls(dir=dir)

    @cached_property
    def out_dir(self) -> str:
        os.makedirs(self.dir, exist_ok=True)
        return self.dir

    def file_name(self, base: str, ext: str) -> str:
        return os.path.join(self.dir, f"{base}.{ext}")

    def tiff_name(self, base: str) -> str:
        return self.file_name(base, "tiff")

    def json_name(self, base: str) -> str:
        return self.file_name(base, "json")

    def load(self, base: str) -> np.ndarray:
        return imread(self.tiff_name(base))

    def save(self, base: str, img: np.ndarray, photometric: str) -> None:
        _ = self.out_dir
        file_name = self.tiff_name(base)
        tmp_name = self.tiff_name(f"tmp.{base}")
        imwrite(
            tmp_name,
            img,
            photometric=photometric,
            compression="zlib",
            compressionargs={"level": 8},
            predictor=True,
        )
        os.rename(tmp_name, file_name)

    def load_json(self, base: str) -> Any:
        with open(self.json_name(base), "r") as f:
            return json.load(f)

    def save_json(self, base: str, data: Any) -> None:
        _ = self.out_dir
        file_name = self.json_name(base)
        tmp_name = self.json_name(f"tmp.{base}")
        with open(tmp_name, "w") as f:
            json.dump(data, f, indent=2)
        os.rename(tmp_name, file_name)
