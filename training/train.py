"""Trains the EcoSort YOLO detector on the dataset from build_dataset.py.

  python train.py                       # yolov8n, 640px, 100 epochs
  python train.py --model yolo11n.pt --epochs 150 --device 0

A free Kaggle / Colab GPU finishes 100 epochs in roughly 1–2 hours.
"""
import argparse
import pathlib

from ultralytics import YOLO

HERE = pathlib.Path(__file__).resolve().parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="yolov8n.pt")
    ap.add_argument("--epochs", type=int, default=100)
    ap.add_argument("--imgsz", type=int, default=640)
    ap.add_argument("--batch", type=int, default=32)
    ap.add_argument("--device", default=None)
    args = ap.parse_args()

    model = YOLO(args.model)
    model.train(
        data=str(HERE / "data" / "ecosort.yaml"),
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        device=args.device,
        project=str(HERE / "runs"),
        name="ecosort",
        exist_ok=True,
        patience=25,
        # Augmentations that matter for trash photos.
        hsv_h=0.015, hsv_s=0.6, hsv_v=0.4,
        degrees=10, fliplr=0.5, flipud=0.1,
        mosaic=1.0, mixup=0.1, close_mosaic=10,
    )
    metrics = model.val()
    print(f"mAP50={metrics.box.map50:.3f}  mAP50-95={metrics.box.map:.3f}")
    print(f"Best weights: {HERE / 'runs/ecosort/weights/best.pt'}  — next: python export_tflite.py")


if __name__ == "__main__":
    main()
