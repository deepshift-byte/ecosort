"""Inside a Kaggle notebook: point raw/index.json at the attached datasets in
/kaggle/input instead of downloading them."""
import json
import pathlib

from datasets import KAGGLE_DATASETS

HERE = pathlib.Path(__file__).resolve().parent
INPUT = pathlib.Path("/kaggle/input")

index = {}
for slug, (kind, _) in KAGGLE_DATASETS.items():
    name = slug.split("/")[1]
    candidates = [p for p in INPUT.glob("*") if p.name == name] + list(INPUT.glob(f"datasets/*/{name}"))
    if candidates:
        index[slug] = {"kind": kind, "path": str(candidates[0])}
        print(f"✓ {slug} -> {candidates[0]}")
    else:
        print(f"✗ {slug} not attached (Add Input → search '{name}')")
(HERE / "raw").mkdir(exist_ok=True)
(HERE / "raw" / "index.json").write_text(json.dumps(index, indent=2))
