"""Downloads the training datasets from Kaggle.

Setup (once):
  1. kaggle.com -> Settings -> API -> "Create New Token"  (kaggle.json)
  2. Put it in ~/.kaggle/kaggle.json  (or export KAGGLE_USERNAME / KAGGLE_KEY)

Usage:
  python download_kaggle.py            # all datasets
  python download_kaggle.py --only kneroma/tacotrashdataset
"""
import argparse
import json
import pathlib

import kagglehub

from datasets import KAGGLE_DATASETS

ROOT = pathlib.Path(__file__).resolve().parent / "raw"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", help="dataset slugs to fetch")
    args = ap.parse_args()
    slugs = args.only or list(KAGGLE_DATASETS)
    ROOT.mkdir(exist_ok=True)
    index = {}
    for slug in slugs:
        kind, desc = KAGGLE_DATASETS[slug]
        print(f"↓ {slug}  ({desc})")
        path = kagglehub.dataset_download(slug)
        index[slug] = {"kind": kind, "path": str(path)}
        print(f"  -> {path}")
    (ROOT / "index.json").write_text(json.dumps(index, indent=2))
    print(f"\nWrote {ROOT / 'index.json'}. Next: python build_dataset.py")


if __name__ == "__main__":
    main()
