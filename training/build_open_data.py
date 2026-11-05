"""Builds the 7-class YOLO dataset from openly hosted sources (no Kaggle
account needed):

* Google Open Images (validation + test, and with --oi-train the 1.7M-image
  train split): human-drawn boxes for ~45 waste-relevant classes.
* Open Images human-verified *image-level* labels for hazardous items that
  have no boxes (batteries, paint, sprays, motor oil, bleach, medicine, pills,
  fluorescent lamps, thermometers…) — one estimated box per image.
* TrashNet (github.com/garythung/trashnet): 2.5k single-item trash photos
  (the original of the popular Kaggle "garbage classification" sets).

  python build_open_data.py --per-class 900 --oi-train --hazard-images 900

Output: data/<name>/{images,labels}/{train,val} + data/<name>.yaml (default name: ecosort)
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

from PIL import Image, ImageOps

from build_dataset import salient_box, yolo_line
from datasets import CLASSES

HERE = pathlib.Path(__file__).resolve().parent
OUT = HERE / "data" / "ecosort"
CACHE = HERE / "raw" / "open"
MAX_SIDE = 640

OI = "https://storage.googleapis.com/openimages"
OI_IMG = "https://open-images-dataset.s3.amazonaws.com/{split}/{id}.jpg"
TRASHNET = "https://raw.githubusercontent.com/garythung/trashnet/master/data/dataset-resized.zip"

BBOX_FILES = {
    "validation": f"{OI}/v5/validation-annotations-bbox.csv",
    "test": f"{OI}/v5/test-annotations-bbox.csv",
    "train": f"{OI}/v6/oidv6-train-annotations-bbox.csv",
}
LABEL_FILES = {
    "validation": f"{OI}/v5/validation-annotations-human-imagelabels.csv",
    "test": f"{OI}/v5/test-annotations-human-imagelabels.csv",
    "train": f"{OI}/v6/oidv6-train-annotations-human-imagelabels.csv",
}

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
# Image-level (no boxes) hazardous labels, by Open Images MID.
HAZARD_LABELS = {
    "/m/01c0z": "Battery", "/m/0h8k552": "Mobile phone battery", "/m/05y4t": "Paint",
    "/m/0gmc028": "Spray", "/m/01fnj5": "Motor oil", "/m/030l0j": "Bleach",
    "/m/02r537t": "Pill", "/m/04sh3": "Medicine", "/m/018l35": "Pharmaceutical drug",
    "/m/08ncv6": "Capsule", "/m/012757": "Fluorescent lamp",
    "/m/04gvd_": "Compact fluorescent lamp", "/m/0cpk7": "Incandescent light bulb",
    "/m/07mf1": "Thermometer", "/m/05wz1": "Propane",
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


def stream_csv(url):
    """Iterates a remote CSV without saving it (the train files are GBs)."""
    with urllib.request.urlopen(url, timeout=300) as r:
        yield from csv.DictReader(io.TextIOWrapper(r, encoding="utf-8"))


def class_mids():
    names = {}
    with open(fetch(f"{OI}/v5/class-descriptions-boxable.csv", CACHE / "classes.csv"),
              encoding="utf-8") as f:
        for mid, name in csv.reader(f):
            names[mid] = name
    to_cat = {n: c for c, ns in OI_MAP.items() for n in ns}
    return {mid: to_cat[n] for mid, n in names.items() if n in to_cat}


def load_boxes(splits):
    wanted = class_mids()
    images = {}  # (split, id) -> [(cat, box)]
    for split in splits:
        print(f"  streaming {split} boxes…", flush=True)
        for row in stream_csv(BBOX_FILES[split]):
            cat = wanted.get(row["LabelName"])
            # Skip "group of" boxes (many objects at once) and drawings.
            if cat is None or row["IsGroupOf"] == "1" or row["IsDepiction"] == "1":
                continue
            box = tuple(float(row[k]) for k in ("XMin", "YMin", "XMax", "YMax"))
            images.setdefault((split, row["ImageID"]), []).append((cat, box))
    return images


def pick_balanced(images, per_class, rng):
    by_cat = {c: [] for c in CLASSES}
    for key, anns in images.items():
        for c in {a[0] for a in anns}:
            by_cat[c].append(key)
    chosen = set()
    for c in sorted(CLASSES, key=lambda c: len(by_cat[c])):  # rarest first
        have = sum(1 for k in chosen if any(a[0] == c for a in images[k]))
        pool = [k for k in by_cat[c] if k not in chosen]
        rng.shuffle(pool)
        chosen.update(pool[: max(0, per_class - have)])
        print(f"  {c:10s} {len(by_cat[c]):6d} candidate images")
    return {k: images[k] for k in chosen}


def load_hazard_images(splits, limit, exclude, rng):
    found = {}
    for split in splits:
        print(f"  streaming {split} image labels…", flush=True)
        for row in stream_csv(LABEL_FILES[split]):
            if row["Confidence"] == "1" and row["LabelName"] in HAZARD_LABELS:
                key = (split, row["ImageID"])
                if key not in exclude:
                    found.setdefault(key, HAZARD_LABELS[row["LabelName"]])
    keys = list(found)
    rng.shuffle(keys)
    # Spread the budget over the label types so "Medicine" doesn't swamp batteries.
    by_label = {}
    for k in keys:
        by_label.setdefault(found[k], []).append(k)
    picked, i = [], 0
    while len(picked) < limit and any(by_label.values()):
        for lbl in list(by_label):
            if by_label[lbl] and len(picked) < limit:
                picked.append(by_label[lbl].pop())
        i += 1
    counts = {}
    for k in picked:
        counts[found[k]] = counts.get(found[k], 0) + 1
    print("  hazardous image labels:", ", ".join(f"{k} {v}" for k, v in sorted(counts.items())))
    return picked


def download_image(key):
    """Downloads one Open Images photo, resized so its long side is ≤ 640 px."""
    split, iid = key
    dest = CACHE / "img" / f"{iid}.jpg"
    if dest.exists():
        return key, dest
    try:
        with urllib.request.urlopen(OI_IMG.format(split=split, id=iid), timeout=60) as r:
            img = Image.open(io.BytesIO(r.read()))
            img = ImageOps.exif_transpose(img).convert("RGB")
        img.thumbnail((MAX_SIDE, MAX_SIDE))
        dest.parent.mkdir(parents=True, exist_ok=True)
        img.save(dest, quality=90)
        return key, dest
    except Exception:
        return key, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--per-class", type=int, default=350, help="Open Images photos per category")
    ap.add_argument("--oi-train", action="store_true", help="also use the 1.7M-image train split")
    ap.add_argument("--hazard-images", type=int, default=0,
                    help="extra hazardous photos from image-level labels (batteries, paint, …)")
    ap.add_argument("--val", type=float, default=0.12)
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--name", default="ecosort", help="output folder / yaml name under data/")
    args = ap.parse_args()
    global OUT
    OUT = HERE / "data" / args.name
    rng = random.Random(args.seed)
    splits = ["validation", "test"] + (["train"] if args.oi_train else [])

    if OUT.exists():
        shutil.rmtree(OUT)
    for s in ("train", "val"):
        (OUT / "images" / s).mkdir(parents=True)
        (OUT / "labels" / s).mkdir(parents=True)
    stats = {c: 0 for c in CLASSES}

    def place(stem, src: pathlib.Path, lines):
        split = "val" if rng.random() < args.val else "train"
        shutil.copy(src, OUT / "images" / split / f"{stem}.jpg")
        (OUT / "labels" / split / f"{stem}.txt").write_text("\n".join(lines) + "\n")

    print("• Open Images boxes")
    picked = pick_balanced(load_boxes(splits), args.per_class, rng)
    hazard = []
    if args.hazard_images:
        print("• Open Images hazardous image labels")
        hazard = load_hazard_images(splits, args.hazard_images, set(picked), rng)

    todo = list(picked) + hazard
    print(f"  downloading {len(todo)} images…", flush=True)
    with ThreadPoolExecutor(48) as ex:
        paths = dict(ex.map(download_image, todo))

    for key, anns in picked.items():
        if paths.get(key) is None:
            continue
        lines = []
        for cat, (x0, y0, x1, y1) in anns:
            lines.append(f"{CLASSES.index(cat)} {(x0 + x1) / 2:.6f} {(y0 + y1) / 2:.6f} "
                         f"{x1 - x0:.6f} {y1 - y0:.6f}")
            stats[cat] += 1
        place(f"oi_{key[1]}", paths[key], lines)

    hz = CLASSES.index("hazardous")
    for key in hazard:
        path = paths.get(key)
        if path is None:
            continue
        with Image.open(path) as img:
            w, h = img.size
            line = yolo_line(hz, *salient_box(img), w, h)
        place(f"oih_{key[1]}", path, [line])
        stats["hazardous"] += 1

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

    (HERE / "data" / f"{args.name}.yaml").write_text(
        f"path: {OUT}\ntrain: images/train\nval: images/val\nnames:\n"
        + "".join(f"  {i}: {c}\n" for i, c in enumerate(CLASSES)))
    n_train = len(list((OUT / "images" / "train").iterdir()))
    n_val = len(list((OUT / "images" / "val").iterdir()))
    print(f"\n{n_train} train / {n_val} val images. Boxes per category:")
    for c in CLASSES:
        print(f"  {c:10s} {stats[c]}")


if __name__ == "__main__":
    main()
