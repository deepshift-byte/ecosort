"""Appends the TrashBox dataset (github.com/nikhilvenkatkumsetty/TrashBox,
~14k single-item trash photos in 7 classes incl. e-waste and medical) to an
existing YOLO dataset folder built by build_open_data.py / build_dataset.py.

  git clone --depth 1 https://github.com/nikhilvenkatkumsetty/TrashBox
  python add_trashbox.py /path/to/TrashBox --name ecosort_v2 --cap 1500

Each photo shows one item, so it gets one estimated box (salient_box).
"""
import argparse
import pathlib
import random

from PIL import Image, ImageOps

from build_dataset import salient_box, yolo_line
from datasets import CLASSES

HERE = pathlib.Path(__file__).resolve().parent
MAX_SIDE = 640

# "<class>/<subclass>" (or "<class>") -> EcoSort category; None = skip.
TRASHBOX_MAP = {
    "cardboard": "paper",
    "paper": "paper",
    "glass": "glass",
    "plastic": "plastic",
    "plastic/cigarette butt": None,  # general waste
    "metal": "metal",
    "metal/spray cans": "hazardous",  # aerosols
    "e-waste": "ewaste",
    "medical/syringe": "hazardous",
    "medical/medicines": "hazardous",
    "medical/gloves": None,  # general waste
    "medical/masks": None,
}


def category_for(rel: pathlib.Path):
    parts = [p.lower() for p in rel.parts[:-1]]
    for key in ("/".join(parts[:2]), parts[0] if parts else ""):
        if key in TRASHBOX_MAP:
            return TRASHBOX_MAP[key]
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("trashbox", type=pathlib.Path, help="path to the cloned TrashBox repo")
    ap.add_argument("--name", default="ecosort")
    ap.add_argument("--cap", type=int, default=1500, help="max images per category")
    ap.add_argument("--val", type=float, default=0.12)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    rng = random.Random(args.seed)
    out = HERE / "data" / args.name
    assert (out / "images" / "train").is_dir(), f"build the base dataset first: {out}"

    root = args.trashbox / "TrashBox_train_dataset_subfolders"
    by_cat = {}
    for f in root.rglob("*.jpg"):
        cat = category_for(f.relative_to(root))
        if cat:
            by_cat.setdefault(cat, []).append(f)

    stats = {}
    for cat, files in sorted(by_cat.items()):
        rng.shuffle(files)
        for i, f in enumerate(files[: args.cap]):
            try:
                with Image.open(f) as im:
                    img = ImageOps.exif_transpose(im).convert("RGB")
                img.thumbnail((MAX_SIDE, MAX_SIDE))
                w, h = img.size
                line = yolo_line(CLASSES.index(cat), *salient_box(img), w, h)
            except Exception:
                continue
            split = "val" if rng.random() < args.val else "train"
            stem = f"tb_{cat}_{i}"
            img.save(out / "images" / split / f"{stem}.jpg", quality=90)
            (out / "labels" / split / f"{stem}.txt").write_text(line + "\n")
            stats[cat] = stats.get(cat, 0) + 1
    print("TrashBox images added per category:")
    for c in CLASSES:
        print(f"  {c:10s} {stats.get(c, 0)}  (of {len(by_cat.get(c, []))} available)")


if __name__ == "__main__":
    main()
