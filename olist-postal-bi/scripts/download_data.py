#!/usr/bin/env python3
"""Download the public Olist dataset with kagglehub and expose it under data/raw."""

from pathlib import Path
import os

import kagglehub


PROJECT_ROOT = Path(__file__).resolve().parents[1]
RAW_LINK = PROJECT_ROOT / "data" / "raw" / "kaggle_source"


def main() -> None:
    source = Path(kagglehub.dataset_download("olistbr/brazilian-ecommerce")).resolve()
    RAW_LINK.parent.mkdir(parents=True, exist_ok=True)
    if RAW_LINK.is_symlink() and RAW_LINK.resolve() == source:
        pass
    elif RAW_LINK.exists() or RAW_LINK.is_symlink():
        raise RuntimeError(f"Refusing to overwrite existing path: {RAW_LINK}")
    else:
        os.symlink(source, RAW_LINK, target_is_directory=True)
    print(source)


if __name__ == "__main__":
    main()

