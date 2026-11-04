# EcoSort — Project Plan

EcoSort is a mobile app that sorts waste into **seven categories** by pointing
the phone camera at items. Every detected object gets a colour-coded outline
and a small label chip ("Plastic", "Hazardous", …). Users can also snap or
upload a photo, or upload a short video, and get a full breakdown of every
item found. All recognition runs **on-device** using a locally trained model.

---

## 1. Key decisions

| Decision | Choice | Why |
|---|---|---|
| App framework | **Flutter 3 (Dart)** | One codebase for Android + iOS, fast camera/canvas rendering, mature on-device ML plugins. |
| ML model file format | **TensorFlow Lite (`.tflite`)** | Runs fully offline on Android & iOS, GPU/NNAPI/CoreML delegates, small (≈3–6 MB for YOLOv8n fp16), supported by `tflite_flutter`. |
| Model architecture | **YOLOv8n object detector** (Ultralytics), 320×320 or 640×640 input | Detection (not just classification) is required to draw an outline around *each* item. `n` size keeps live FPS high on mid-range phones. |
| Labels | `assets/models/labels.txt` + `assets/models/category_map.json` | Decouples model class names from the 7 app categories, so you can swap models without code changes. |
| Time-based API | **WorldTimeAPI** (`worldtimeapi.org`), fallback **TimeAPI.io**, final fallback device clock | Trusted, timezone-aware timestamps for scan history, daily streaks and the "next collection day" countdown — immune to wrong device clocks. |
| Local storage | `shared_preferences` (JSON) | Scan history and settings; tiny and dependency-free. |
| Design | Material 3, custom eco palette, light + dark | See §5. |

## 2. The seven categories

| # | Category | Colour | Examples | Disposal hint |
|---|---|---|---|---|
| 1 | **Plastic** | Yellow `#F5C518` | bottles, bags, cups, wrappers | Rinse, squash, yellow/plastics bin |
| 2 | **Paper & Cardboard** | Blue `#2D9CDB` | boxes, newspaper, books | Keep dry, flatten boxes |
| 3 | **Glass** | Green `#27AE60` | jars, wine glasses, bottles | Remove lids, bottle bank |
| 4 | **Metal** | Orange `#F2994A` | cans, foil, cutlery | Rinse, metals bin |
| 5 | **Organic** | Brown `#B7794A` | food scraps, fruit, peels | Compost / green bin |
| 6 | **E-waste** | Purple `#9B51E0` | phones, cables, laptops, remotes | E-waste drop-off point |
| 7 | **Hazardous** | Red `#EB5757` | batteries, paint, chemicals, bulbs, syringes | Never in household bins — hazardous collection |

## 3. Features

1. **Live Scan** – camera preview, real-time detection on a background
   isolate, rounded colour outlines + label chips + confidence, FPS-throttled.
   Tap a box for disposal tips. Pause/flash/switch-camera controls.
2. **Photo** – capture with camera or pick from gallery → full-resolution
   detection → annotated image + per-item list + category totals.
3. **Video** – pick a short clip (≤ 60 s) → sample frames every N ms →
   detect on each frame → a lightweight IoU tracker merges the same item across
   frames → summary of *unique* items per category + per-frame scrubber.
4. **History** – every scan saved with a network-verified timestamp and its
   category counts; stats (items sorted, per-category bars, daily streak).
5. **Guide** – the 7 categories, colours, examples, disposal tips.
6. **Ask EcoSort (type or speak)** – describe trash in words ("old phone
   charger and banana peels") by keyboard or microphone (`speech_to_text`,
   on-device recogniser). An offline knowledge base (~56 items, 300+ aliases,
   typo-tolerant matching, several items per sentence) returns the category,
   how to handle it, and where to put it.
7. **Settings** – confidence threshold, collection weekday (drives the
   time-API countdown), use-GPU toggle, clear history.

## 4. Architecture

```
lib/
  main.dart                    App bootstrap, theme, providers
  app/theme.dart               Palette, typography, light/dark themes
  models/
    waste_category.dart        The 7 categories (colour, icon, tips)
    detection.dart             Bounding box + class + score
    scan_record.dart           History entry (JSON)
  services/
    waste_advisor.dart         Offline text/voice → category, handling, bin
    detector_service.dart      Loads .tflite, preprocess, inference, YOLO decode, NMS
    image_utils.dart           CameraImage(YUV420/BGRA) → RGB, letterbox resize
    video_analyzer.dart        Frame sampling + cross-frame IoU tracking
    time_service.dart          WorldTimeAPI / TimeAPI.io / device fallback
    history_service.dart       Persist scans (shared_preferences)
    settings_service.dart      User preferences
  widgets/
    detection_painter.dart     CustomPainter: colour outlines + label chips
    category_chip.dart, stat_card.dart, …
  screens/
    home_screen.dart           Dashboard: greeting (time API), next-collection countdown, actions
    live_scan_screen.dart      Real-time camera detection
    photo_result_screen.dart   Annotated photo results
    video_result_screen.dart   Video analysis & unique-item summary
    history_screen.dart, guide_screen.dart, settings_screen.dart
training/                      Python pipeline that produces the .tflite
  data/ecosort.yaml            7-class dataset spec
  datasets.py                  Kaggle dataset list + class → category mapping
  download_kaggle.py           Fetch datasets with kagglehub (or link_kaggle_inputs.py on Kaggle)
  build_dataset.py             Build the 7-class YOLO dataset
  train.py                     Train YOLOv8n / YOLO11n
  export_tflite.py             Export → .tflite + labels.txt + category_map.json into app assets
                               (--coco exports the pretrained bootstrap model)
```

### Detection pipeline
1. Frame (camera YUV420 / file bytes) → RGB → letterbox to model input size.
2. `float32[1,H,W,3]` (or NCHW `[1,3,H,W]`, auto-detected) normalised 0–1 → interpreter (in an isolate via `IsolateInterpreter`).
3. Output `[1, 4 + C, N]` (YOLOv8) → transpose → score = max class prob →
   threshold → xywh→xyxy → class-wise NMS (IoU 0.45) → undo letterbox.
4. Class index → label → `category_map.json` → `WasteCategory`. Labels not in
   the map are ignored (lets the COCO bootstrap model ignore people, cars, …).

### Video pipeline
Frames sampled with `video_thumbnail` at a fixed interval → detector → tracker
(greedy IoU ≥ 0.3, same category, max 3 missed frames) → unique track count
per category. A track must be seen in ≥ 2 frames (or once for clips with few
frames) to count, filtering flicker.

### Time API integration
`TimeService.now()` calls `https://worldtimeapi.org/api/ip` (timezone from the
user's IP) and falls back to `https://timeapi.io/api/time/current/zone`, then
the device clock. The offset between server and device time is cached so later
calls are instant. Used for: scan timestamps, "Good morning" greeting,
daily streak, and countdown to the user's weekly collection day.

## 5. Visual design
- Primary: deep eco green `#0F766E` → mint `#34D399` gradient; surfaces off-white
  `#F6FBF8` (light) / `#0B1512` (dark).
- Category colours above are used for outlines, chips, bars — all chosen for
  contrast on busy camera backgrounds (outline has a dark 1 px halo).
- Rounded 20 px cards, soft shadows, Google *Poppins*-style geometric type
  (bundled via the `google_fonts` package), animated scan reticle.

## 6. Model training plan
1. **Data (Kaggle)**: `kneroma/tacotrashdataset` (TACO, real boxes),
   `sumn2u/garbage-classification-v2`, `mostafaabla/garbage-classification`,
   `joebeachcapital/realwaste`, `akshat103/e-waste-image-dataset`. Every source
   class is remapped to the 7 categories (`training/datasets.py`). Single-item
   classification photos become one box each (`training/build_dataset.py`).
   Aim for ≥ 500 boxes per category; hazardous and e-waste need deliberate
   collection (batteries, bulbs, spray cans, cables).
2. **Train**: `yolo detect train model=yolov8n.pt data=ecosort.yaml imgsz=640 epochs=100`
   with mosaic/HSV augmentation. Target mAP50 ≥ 0.6.
3. **Export**: `format=tflite` (fp16; int8 with calibration for low-end phones).
4. **Ship**: copy `best_float16.tflite` → `assets/models/ecosort.tflite`, write
   `labels.txt`, set `category_map.json` to identity. No code changes.

Until a custom model is trained, the app ships with **a pretrained COCO YOLOv8n**
exported to `.tflite`, and a COCO→category map (bottle→Plastic, cup→Plastic,
wine glass→Glass, fork/knife/spoon→Metal, banana/apple/…→Organic,
cell phone/laptop/remote/keyboard/mouse/tv→E-waste, book→Paper, …). It already
works end-to-end; the custom 7-class model improves coverage (bags, cans,
batteries, cardboard).

## 7. Milestones
1. Project scaffold, theme, categories, navigation.
2. Detector service + painter; photo flow.
3. Live camera flow (streaming, isolate, throttling).
4. Video flow + tracker.
5. Time API, history, stats, settings.
6. Training & export pipeline; bootstrap model.
7. Static analysis + unit tests (decoder/NMS, tracker, time fallback).

## 8. Risks
- **Accuracy** of the bootstrap COCO model on trash is limited → custom training (§6).
- **Hazardous misses** are costly → low threshold for hazardous class and an
  "always check local rules" note.
- **Performance** on low-end Android → 320 input, int8 model, frame skipping.
- **Time API outages** → two providers + device-clock fallback.
