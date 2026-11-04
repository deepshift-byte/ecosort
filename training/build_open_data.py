"""Builds the 7-class YOLO dataset from openly hosted sources (no Kaggle
account needed):

* Google Open Images (validation + test splits): real, human-drawn boxes
  for ~45 waste-relevant classes, mapped to the 7 categories below.
* TrashNet (github.com/garythung/trashnet): 2.5k single-item trash photos
  (the original of the popular Kaggle "garbage classification" sets), turned
  into one box per image like build_dataset.py does.

  python build_open_data.py --per-class 350

Output: data/ecosort/{images,labels}/{train,val} + data/ecosort.yaml
"""
import argparse
import csv
import io
import pathlib
import random
import shutil
import urllib.request
import zipfile
from concurrent.futures import ThreadPoolExecutor

from PIL import Image

from build_dataset import salient_box, yolo_line
from datasets import CLASSES

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "data" / "ecosort"
CACHE = HERE / "raw" / "open"

OI_BASE = "https://storage.googleapis.com/openimages"
OI_IMG = "https://open-images-dataset.s3.amazonaws.com/{split}/{id}.jpg"
TRASHNET = "https://raw.githubusercontent.com/garythung/trashnet/master/data/dataset-resized.zip"

OI_MAP = {
    "plastic": ["Bottle", "Plastic bag", "Drinking straw", "Toothbrush"],
    "paper": ["Box", "Book", "Envelope"],
    "glass": ["Wine glass", "Wine"],
    "metal": ["Tin can", "Fork", "Spoon", "Knife", "Kitchen knife", "Frying pan", "Scissors"],
    "organic": ["Apple", "Banana", "Bread", "Carrot", "Tomato", "Fruit", "Vegetable", "Egg"],
    "ewaste": ["Mobile phone", "Laptop", "Computer keyboard", "Computer mouse", "Remote control",
               "Television", "Computer monitor", "Headphones", "Calculator", "Tablet computer",
               "Camera", "Printer"],
    "hazardous": ["Light bulb", "Syringe"],
}
TRASHNET_MAP = {"plastic": "plastic", "paper": "paper", "cardboard": "paper",
                "glass": "glass", "metal": "metal"}  # "trash" is skipped


def fetch(url, dest: pathlib.Path):
    if not dest.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        tmp = dest.with_suffix(dest.suffix + ".part")
        with urllib.request.urlopen(url, timeout=120) as r, open(tmp, "wb") as f:
            shutil.copyfileobj(r, f)
        tmp.rename(dest)
    return dest


def load_open_images(per_class, rng):
    names = {}
    with open(fetch(f"{OI_BASE}/v5/class-descriptions-boxable.csv", CACHE / "classes.csv"),
              encoding="utf-8") as f:
        for mid, name in csv.reader(f):
            names[mid] = name
    to_cat = {n: c for c, ns in OI_MAP.items() for n in ns}
    wanted = {mid: to_cat[n] for mid, n in names.items() if n in to_cat}

    images = {}  # (split, id) -> list of (cat, box)
    for split in ("validation", "test"):
        path = fetch(f"{OI_BASE}/v5/{split}-annotations-bbox.csv", CACHE / f"{split}-bbox.csv")
        with open(path, encoding="utf-8") as f:
            for row in csv.DictReader(f):
                cat = wanted.get(row["LabelName"])
                # Skip "group of" boxes: they cover many objects at once.
                if cat is None or row["IsGroupOf"] == "1":
                    continue
                box = tuple(float(row[k]) for k in ("XMin", "YMin", "XMax", "YMax"))
                images.setdefault((split, row["ImageID"]), []).append((cat, box))

    # Pick up to `per_class` images per category, rarest category first.
    by_cat = {c: [] for c in CLASSES}
    for key, anns in images.items():
        for c in {a[0] for a in anns}:
            by_cat[c].append(key)
    chosen = set()
    for c in sorted(CLASSES, key=lambda c: len(by_cat[c])):
        pool = [k for k in by_cat[c] if k not in chosen]
        rng.shuffle(pool)
        have = sum(1 for k in chosen if any(a[0] == c for a in images[k]))
        chosen.update(pool[: max(0, per_class - have)])
    return {k: images[k] for k in chosen}


def download_image(key):
    split, iid = key
    dest = CACHE / "img" / f"{iid}.jpg"
    try:
        fetch(OI_IMG.format(split=split, id=iid), dest)
        return key, dest
    except Exception:
        return key, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-class", type=int, default=350)
    ap.add_argument("--val", type=float, default=0.12)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args()
    rng = random.Random(args.seed)

    if OUT.exists():
        shutil.rmtree(OUT)
    for s in ("train", "val"):
        (OUT / "images" / s).mkdir(parents=True)
        (OUT / "labels" / s).mkdir(parents=True)
    stats = {c: 0 for c in CLASSES}

    print("• Open Images: reading box annotations…")
    picked = load_open_images(args.per_class, rng)
    print(f"  downloading {len(picked)} images…")
    with ThreadPoolExecutor(32) as ex:
        results = list(ex.map(download_image, picked))
    for key, path in results:
        if path is None:
            continue
        lines = []
        for cat, (x0, y0, x1, y1) in picked[key]:
            cls = CLASSES.index(cat)
            lines.append(f"{cls} {(x0 + x1) / 2:.6f} {(y0 + y1) / 2:.6f} {x1 - x0:.6f} {y1 - y0:.6f}")
            stats[cat] += 1
        split = "val" if rng.random() < args.val else "train"
        shutil.copy(path, OUT / "images" / split / f"oi_{key[1]}.jpg")
        (OUT / "labels" / split / f"oi_{key[1]}.txt").write_text("\n".join(lines) + "\n")

    print("• TrashNet")
    z = zipfile.ZipFile(fetch(TRASHNET, CACHE / "trashnet.zip"))
    for n in z.namelist():
        parts = n.split("/")
        if (not n.lower().endswith(".jpg") or len(parts) < 2 or parts[-2] not in TRASHNET_MAP
                or "__MACOSX" in n or parts[-1].startswith("._")):
            continue
        cat = TRASHNET_MAP[parts[-2]]
        data = z.read(n)
        try:
            img = Image.open(io.BytesIO(data))
            w, h = img.size
            line = yolo_line(CLASSES.index(cat), *salient_box(img), w, h)
        except Exception:
            continue
        split = "val" if rng.random() < args.val else "train"
        stem = f"tn_{parts[-1][:-4]}"
        (OUT / "images" / split / f"{stem}.jpg").write_bytes(data)
        (OUT / "labels" / split / f"{stem}.txt").write_text(line + "\n")
        stats[cat] += 1

    (HERE / "data" / "ecosort.yaml").write_text(
        f"path: {OUT}\ntrain: images/train\nval: images/val\nnames:\n"
        + "".join(f"  {i}: {c}\n" for i, c in enumerate(CLASSES)))
    n_train = len(list((OUT / "images" / "train").iterdir()))
    n_val = len(list((OUT / "images" / "val").iterdir()))
    print(f"\n{n_train} train / {n_val} val images. Boxes per category:")
    for c in CLASSES:
        print(f"  {c:10s} {stats[c]}")


if __name__ == "__main__":
    main()
