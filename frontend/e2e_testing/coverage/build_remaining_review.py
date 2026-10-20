"""Roll up this completion batch without certifying parent coverage from child PASS."""
import argparse
import hashlib
import json
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
FIXED = [
    'FULL-PRIORITY-PLAN-DOWNGRADE-BACKGROUND-DENIED',
    'FULL-PRIORITY-PLAN-EXPIRY-BACKGROUND-DENIED',
    'FULL-PRIORITY-PLAN-EXPIRY-IMMEDIATE-FEATURE-GATE',
]
UNCONFIRMED = [
    'FULL-A-RECOMMENDATION-LIVE-CHECK',
    'FULL-A-RECOMMENDATION-LIVE-CSV',
    'FULL-A-RECOMMENDATION-LIVE-PREVIEW',
    'FULL-RECOMMENDATION-SUCCESSFUL-TRAINING-DEPENDENCY',
    'FULL-WATCH-FULLSCREEN-NATIVE-ESCAPE',
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--device-run', action='append', default=[])
    parser.add_argument('--product-root',type=Path,default=REPO,
                        help='Checkout whose product source was built; output remains in the report workspace.')
    parser.add_argument('--interrupted-run', action='append', default=[],
                        help='Explicitly retain recorded case outcomes from a stopped run; never certify the run completed.')
    args = parser.parse_args()
    sources = [
        ('20261015T121811.122489Z', None),
        ('20261015T122422.526453Z', None),
        # This mixed attempt had infrastructure failures, superseded by the next
        # integrated run. Only the unique Windows-input Escape proof is selected.
        ('20261015T123417.446310Z', {'FULL-WATCH-FULLSCREEN-NATIVE-ESCAPE'}),
        ('20261015T124450.860476Z', None),
        *[(run, None) for run in args.device_run],
        *[(run, None) for run in args.interrupted_run],
    ]
    latest = {}
    runs = []
    superseded_prerequisites=[]
    interrupted_unfinished_cases=[]
    for run_id, selection in sorted(sources,key=lambda source:source[0]):
        path = ROOT / 'artifacts/runs' / run_id / 'report.json'
        report = json.loads(path.read_text(encoding='utf-8'))
        interrupted=run_id in args.interrupted_run
        assert report.get('finished_at') or interrupted, 'Refuse undeclared incomplete execution: ' + run_id
        device = report.get('action_device', {}).get('name', 'desktop')
        runs.append({'run_id': run_id, 'device': device, 'report': path.resolve().as_posix(),
                     'execution_state':'interrupted; recorded cases only' if interrupted else 'finished',
                     'selection': sorted(selection) if selection else 'all records',
                     'raw_counts': {s: report.get(s, 0) for s in ['passed', 'failed', 'blocked']},
                     'cleanup': report.get('cleanup'), 'run_error': report.get('run_error')})
        for execution in report.get('group_executions',[]):
            if execution['status']!='completed':continue
            key=(device,'FULL-GROUP-'+execution['group'].upper())
            prior=latest.pop(key,None)
            if prior:
                superseded_prerequisites.append({'id':prior['id'],'raw_report':prior['raw_report'],
                    'resolved_by_execution':run_id,'group':execution['group'],
                    'note':'Later group execution completed; its individual case results remain authoritative. No synthetic PASS added.'})
        for item in report['cases']:
            if interrupted and 'duration_ms' not in item:
                interrupted_unfinished_cases.append({'id':item['id'],'raw_report':path.resolve().as_posix(),
                    'reason':'Stopped before a final case outcome was recorded; excluded from outcome counts.'})
                continue
            if selection and item['id'] not in selection:
                continue
            key = (device, item.get('logical_id', item['id']))
            latest[key] = {**item, 'action_device': device, 'raw_report': path.resolve().as_posix()}
    cases = list(latest.values())
    by_id = {c['id']: c for c in cases if c['action_device'] == 'desktop'}
    data = {
        'product_source_root':args.product_root.resolve().as_posix(),
        'product_scope_note':'Results belong to the declared built checkout; do not transfer them to a different main revision.',
        'release_gate': 'NOT_COMPLETE',
        'selection_policy': 'Latest recorded case outcome per device and logical ID; stopped runs require explicit declaration and do not certify completion. Unique native Escape selection retained from earlier mixed infrastructure attempt.',
        'runs': runs, 'cases': cases,
        'superseded_prerequisites':superseded_prerequisites,
        'interrupted_unfinished_cases':interrupted_unfinished_cases,
        'case_counts': dict(Counter(c['status'] for c in cases)),
        'device_counts': {d: dict(Counter(c['status'] for c in cases if c['action_device'] == d))
                          for d in sorted({c['action_device'] for c in cases})},
        'requested_fail_retest': {id: {'status': by_id[id]['status'], 'run_id': by_id[id]['run_id']} for id in FIXED},
        'previously_unconfirmed': {id: {'status': by_id[id]['status'], 'run_id': by_id[id]['run_id']} for id in UNCONFIRMED},
        'scope_exclusions': ['AUTH-EXT-05', 'U-PLAN.02', 'A-RECOMMENDATION.01', 'A-CF.01', 'A-CF.02', 'A-RECOMMENDATION.03'],
        'limitations': [
            'Passing child cases do not certify all clauses of a master scenario.',
            'Mobile/tablet are Chromium touch emulation, not physical hardware or Safari certification.',
            'Actual Python training uses Moto S3 protocol emulation, not Cloudflare R2 certification.',
            'Old public Local playback URL and downloaded file observations do not prove R2 signed URL expiry/revocation.',
            'Real mailbox receipt/open/reset/login relies on explicit recipient confirmation plus supplied screenshots and server state.',
        ],
    }
    output = REPO / 'outputs/20261015-remaining-completion'
    (output / 'review.json').write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding='utf-8')
    products = [
        'backend/src/HuTube.Infrastructure/Plans/PlanService.cs',
        'frontend/user-web/src/app/features/video/watch-page.ts',
        'frontend/admin-web/src/app/features/videos/admin-videos-page.html',
        'frontend/admin-web/src/app/features/videos/admin-videos-page.scss',
        'frontend/admin-web/src/app/core/admin-page-translations.ts',
        'backend/src/HuTube.Application/Storage/IObjectStorage.cs',
        'backend/src/HuTube.Infrastructure/Recommendations/RecommendationSnapshotStore.cs',
        'backend/src/HuTube.Api/Program.cs',
        'backend/src/HuTube.Api/Controllers/ChannelController.cs',
        'backend/src/HuTube.Api/Controllers/AccountController.cs',
        'recommendation-service/app/config.py',
        'recommendation-service/app/r2_store.py',
    ]
    manifest = [{'path': p, 'sha256': hashlib.sha256((args.product_root / p).read_bytes()).hexdigest()} for p in products]
    (output / 'product-source-manifest.json').write_text(json.dumps(manifest, indent=2), encoding='utf-8')
    print(json.dumps({'records': len(cases), 'devices': data['device_counts'],
                      'fix3': data['requested_fail_retest'], 'unconfirmed5': data['previously_unconfirmed']}))


if __name__ == '__main__':
    main()
