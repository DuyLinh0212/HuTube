"""One-time migration of flat auth screenshots to app/module/flow/case folders."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from support.evidence import auth_relative_path, auth_scope, legacy_case
from support.state import atomic_json


def move_flat(source, target):
    count = 0
    for image in source.glob('*.png'):
        case_id = legacy_case(image.name)
        if not case_id:
            raise ValueError('No case mapping: ' + image.name)
        destination = target / auth_relative_path(case_id, image.name)
        # Verify both absolute paths before any move, including Windows paths.
        if not image.resolve().is_relative_to(ROOT) or not destination.resolve().is_relative_to(ROOT):
            raise ValueError('Screenshot move must stay within e2e_testing.')
        if destination.exists():
            raise FileExistsError('Refuse to overwrite existing screenshot: ' + str(destination))
        destination.parent.mkdir(parents=True, exist_ok=True)
        image.rename(destination)
        count += 1
    return count


def main():
    total = 0
    for run in sorted((ROOT / 'artifacts/runs').iterdir()):
        report_path = run / 'report.json'
        if not report_path.exists():
            continue
        report = json.loads(report_path.read_text(encoding='utf-8'))
        source = Path(report.get('screenshot_dir', str(run / 'screenshots')))
        target = ROOT / 'screenshots' / run.name
        total += move_flat(source, target)
        report['screenshot_dir'] = str(target)
        entries = []
        for image in target.rglob('*.png'):
            case_id = legacy_case(image.name)
            application, module, flow = auth_scope(case_id)
            entries.append({'application': application, 'module': module, 'flow': flow,
                            'case_id': case_id, 'step': image.stem,
                            'path': image.relative_to(target).as_posix()})
        report['screenshots'] = entries
        atomic_json(report_path, report)
    total += move_flat(ROOT / 'screenshots/baseline-auth', ROOT / 'screenshots/baseline-auth')
    print(f'Organized {total} screenshots. Original bytes retained; no files deleted.')


if __name__ == '__main__':
    main()
