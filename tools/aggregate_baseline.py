"""Report-only baseline comparison. Never supplies training statistics."""
import json
import math
import re

METRICS = ("processed", "pose_accepted", "clip_accepted", "portrait_photos",
           "landscape_photos", "portrait_clusters", "landscape_clusters", "json_bytes")


def configuration(team_weight, supplementary_weight):
    return {"team_weight": team_weight, "supplementary_weight": supplementary_weight,
            "cluster_seed": 0, "max_clusters_per_orientation": 64, "target_photos_per_cluster": 20}


def load_baseline(path):
    value = json.loads(path.read_text(encoding="utf-8"))
    if (set(value) != {"version", "configuration", "metrics", "asset_sha256"}
            or type(value["version"]) is not int or value["version"] != 1
            or set(value["metrics"]) != set(METRICS)
            or set(value["configuration"]) != set(configuration(3, 1))
            or not isinstance(value["asset_sha256"], str)
            or not re.fullmatch(r"[0-9a-f]{64}", value["asset_sha256"])):
        raise ValueError("Invalid aggregate-only baseline schema")
    if any(type(n) is not int or n < 0 for n in value["metrics"].values()):
        raise ValueError("Invalid baseline metric")
    if any(isinstance(n, bool) or not isinstance(n, (int, float)) or not math.isfinite(n) or n < 0
           for n in value["configuration"].values()):
        raise ValueError("Invalid baseline configuration")
    return value


def compare_baseline(baseline, counts, diagnostics, size, team_weight, supplementary_weight, asset_hash):
    metrics = {"processed": counts["processed"], "pose_accepted": counts["pose_accepted"],
               "clip_accepted": counts["accepted"], "json_bytes": size}
    for o in ("portrait", "landscape"):
        metrics[f"{o}_photos"] = diagnostics[o]["photos"]
        metrics[f"{o}_clusters"] = diagnostics[o]["clusters"]
    lines = ["## Provisional asset and fixed baseline comparison", "",
             "recommend.json is provisional and may be regenerated when more photos arrive.",
             "Every run recursively discovers the full photo input and recomputes pose statistics,",
             "embeddings, boundaries, clusters and fallbacks from scratch. Prior JSON/report",
             "statistics are never loaded as training input. This baseline is read only for reporting.", "",
             "Metric | Fixed baseline | Current | Change", "--- | ---: | ---: | ---:"]
    for key in METRICS:
        current, original = metrics[key], baseline["metrics"][key]
        lines.append(f"{key} | {original} | {current} | {current - original:+d}")
    same_config = baseline["configuration"] == configuration(team_weight, supplementary_weight)
    lines += ["", f"Configuration matches fixed baseline: {'yes' if same_config else 'no; changes may reflect configuration as well as data'}.",
              f"Aggregate asset SHA-256 matches fixed baseline: {'yes' if asset_hash == baseline['asset_sha256'] else 'no'}.",
              "The fixed baseline is never overwritten automatically. No photo IDs or per-photo history are stored.", ""]
    return "\n".join(lines)
