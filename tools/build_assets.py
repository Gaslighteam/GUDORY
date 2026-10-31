"""Pose-only milestone entry point; no CLIP or recommendation asset generation."""
from __future__ import annotations

import argparse
import sys

from pose_analysis import main as pose_main


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    if "--pose-only" not in args:
        argparse.ArgumentParser(description=__doc__).error(
            "Only --pose-only is implemented in this milestone")
    args.remove("--pose-only")
    return pose_main(args)


if __name__ == "__main__":
    main()
