"""Builds a YOLO-format, 7-class detection dataset from the Kaggle downloads.

  raw/index.json  (from download_kaggle.py)  ->  data/ecosort/{images,labels}/{train,val}

* TACO (COCO json) boxes are remapped with datasets.taco_to_category.
* Classification images get one box around the object: we use the whole
  image minus a small margin, then shrink it to the salient region with a
  simple background-difference heuristic (these datasets are mostly a single
  item on a plain background). Boxes that would be implausible fall back to
  the full image.
"""
import argparse
import json
import pathlib
import random
import shutil

import numpy as np
from PIL import Image, ImageOps

from datasets import CLASSES, CLASSIFICATION_MAP, taco_to_category

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "data" / "ecosort"
IMG_EXT = {".jpg", ".jpeg", ".png", ".bmp", ".webp"}


def yolo_line(cls, x0, y0, x1, y1, w, h):
    cx, cy = (x0 + x1) / 2 / w, (y0 + y1) / 2 / h
    bw, bh = (x1 - x0) / w, (y1 - y0) / h
    return f"{cls} {cx:.6f} {cy:.6f} {bw:.6f} {bh:.6f}"


def salient_box(img: Image.Image):
    """Estimates the object box for a single-object photo."""
    small = ImageOps.exif_transpose(img).convert("RGB")
    w, h = small.size
    a = np.asarray(small.resize((96, 96))).astype(np.float32)
    border = np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]])
    bg = np.median(border, axis=0)
    diff = np.abs(a - bg).sum(axis=2)
    mask = diff > max(40.0, np.percentile(diff, 60))
    ys, xs = np.nonzero(mask)
    if len(xs) < 50:
        return 0.02 * w, 0.02 * h, 0.98 * w, 0.98 * h
    x0, x1 = np.percentile(xs, [2, 98]) / 96 * w
    y0, y1 = np.percentile(ys, [2, 98]) / 96 * h
    if (x1 - x0) * (y1 - y0) < 0.08 * w * h:  # too small: probably noise
        return 0.02 * w, 0.02 * h, 0.98 * w, 0.98 * h
    pad = 0.03
    return (max(0, x0 - pad * w), max(0, y0 - pad * h), min(w, x1 + pad * w), min(h, y1 + pad * h))


def add_sample(src: pathlib.Path, lines, split, name):
    dst_img = OUT / "images" / split / f"{name}{src.suffix.lower()}"
    dst_lbl = OUT / "labels" / split / f"{name}.txt"
    shutil.copy(src, dst_img)
    dst_lbl.write_text("\n".join(lines) + "\n")


def build_taco(root: pathlib.Path, stats, val_frac):
    ann_files = list(root.rglob("annotations.json"))
    if not ann_files:
        print("  ! TACO annotations.json not found")
        return
    ann_path = ann_files[0]
    coco = json.loads(ann_path.read_text())
    cats = {c["id"]: taco_to_category(c["name"]) for c in coco["categories"]}
    by_img = {}
    for a in coco["annotations"]:
        by_img.setdefault(a["image_id"], []).append(a)
    for im in coco["images"]:
        src = ann_path.parent / im["file_name"]
        if not src.exists():
            continue
        w, h = im["width"], im["height"]
        # TACO images can carry EXIF rotation; boxes are relative to stored pixels.
        lines = []
        for a in by_img.get(im["id"], []):
            cat = cats.get(a["category_id"])
            if cat is None:
                continue
            x, y, bw, bh = a["bbox"]
            lines.append(yolo_line(CLASSES.index(cat), x, y, x + bw, y + bh, w, h))
            stats[cat] = stats.get(cat, 0) + 1
        if lines:
            split = "val" if random.random() < val_frac else "train"
            add_sample(src, lines, split, f"taco_{im['id']}")


def build_classification(slug, root: pathlib.Path, stats, val_frac, cap):
    per_class = {}
    for f in root.rglob("*"):
        if f.suffix.lower() not in IMG_EXT:
            continue
        label = f.parent.name.lower().replace("_", " ")
        if label not in CLASSIFICATION_MAP:
            label = label.replace(" ", "-")
        cat = CLASSIFICATION_MAP.get(label)
        if cat is None:
            continue
        per_class.setdefault(cat, []).append(f)
    tag = slug.replace("/", "_").replace("-", "_")
    for cat, files in per_class.items():
        random.shuffle(files)
        for i, f in enumerate(files[:cap]):
            try:
                with Image.open(f) as img:
                    w, h = ImageOps.exif_transpose(img).size
                    box = salient_box(img)
            except Exception:
                continue
            line = yolo_line(CLASSES.index(cat), *box, w, h)
            split = "val" if random.random() < val_frac else "train"
            add_sample(f, [line], split, f"{tag}_{cat}_{i}")
            stats[cat] = stats.get(cat, 0) + 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--val", type=float, default=0.12)
    ap.add_argument("--cap", type=int, default=2500,
                    help="max images per category per classification dataset (balances classes)")
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    random.seed(args.seed)

    index = json.loads((HERE / "raw" / "index.json").read_text())
    if OUT.exists():
        shutil.rmtree(OUT)
    for s in ("train", "val"):
        (OUT / "images" / s).mkdir(parents=True)
        (OUT / "labels" / s).mkdir(parents=True)

    stats = {}
    for slug, info in index.items():
        print(f"• {slug}")
        root = pathlib.Path(info["path"])
        if info["kind"] == "detection":
            build_taco(root, stats, args.val)
        else:
            build_classification(slug, root, stats, args.val, args.cap)

    (HERE / "data" / "ecosort.yaml").write_text(
        f"path: {OUT}\ntrain: images/train\nval: images/val\n"
        f"names:\n" + "".join(f"  {i}: {c}\n" for i, c in enumerate(CLASSES))
    )
    print("\nBoxes per category:")
    for c in CLASSES:
        print(f"  {c:10s} {stats.get(c, 0)}")
    print(f"\nDataset ready: {HERE / 'data' / 'ecosort.yaml'}  — next: python train.py")


if __name__ == "__main__":
    main()
