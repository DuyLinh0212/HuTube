"""Freeze historical passing case IDs; never execute tests or rewrite reports."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'coverage/retained-evidence.json'


def main():
    if TARGET.exists():
        raise SystemExit('Baseline already frozen; review additions explicitly instead of replacing it.')
    retained = {}
    for path in sorted((ROOT / 'artifacts/runs').glob('*/report.json')):
        try:
            report = json.loads(path.read_text(encoding='utf-8'))
        except (OSError, ValueError):
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        for case in report.get('cases', []):
            if case.get('status') != 'passed':
                continue
            key = case.get('logical_id', case['id'])
            retained.setdefault(key, []).append({
                'run_id': report.get('run_id', path.parent.name),
                'parent': case.get('parent'),
                'report': path.relative_to(ROOT).as_posix(),
                'report_sha256': digest,
                'screenshots': case.get('screenshots', []),
            })
    TARGET.write_text(json.dumps({'version': 1, 'cases': retained}, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({'retained_case_ids': len(retained), 'path': str(TARGET)}))


if __name__ == '__main__':
    main()
