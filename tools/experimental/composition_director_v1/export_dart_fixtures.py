"""Export ONLY procedural synthetic frames for Python/Dart behavior parity."""
from dataclasses import asdict
import json
from pathlib import Path
from .director import Director
from .fixtures import scene, simulated_context


def main():
    records=[]
    for orientation in ('portrait', 'landscape'):
        for kind in ('diagonal', 'asymmetric', 'symmetric', 'weak'):
            frame=scene(kind,orientation=orientation,x=.3 if kind=='asymmetric' else .5)
            decision=Director().update(frame,simulated_context(frame))
            records.append(dict(name=f'{orientation}/{kind}',frame=asdict(frame),expected=asdict(decision)))
    root=Path(__file__).resolve().parents[3]
    target=root/'app/lib/features/scene/experimental/composition_director_v1/parity_fixtures.json'
    target.write_bytes(json.dumps(records,separators=(',',':'),ensure_ascii=False).encode('utf-8'))
    print(f'Exported {len(records)} synthetic parity fixtures ({target.stat().st_size} bytes)')


if __name__=='__main__':
    main()
