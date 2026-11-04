# EcoSort ♻️

EcoSort is an on-device mobile app (Flutter, Android + iOS) that sorts waste into **7 categories**:
Plastic · Paper · Glass · Metal · Organic · E-waste · Hazardous.

* **Live scan**: point the camera at items. Each item gets a colour-coded outline and a label chip.
* **Photo**: take a photo or upload one, and get an annotated image with a per-category breakdown.
* **Video**: upload a short clip (up to 60 s). Frames are sampled and tracked, and each unique item is counted once.
* **Ask (type or speak)**: describe your trash and get its category, how to handle it, and where to put it. Works offline.
* **History & stats**: timestamps verified by a time API (WorldTimeAPI, then TimeAPI.io, then the device clock), a daily streak and a countdown to collection day.

The model runs locally as a **TensorFlow Lite (`.tflite`)** YOLO detector. See [`docs/PLAN.md`](docs/PLAN.md) for the full plan and [`training/README.md`](training/README.md) to train it on the Kaggle trash datasets.

## Run

```bash
flutter pub get
flutter run            # on a connected Android (API 26+) or iOS device
```

Run the tests and static checks:

```bash
flutter test && flutter analyze
```

## Model

`assets/models/` ships with a **bootstrap** model: COCO-pretrained YOLOv8n at 320 px, mapped to the 7 categories. It handles bottles, cups, glasses, cutlery, food, phones, laptops and books. Train the custom 7-class model from Kaggle data to cover cans, bags, cardboard, batteries and other hazardous items:

```bash
cd training && pip install -r requirements.txt
python download_kaggle.py && python build_dataset.py && python train.py && python export_tflite.py
```

To swap the model, replace `ecosort.tflite`, `labels.txt` and `category_map.json`. No code changes are needed.
