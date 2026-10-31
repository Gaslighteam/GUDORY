# tools/ — data pipeline (written by Seojun, run by Bomin)

| File | Role |
|---|---|
| `fetch_models.py` | Downloads CLIP ONNX models into `app/assets/clip/` (stdlib only, anyone can run it) |
| `build_assets.py` | (Seojun) `data/photos` + `data/labels.csv` → `app/assets/clip/keywords.json`, `app/assets/compositions.json`, `tools/report.md` |

## Environment (Python 3.12, pinned)
```bash
cd tools
uv venv --python 3.12
uv pip install transformers torch pillow numpy pandas mediapipe   # if mediapipe fails: ultralytics
```

## Run
```bash
uv run build_assets.py --photos ../data/photos --labels ../data/labels.csv --out ../app/assets
```
When it finishes, post the per-category counts and top-1 accuracy from `report.md` in the team chat.

## Rules
- Same checkpoint as the app's ONNX (`openai/clip-vit-base-patch32`)
- Preprocessing identical to AGENTS.md §5
- Output JSON formats as in AGENTS.md §4 "Asset formats"
