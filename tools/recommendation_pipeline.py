"""Offline orchestration; only aggregate JSON/report files are written."""
import argparse
from collections import Counter
from contextlib import ExitStack
import hashlib
import importlib.metadata
from pathlib import Path
import sys

from background_clip import ClipEncoder, SelfieSegmenter, SegmentationFailure, background_embedding
from import_photos import IMAGE_EXTENSIONS
from pose_analysis import MediaPipePhotoAnalyzer, center_crop_rect, load_photo
from recommendation_assets import Sample, build_asset, serialize_asset
from aggregate_baseline import load_baseline, compare_baseline


def collect_samples(root, pose, segmenter, encoder, team_weight=3, supplementary_weight=1):
    counts = Counter()
    samples = []
    root = root.resolve()
    for path in sorted(root.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in IMAGE_EXTENSIONS:
            continue
        counts["processed"] += 1
        if path.is_symlink() or not path.resolve().is_relative_to(root):
            counts["rejected/unsafe_path"] += 1
            continue
        result = pose.analyze(path)
        counts[f"source_orientation/{result.source_orientation or 'undecodable'}"] += 1
        if not result.accepted:
            counts[f"rejected/pose/{result.reason}"] += 1
            continue
        counts["pose_accepted"] += 1
        try:
            with load_photo(path) as image:
                if result.crop in ("portrait_3_4", "landscape_4_3"):
                    rect = center_crop_rect(image.width, image.height, result.crop == "portrait_3_4")
                    shot = image.crop(rect)
                else:
                    shot = image.copy()
                with shot:
                    vector = background_embedding(shot, segmenter, encoder)
        except SegmentationFailure:
            counts["rejected/segmentation"] += 1
            continue
        except Exception:
            counts["rejected/embedding_or_image"] += 1
            continue
        relative = path.relative_to(root)
        is_team = relative.parts[0] == "team" or root.name == "team" or root.parent.name == "team"
        weight = team_weight if is_team else supplementary_weight
        samples.append(Sample(result.orientation, result.composition, vector, weight))
        counts["accepted"] += 1
        counts["accepted_source/team" if is_team else "accepted_source/supplementary"] += 1
        if counts["processed"] % 50 == 0:
            print(f"Processed {counts['processed']}; embedded {counts['accepted']}", file=sys.stderr, flush=True)
    counts["rejected"] = counts["processed"] - counts["accepted"]
    return samples, counts


def render_report(counts, diagnostics, size, team_weight, supplementary_weight, metadata=None):
    lines = ["# Recommendation data-generation report", "",
        "Aggregate output only. No photo names, IDs, paths, measurements or per-photo embeddings.", "",
        f"Processed: {counts['processed']}; pose accepted: {counts['pose_accepted']}; "
        f"background embeddings accepted: {counts['accepted']}; rejected: {counts['rejected']}.",
        f"Source weights: team {team_weight:g}; supplementary {supplementary_weight:g}.",
        f"recommend.json: {size:,} bytes (limit < 1,000,000 bytes).", "",
        "## Filters and source counts", "", "Aggregate | Count", "--- | ---:"]
    lines += [f"{key} | {value}" for key, value in sorted(counts.items())]
    for orientation, info in diagnostics.items():
        lines += ["", f"## {orientation}", "",
            f"Photos: {info['photos']}; weighted mass: {info['weight']:g}; "
            f"exported clusters: {info['clusters']}; clusters without supported levels omitted: {info['omitted_clusters']}.",
            "", "Level | Photos | Weighted mass | chestUp | waistUp | kneeUp | fullBody",
            "--- | ---: | ---: | ---: | ---: | ---: | ---:"]
        for level, data in info["levels"].items():
            fs = data["framings"]
            lines.append(f"{level} | {data['count']} | {data['weight']:g} | " +
                         " | ".join(str(fs.get(f, 0)) for f in ("chestUp", "waistUp", "kneeUp", "fullBody")))
        lines += ["", "Cluster size (actual photos) | Number of clusters", "--- | ---:"]
        lines += [f"{n} | {count}" for n, count in info["cluster_sizes"].items()]
        lines += ["", "Fallback target level | Levels pooled (nearest first)", "--- | ---"]
        lines += [f"{lv} | {', '.join(map(str, levels))}" for lv, levels in info["fallback_pooled_levels"].items()]
    lines += ["", "## Definitions and limitations", "",
        "- Uses the verified pose pipeline and original-frame person-count evidence; near-square shot crops are recomputed from the same centre-crop rectangle.",
        "- Person confidence >= 0.5 is filled with the rounded RGB mean of the whole shot before CLIP preprocessing. Missing/invalid/empty/full masks reject the photo, never fall back to an unmasked embedding.",
        "- CLIP: verified local ViT-B/32 q8 ONNX, RGB short-side 224 bicubic resize, integer centre crop 224x224, float32 NCHW, exact AGENTS.md mean/std; L2-normalized finite 512-vectors.",
        "- Pillow and Dart bicubic interpolation implementations may differ on natural images. End-to-end pixel/embedding parity and recommendation quality on Android remain unverified.",
        "- Weighted quintiles use inverse empirical CDF at 0.8/0.6/0.4/0.2. Equal scales stay together; empty levels borrow the nearest levels within the same orientation until the dominant framing has at least three contributors.",
        "- Levels rank head-to-shoulder scale s, not raw span h. Spans measured to different framing anchors are not comparable and are not forced to be monotonic across framing changes.",
        "- Dominant framing uses source-weight mass; ties use chestUp, waistUp, kneeUp, fullBody order. All medians use source weights and only that framing's photos. No span mixing across framings.",
        "- K-means uses source weights, seed 0, n_init=10, Lloyd and one numerical-library thread. Target k=min(64,max(1,floor(actual photos/20)),distinct vectors). Groups with fewer than three photos merge into the nearest centre. The approximately-20 target is an average, not a per-cluster minimum.",
        "- Cluster n is actual photos. Per-level n is actual dominant-framing contributors; levels with fewer than three are omitted. No individual-photo centre is exported; unsupported clusters are omitted.",
        "- Centres are L2-normalized, rounded after scaling by 127, int8 and base64 encoded. Dequantized centres should be renormalized before cosine comparison.",
        "- No per-photo caches are written. Missing orientations/insufficient aggregate support or model setup errors abort generation before replacing the prior asset.",
        "- Human accuracy/consent/attribution review and Dart consumer verification remain required. No training photos leave this PC; only aggregated assets and this report are outputs.", ""]
    if metadata:
        lines += ["## Runtime and model provenance", "", "Component | Version or SHA-256", "--- | ---"]
        lines += [f"{key} | {value}" for key, value in sorted(metadata.items())]
        lines += ["", "Model hashes identify local model files, never individual training photos.", ""]
    return "\n".join(lines)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--photos", type=Path, required=True)
    parser.add_argument("--pose-model", type=Path, required=True)
    parser.add_argument("--person-model", type=Path, required=True)
    parser.add_argument("--segmentation-model", type=Path, required=True)
    parser.add_argument("--clip-model", type=Path, required=True)
    parser.add_argument("--out", type=Path, default=Path("app/assets/recommend.json"))
    parser.add_argument("--report", type=Path, default=Path("tools/report.md"))
    parser.add_argument("--team-weight", type=float, default=3)
    parser.add_argument("--supplementary-weight", type=float, default=1)
    parser.add_argument("--baseline", type=Path, default=Path(__file__).with_name("recommendation_baseline.json"),
                        help="Aggregate-only baseline used for report comparison, never training")
    parser.add_argument("--layout-out", type=Path, default=None,
                        help="Optional aggregate composition prototypes; legacy JSON stays unchanged")
    args = parser.parse_args(argv)
    import math
    if not args.photos.is_dir() or not all(math.isfinite(w) and w > 0 for w in (args.team_weight, args.supplementary_weight)):
        parser.error("Require a photo directory and positive finite source weights")
    baseline = load_baseline(args.baseline)
    with ExitStack() as stack:
        pose = MediaPipePhotoAnalyzer(args.pose_model, args.person_model)
        stack.callback(pose.close)
        segmenter = SelfieSegmenter(args.segmentation_model)
        stack.callback(segmenter.close)
        encoder = ClipEncoder(args.clip_model)
        samples, counts = collect_samples(args.photos, pose, segmenter, encoder,
                                         args.team_weight, args.supplementary_weight)
    asset, diagnostics = build_asset(samples)
    payload = serialize_asset(asset)
    layout_payload = None
    if args.layout_out is not None:
        from layout_prototypes import build_layout_asset, serialize_layout_asset
        layout_payload = serialize_layout_asset(build_layout_asset(samples, asset), asset)
        if args.layout_out.resolve() in (args.out.resolve(), args.report.resolve()):
            parser.error("Layout output must not overwrite the legacy asset or report")
    metadata = {name: importlib.metadata.version(name) for name in
                ("numpy", "pillow", "mediapipe", "onnxruntime", "scikit-learn")}
    metadata["Python"] = sys.version.split()[0]
    for name, path in (("CLIP model", args.clip_model), ("Pose model", args.pose_model),
                       ("Person detector model", args.person_model), ("Segmentation model", args.segmentation_model)):
        with path.open("rb") as stream:
            metadata[name] = hashlib.file_digest(stream, "sha256").hexdigest()
    report = render_report(counts, diagnostics, len(payload), args.team_weight, args.supplementary_weight, metadata)
    report += "\n" + compare_baseline(baseline, counts, diagnostics, len(payload),
                                     args.team_weight, args.supplementary_weight,
                                     hashlib.sha256(payload).hexdigest())
    if layout_payload is not None:
        report += f"\n## Phase A composition prototypes\n\nOptional aggregate sidecar: {len(layout_payload):,} bytes. Legacy asset schema unchanged.\n"
    # Validate all output before replacing either file; originals are untouched.
    outputs = [(args.out, payload), (args.report, report.encode("utf-8"))]
    if layout_payload is not None:
        outputs.append((args.layout_out, layout_payload))
    for path, data in outputs:
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.with_suffix(path.suffix + ".tmp")
        temporary.write_bytes(data)
        temporary.replace(path)
    print(report)
