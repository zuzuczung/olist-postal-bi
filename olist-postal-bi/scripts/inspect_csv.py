#!/usr/bin/env python3
"""Print source CSV headers, sizes, and sample rows before schema work."""

from pathlib import Path
import csv
import os


DEFAULT_DATA_DIR = Path.home() / ".cache/kagglehub/datasets/olistbr/brazilian-ecommerce/versions/2"


def main() -> None:
    root = Path(os.getenv("OLIST_DATA_DIR", DEFAULT_DATA_DIR)).expanduser().resolve()
    if not root.exists():
        raise SystemExit(f"Dataset directory does not exist: {root}")
    for path in sorted(root.glob("*.csv")):
        with path.open(encoding="utf-8-sig", newline="") as handle:
            reader = csv.reader(handle)
            header = next(reader)
            sample = [row for _, row in zip(range(3), reader)]
        print(f"FILE {path.name} bytes={path.stat().st_size}")
        print("COLUMNS", header)
        for row in sample:
            print("SAMPLE", row)
        print()


if __name__ == "__main__":
    main()

