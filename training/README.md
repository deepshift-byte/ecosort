# Training the EcoSort model

The app runs a **YOLO object detector exported to TensorFlow Lite**
(`assets/models/ecosort.tflite`). This folder takes Kaggle datasets and
produces that file.

## Kaggle datasets used

| Kaggle slug | Type | What it adds |
|---|---|---|
| `kneroma/tacotrashdataset` | detection (COCO boxes) | TACO: real litter photos with boxes, 60 classes → mapped to 7 |
| `sumn2u/garbage-classification-v2` | classification | ~20k images, 10 classes incl. **battery** |
| `mostafaabla/garbage-classification` | classification | ~15k images, 12 classes incl. battery, 3 glass colours |
| `joebeachcapital/realwaste` | classification | RealWaste: 4.7k landfill photos (organics, vegetation, …) |
| `akshat103/e-waste-image-dataset` | classification | ~3k images of e-waste devices |

The mapping from source classes to the 7 categories is in `datasets.py`
(`CLASSIFICATION_MAP`, `taco_to_category`). Classification photos show a
single item each, so `build_dataset.py` turns each one into a single box
(estimated from the background) and mixes them with TACO's real boxes.

> The slugs were chosen from Kaggle's catalogue. The build sandbox could not
> reach kaggle.com, so if a dataset has been renamed, swap the slug in
> `datasets.py`. Folder names that are missing from `CLASSIFICATION_MAP` are
> skipped, and the script prints the box count per category so you can spot gaps.

## Option A: train on Kaggle (free GPU, no token needed)

1. Create a new Kaggle Notebook and set the accelerator to GPU (T4 / P100).
2. Use **Add Input** to attach the five datasets above.
3. Upload this `training/` folder, or clone the repo, then run:
   ```bash
   pip install -r requirements.txt
   python link_kaggle_inputs.py      # writes raw/index.json from /kaggle/input
   python build_dataset.py
   python train.py --device 0
   python export_tflite.py
   ```
4. Download `assets/models/ecosort.tflite`, `labels.txt` and
   `category_map.json`, and copy them into the app's `assets/models/`.

## Option B: train locally

```bash
cd training
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# Kaggle API token: kaggle.com → Settings → API → Create New Token → ~/.kaggle/kaggle.json
python download_kaggle.py
python build_dataset.py
python train.py --device 0          # or --device cpu (slow)
python export_tflite.py             # installs into ../assets/models/
```

## Bootstrap model (already bundled)

Until you train the custom model, the app ships with a COCO-pretrained
YOLOv8n exported the same way:

```bash
python export_tflite.py --weights yolov8n.pt --coco
```

It recognises bottles, cups, glasses, cutlery, fruit, phones, laptops,
remotes, books and similar items, and `category_map.json` maps them to the 7
categories. It **cannot** recognise batteries, cans, bags or cardboard. The
custom model is needed for those.

## Model contract (what the app expects)

* input `float32 [1, S, S, 3]`, RGB 0..1 (S = 320 or 640)
* output `float32 [1, 4 + C, N]`, the raw YOLOv8/YOLO11 head without NMS
  (the app runs NMS itself)
* `labels.txt`: C lines, and `category_map.json`: label → category id

Any model that follows this contract can be dropped in without code changes.

## Targets

* ≥ 500 boxes per category (hazardous and e-waste are the scarcest, so add your own photos)
* mAP50 ≥ 0.6 on the validation split
* ≤ 40 ms per frame at 320 px on a mid-range Android phone (fp16 + GPU delegate)
