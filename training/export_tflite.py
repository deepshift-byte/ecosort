"""Exports a trained YOLO model to TensorFlow Lite and installs it in the app.

  python export_tflite.py                                   # trained 7-class model
  python export_tflite.py --weights yolov8n.pt --coco       # COCO bootstrap model
  python export_tflite.py --int8                            # smaller/faster, needs dataset for calibration

Writes:
  assets/models/ecosort.tflite        float32 in/out, [1,S,S,3] -> [1,4+C,N]
  assets/models/labels.txt            one class name per line
  assets/models/category_map.json     class name -> category id
"""
import argparse
import json
import pathlib
import shutil

from ultralytics import YOLO

from datasets import CLASSES

HERE = pathlib.Path(__file__).resolve().parent
ASSETS = HERE.parent / "assets" / "models"

# COCO class -> EcoSort category, for the pretrained bootstrap model.
COCO_MAP = {
    "bottle": "plastic",
    "cup": "plastic",
    "wine glass": "glass",
    "fork": "metal",
    "knife": "metal",
    "spoon": "metal",
    "scissors": "metal",
    "bowl": "plastic",
    "banana": "organic",
    "apple": "organic",
    "orange": "organic",
    "broccoli": "organic",
    "carrot": "organic",
    "sandwich": "organic",
    "hot dog": "organic",
    "pizza": "organic",
    "donut": "organic",
    "cake": "organic",
    "potted plant": "organic",
    "book": "paper",
    "cell phone": "ewaste",
    "laptop": "ewaste",
    "remote": "ewaste",
    "keyboard": "ewaste",
    "mouse": "ewaste",
    "tv": "ewaste",
    "microwave": "ewaste",
    "toaster": "ewaste",
    "hair drier": "ewaste",
    "clock": "ewaste",
    "toothbrush": "plastic",
}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--weights", default=str(HERE / "runs/ecosort/weights/best.pt"))
    ap.add_argument("--imgsz", type=int, default=320,
                    help="320 for real-time on mid-range phones, 640 for best accuracy")
    ap.add_argument("--coco", action="store_true", help="weights are a COCO-pretrained model")
    ap.add_argument("--int8", action="store_true")
    args = ap.parse_args()

    model = YOLO(args.weights)
    names = [model.names[i] for i in range(len(model.names))]
    kwargs = dict(format="tflite", imgsz=args.imgsz, nms=False)
    if args.int8:
        kwargs.update(int8=True, data=str(HERE / "data" / "ecosort.yaml"))
    # Default: float32 weights and I/O (≈12 MB for yolov8n). Older Ultralytics
    # versions also accept half=True for fp16 (≈6 MB).
    out = pathlib.Path(model.export(**kwargs))
    # Ultralytics returns the saved_model dir or the .tflite path depending on version.
    if out.is_dir():
        files = sorted(out.rglob("*.tflite"))
        pick = [p for p in files if ("int8" in p.name) == args.int8]
        out = (pick or files)[0]

    ASSETS.mkdir(parents=True, exist_ok=True)
    shutil.copy(out, ASSETS / "ecosort.tflite")
    (ASSETS / "labels.txt").write_text("\n".join(names) + "\n")
    if args.coco:
        cmap = {n: COCO_MAP[n] for n in names if n in COCO_MAP}
    else:
        assert set(names) <= set(CLASSES), f"unexpected classes {names}"
        cmap = {n: n for n in names}
    (ASSETS / "category_map.json").write_text(json.dumps(cmap, indent=1))
    size_mb = (ASSETS / "ecosort.tflite").stat().st_size / 1e6
    print(f"Installed {out.name} ({size_mb:.1f} MB, {len(names)} classes, {args.imgsz}px) -> {ASSETS}")


if __name__ == "__main__":
    main()
