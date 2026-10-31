"""CLIP ONNX 모델 파일을 app/assets/clip/ 에 내려받는다. (레포에는 커밋하지 않음)

사용: python tools/fetch_models.py            # q8(내장용)만
      python tools/fetch_models.py --big      # 온라인용 큰 모델도 (서버 업로드용, 앱에는 내장하지 않음)
표준 라이브러리만 사용. Python 3.x 아무 버전.
"""
from __future__ import annotations

import argparse
import sys
import urllib.request
from pathlib import Path

REPO = "https://huggingface.co/Xenova/clip-vit-base-patch32/resolve/main/onnx/"
FILES = {
    "vision_q8.onnx": REPO + "vision_model_quantized.onnx",
    # 큰 모델: fp16 파일이 레포에 있으면 그 이름으로 바꿀 것 (서준 확인)
    "vision_big.onnx": REPO + "vision_model.onnx",
}
DEST = Path(__file__).resolve().parent.parent / "app" / "assets" / "clip"


def download(url: str, dest: Path) -> None:
    if dest.exists() and dest.stat().st_size > 1_000_000:
        print(f"skip (exists) {dest.name}")
        return
    print(f"downloading {dest.name} ...")

    def hook(blocks: int, block_size: int, total: int) -> None:
        if total > 0:
            done = min(blocks * block_size, total)
            sys.stdout.write(f"\r  {done / 1e6:7.1f} / {total / 1e6:7.1f} MB")
            sys.stdout.flush()

    tmp = dest.with_suffix(".part")
    urllib.request.urlretrieve(url, tmp, hook)
    tmp.rename(dest)
    print(f"\n  saved {dest} ({dest.stat().st_size / 1e6:.1f} MB)")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--big", action="store_true", help="온라인용 큰 모델도 받기")
    args = parser.parse_args()
    DEST.mkdir(parents=True, exist_ok=True)
    download(FILES["vision_q8.onnx"], DEST / "vision_q8.onnx")
    if args.big:
        download(FILES["vision_big.onnx"], DEST / "vision_big.onnx")


if __name__ == "__main__":
    main()
