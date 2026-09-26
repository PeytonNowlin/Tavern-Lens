#!/usr/bin/env python3
"""Import allowlisted public guide fields from a local HSReplay capture directory.

Usage: python3 scripts/import-hsreplay-comps.py HSreplayresearch/comps --captured-at YYYY-MM-DD
Only documented guide content is retained; raw pages/account state never enter the bundle.
An incomplete collection or unresolved shape fails before replacing the last good snapshot.
"""
import argparse
import datetime
import json
import re
from pathlib import Path

FIELDS = (
    'comp_id', 'comp_name', 'comp_slug', 'comp_tier', 'comp_difficulty',
    'comp_core_cards', 'comp_addon_cards', 'comp_last_updated', 'comp_tier_last_updated',
)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('capture', type=Path)
    parser.add_argument('--captured-at', required=True, type=datetime.date.fromisoformat)
    parser.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] /
                        'Sources/HSData/Resources/bg-pool/builds/hsreplay-comps.json')
    args = parser.parse_args()
    index = json.loads((args.capture / 'index/raw/react_context.json').read_text())['comps']
    expected = {row['comp_id'] for row in index}
    rows = {}
    for path in sorted((args.capture / 'detail').glob('*/raw/react_context.json')):
        raw = json.loads(path.read_text())
        row = {key: raw.get(key) for key in FIELDS}
        if type(row['comp_id']) is not int or row['comp_id'] <= 0:
            raise ValueError(f"Invalid comp ID: {path}")
        for key in ('comp_name', 'comp_slug'):
            if not isinstance(row[key], str) or not row[key].strip():
                raise ValueError(f"Invalid string: {path} {key}")
        if not re.fullmatch(r'[a-z0-9-]+', row['comp_slug']):
            raise ValueError(f"Invalid comp slug: {path}")
        for key in ('comp_tier', 'comp_difficulty'):
            if row[key] is not None and (type(row[key]) is not int or row[key] not in range(1, 5)):
                raise ValueError(f"Invalid enum: {path} {key}")
        for key in ('comp_last_updated', 'comp_tier_last_updated'):
            if row[key] is not None:
                if not isinstance(row[key], str):
                    raise ValueError(f"Invalid timestamp: {path} {key}")
                datetime.datetime.fromisoformat(row[key].replace('Z', '+00:00'))
        if row['comp_id'] in rows:
            raise ValueError(f"Duplicate guide: {row['comp_id']}")
        for key in ('comp_core_cards', 'comp_addon_cards'):
            if not isinstance(row[key], list) or any(type(value) is not int for value in row[key]):
                raise ValueError(f"Invalid card IDs: {path} {key}")
        if not row['comp_core_cards'] or not row['comp_name'] or not row['comp_slug']:
            raise ValueError(f"Incomplete guide: {path}")
        rows[row['comp_id']] = row
    if set(rows) != expected or not expected:
        raise ValueError(f"Index/detail mismatch: missing {expected - set(rows)}, extra {set(rows) - expected}")
    data = json.dumps({'capturedAt': args.captured_at.isoformat(),
                       'comps': sorted(rows.values(), key=lambda row: row['comp_id'])}, indent=2) + '\n'
    temporary = args.output.with_suffix('.tmp')
    temporary.write_text(data)
    temporary.replace(args.output)
    print(f"Imported {len(rows)} public guides into {args.output}")


if __name__ == '__main__':
    main()
