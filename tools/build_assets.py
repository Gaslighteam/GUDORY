"""Generate aggregate recommendation data, or run the verified pose-only path."""
from __future__ import annotations

import sys

from pose_analysis import main as pose_main


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    if "--pose-only" in args:
        args.remove("--pose-only")
        return pose_main(args)
    from recommendation_pipeline import main as build_main
    return build_main(args)


if __name__ == "__main__":
    main()
