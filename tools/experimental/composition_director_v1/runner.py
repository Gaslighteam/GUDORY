"""python -m experimental.composition_director_v1.runner [--benchmark]."""
import argparse
from dataclasses import asdict
import json
import platform
import statistics
import time
import tracemalloc
from .director import Director
from .fixtures import scene, simulated_context
from .types import Context, Frame, Person


def summary(name, decision):
    return {"scene": name, "line_count": len(decision.features.lines),
            "vanishing_point": decision.features.vanishing_point,
            "feature_confidence": round(decision.features.confidence, 3),
            "cells": [asdict(c) for c in decision.features.cells],
            "target": asdict(decision.target) if decision.target else None,
            "action": asdict(decision.action), "progress": decision.progress,
            "target_generation": decision.target_generation}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--benchmark", action="store_true")
    parser.add_argument("--input", help="local JSON frame or sequence; no upload or persistence")
    args = parser.parse_args()
    if args.input:
        with open(args.input, encoding="utf-8-sig") as stream:
            records = json.load(stream)
        if isinstance(records, dict):
            records = [records]
        director = Director()
        for record in records:
            record = dict(record)
            record["person"] = Person(**record["person"]) if record.get("person") else None
            frame = Frame(**record)
            print(json.dumps(summary("local-input", director.update(frame, Context())), ensure_ascii=False))
        return
    for orientation in ("portrait", "landscape"):
        for kind in ("diagonal", "asymmetric", "symmetric", "weak"):
            frame = scene(kind, orientation=orientation, x=.3 if kind == "asymmetric" else .5)
            decision = Director().update(frame, simulated_context(frame))
            print(json.dumps(summary(f"synthetic/{orientation}/{kind}", decision), ensure_ascii=False))
    director = Director()
    first = scene("asymmetric", x=.3)
    before = director.update(first, simulated_context(first))
    if before.action.direction in ("left", "right"):
        sign = 1 if before.action.direction == "right" else -1
        after = scene("asymmetric", at=2., x=first.person.x + sign * .10)
        print(json.dumps(summary("synthetic/after-movement", director.update(after, simulated_context(after))), ensure_ascii=False))
    if args.benchmark:
        frames = [scene(k, orientation=o) for o in ("portrait", "landscape")
                  for k in ("diagonal", "asymmetric", "symmetric", "weak")]
        timings = []
        for _ in range(3):
            for frame in frames:
                Director().update(frame)
        for _ in range(10):
            for frame in frames:
                start = time.perf_counter()
                Director().update(frame)
                timings.append((time.perf_counter() - start) * 1000)
        tracemalloc.start()
        for frame in frames:
            Director().update(frame)
        current, peak = tracemalloc.get_traced_memory()
        tracemalloc.stop()
        print(json.dumps({"benchmark": {"python": platform.python_version(),
              "machine": platform.machine(), "samples": len(timings),
              "median_ms": statistics.median(timings),
              "p95_ms": sorted(timings)[int(.95 * (len(timings) - 1))],
              "max_ms": max(timings), "traced_peak_bytes": peak,
              "traced_remaining_bytes": current,
              "excludes": "image decode, pose, mask, CLIP, camera and Android runtime"}}))


if __name__ == "__main__":
    main()
