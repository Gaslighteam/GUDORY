"""Unsplash Lite → 1인 인물 사진 후보 목록 (+ 선택: 이미지 다운로드)

사용 (레포 루트에서):
  python tools/unsplash_candidates.py --lite data/unsplash/raw
  python tools/unsplash_candidates.py --lite data/unsplash/raw --download 3000

출력
  data/unsplash/candidates.csv   후보 전체 (URL, 작가, 키워드). 커밋 금지 (데이터셋 재배포 금지)
  data/photos/unsplash/<id>.jpg  --download 시 짧은 변 640px로 받은 이미지. 커밋 금지

라벨 파일은 없다. 가로/세로는 이미지 크기로, 1인·전신 여부는 build_assets.py(서준)가 포즈 인식으로 판단한다.
보민은 data/photos/unsplash/ 를 훑어보고 구도가 나쁜 사진을 지우기만 하면 된다.
표준 라이브러리만 사용.
"""
from __future__ import annotations

import argparse
import csv
import sys
import urllib.request
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
csv.field_size_limit(10_000_000)

PERSON = {"person", "woman", "man", "girl", "boy", "lady", "guy", "human", "model", "portrait", "female", "male"}
# 2명 이상이거나 사진이 아닌 것
EXCLUDE = {
    "people", "group", "crowd", "couple", "family", "friends", "team", "wedding", "kids", "children",
    "illustration", "drawing", "3d", "render", "text", "poster", "mannequin", "statue", "sculpture",
}
MIN_CONF = 40.0  # ai_service_1_confidence 하한 (0~100)


def read_tsv(lite: Path, stem: str):
    files = sorted(lite.rglob(f"{stem}.tsv*"))
    if not files:
        sys.exit(f"{stem}.tsv* 파일이 {lite} 에 없습니다")
    for f in files:
        with f.open(encoding="utf-8", newline="") as fh:
            yield from csv.DictReader(fh, delimiter="\t", quoting=csv.QUOTE_NONE)


def keywords_by_photo(lite: Path) -> dict[str, set[str]]:
    out: dict[str, set[str]] = defaultdict(set)
    for r in read_tsv(lite, "keywords"):
        conf = r.get("ai_service_1_confidence") or ""
        by_user = r.get("suggested_by_user") == "t"
        try:
            confident = bool(conf) and float(conf) >= MIN_CONF
        except ValueError:
            confident = False
        if by_user or confident:
            out[r["photo_id"]].add(r["keyword"].strip().lower())
    return out


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--lite", type=Path, default=ROOT / "data/unsplash/raw")
    p.add_argument("--out", type=Path, default=ROOT / "data/unsplash/candidates.csv")
    p.add_argument("--download", type=int, default=0, help="인기순으로 N장 다운로드 (0 = 안 함)")
    p.add_argument("--photos", type=Path, default=ROOT / "data/photos/unsplash")
    args = p.parse_args()

    kw = keywords_by_photo(args.lite)
    rows = []
    for r in read_tsv(args.lite, "photos"):
        words = kw.get(r["photo_id"], set())
        desc = f"{r.get('ai_description') or ''} {r.get('photo_description') or ''}".lower().split()
        if not (words & PERSON or PERSON.intersection(desc)):
            continue
        if words & EXCLUDE:
            continue
        w, h = int(r["photo_width"] or 0), int(r["photo_height"] or 0)
        if not w or not h or 0.9 <= w / h <= 1.1:
            continue  # 정사각형에 가까운 사진은 제외
        rows.append({
            "photo_id": r["photo_id"],
            "orientation": "portrait" if h > w else "landscape",
            "width": w, "height": h,
            "image_url": r["photo_image_url"],
            "photographer": r["photographer_username"],
            "downloads": int(r.get("stats_downloads") or 0),
            "keywords": ";".join(sorted(words)),
        })
    if not rows:
        sys.exit("후보가 0장입니다. 키워드 조건을 확인하세요")
    rows.sort(key=lambda x: -x["downloads"])  # 인기 사진 = 대체로 잘 찍은 사진부터

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", encoding="utf-8", newline="") as fh:
        wr = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        wr.writeheader()
        wr.writerows(rows)
    portrait = sum(r["orientation"] == "portrait" for r in rows)
    print(f"후보 {len(rows)}장 (세로 {portrait} / 가로 {len(rows) - portrait}) → {args.out}")

    if not args.download:
        return
    picked = rows[: args.download]
    args.photos.mkdir(parents=True, exist_ok=True)

    def fetch(r: dict) -> bool:
        dest = args.photos / f"{r['photo_id']}.jpg"
        if dest.exists():
            return True
        side = "w" if r["orientation"] == "portrait" else "h"
        try:
            urllib.request.urlretrieve(f"{r['image_url']}?{side}=640&q=80&fm=jpg", dest)
            return True
        except Exception as e:  # noqa: BLE001 — 실패한 사진은 건너뜀
            print(f"  실패 {r['photo_id']}: {e}")
            return False

    with ThreadPoolExecutor(8) as ex:
        ok = sum(ex.map(fetch, picked))
    print(f"다운로드 {ok}/{len(picked)} → {args.photos}")


if __name__ == "__main__":
    main()
