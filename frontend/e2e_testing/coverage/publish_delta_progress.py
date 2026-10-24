"""Publish explicit delta evidence without rewriting historical audit/reports."""
import importlib.util
import json
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
OUT = REPO / 'outputs/20261017-delta-completion'
BASELINE = REPO / 'outputs/20261016-branch-completion/master-clause-audit.json'
START = '20261017T030755.125960Z'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    audit = json.loads(BASELINE.read_text(encoding='utf-8'))
    scope = json.loads((ROOT / 'coverage/delta-scope.json').read_text(encoding='utf-8'))
    runs, latest, passes = [], {}, {}
    rejected_path = OUT / 'evidence-rejections.json'
    rejected_runs = json.loads(rejected_path.read_text(encoding='utf-8')) if rejected_path.exists() else {}
    for path in sorted((ROOT / 'artifacts/runs').glob('*/report.json')):
        if path.parent.name < START:
            continue
        report = json.loads(path.read_text(encoding='utf-8'))
        if not report.get('finished_at'):
            continue
        cases = [c for c in report.get('cases', []) if c.get('parent') in scope['allowed_parents']]
        if not cases:
            continue
        runs.append({'run_id': report['run_id'], 'report': path.relative_to(REPO).as_posix(),
            'finished_at': report['finished_at'], 'cleanup': report.get('cleanup', []), 'run_error': report.get('run_error')})
        for c in cases:
            key = c.get('logical_id', c['id'])
            if key in rejected_runs.get(report['run_id'], {}).get('rejected_case_ids', []):
                continue
            value = {k: c[k] for k in ('parent', 'status', 'screenshots', 'steps', 'resource_ids', 'actual') if k in c}
            value.update(id=key, run_id=report['run_id'], report=path.relative_to(REPO).as_posix())
            latest[key] = value
            if c['status'] == 'passed':
                assert {s['viewport'] for s in c.get('screenshots', [])} >= {'desktop', 'mobile', 'tablet'}, key
                for shot in c['screenshots']:
                    assert (ROOT / shot['path']).is_file(), shot['path']
                passes[key] = value
    # Explicitly closed obligations. Other parents retain their named gap until
    # the associated assertion/manual confirmation has actually completed.
    closure_cases = {
        'U-PLAN.03': ['FULL-DELTA-PLAN-EXACT-OWNER-MEMBER-USED-BYTES', 'FULL-DELTA-PLAN-RENEWAL-CURRENT-PRODUCT-CONTRACT'],
        'A-VIDEOS.01': ['FULL-DELTA-ADMIN-VIDEO-CATEGORY-FIXED-PAGE-SIZE', 'FULL-DELTA-ADMIN-VIDEO-STATS-PREVIEW-SOURCE'],
        'A-VIDEOS.02': ['FULL-DELTA-ADMIN-METADATA-LATE-TARGET-RESPONSE', 'FULL-DELTA-ADMIN-METADATA-PERMISSION-DENIED'],
        'A-TOPICS.01': ['FULL-DELTA-TAXONOMY-DUPLICATE-LENGTH-BOUNDARIES', 'FULL-DELTA-TAXONOMY-LINKED-ARCHIVE-DELETE'],
        'A-POLICY.01': ['FULL-DELTA-POLICY-DRAFT-EDIT-PUBLISH', 'FULL-DELTA-MODERATION-POLICY-VERSION-PINNED'],
        'A-MODERATION.05': ['FULL-DELTA-STRIKE-NATURAL-EXPIRY-AUDIT-NOTIFICATION'],
        'U-STUDIO.05': ['FULL-DELTA-STUDIO-CONTENT-FILTER-SEARCH-PAGINATION', 'FULL-DELTA-STUDIO-THUMBNAIL-PARTIAL-FAILURE', 'FULL-DELTA-STUDIO-PLAYLIST-PARTIAL-FAILURE', 'FULL-DELTA-STUDIO-EDIT-LATE-RESPONSE-TARGET'],
        'U-CHANNEL.05': ['FULL-DELTA-CHANNEL-REPORT-APPEAL-OWNER-STATUS-LINKS'],
        'X-MODERATION.01': ['FULL-DELTA-LEGACY-REPORT-WORKFLOW-REJECTION', 'FULL-DELTA-MODERATION-LOCKED-DELETED-CHANNEL-TARGETS'],
    }
    groups = []
    reviewed_path = OUT / 'reviewed-retained-links.json'
    reviewed = json.loads(reviewed_path.read_text(encoding='utf-8')) if reviewed_path.exists() else {}
    for master in audit['masters']:
        if master['status'] != 'PARTIAL_WITH_NAMED_GAPS':
            continue
        needed = closure_cases.get(master['id'], [])
        closed = bool(needed) and all(k in passes and latest[k]['status'] == 'passed' for k in needed)
        reconciled = reviewed.get(master['id'], {}).get('status') == 'PASS_RECONCILED'
        groups.append({'id': master['id'], 'status': 'PASS_RECONCILED' if reconciled else 'PASS_DELTA' if closed else 'OPEN',
            'closure_cases': needed, 'remaining_obligations': [] if closed or reconciled else master['remaining_obligations'],
            'retained_review': reviewed.get(master['id']),
            'delta_cases': [v for v in latest.values() if v['parent'] == master['id']]})
    # Secondary index protects newly passed deltas as well as frozen history.
    (ROOT / 'coverage/delta-passed-evidence.json').write_text(json.dumps({'cases': passes}, ensure_ascii=False, indent=2), encoding='utf-8')
    spec = importlib.util.spec_from_file_location('delta_inventory', ROOT / 'coverage/generate_inventory.py')
    inventory_module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inventory_module)
    inventory_module.ROOT = OUT / 'inventory'
    (inventory_module.ROOT / 'coverage').mkdir(parents=True, exist_ok=True)
    inventory_module.web()
    inventory = json.loads((inventory_module.ROOT / 'coverage/web-inventory.json').read_text(encoding='utf-8'))
    counts = {k: len(inventory[k]) for k in ('routes', 'bindings', 'navigation', 'form_controls')}
    google_manual_path = OUT / 'google-manual-confirmation.json'
    google_manual = json.loads(google_manual_path.read_text(encoding='utf-8')) if google_manual_path.exists() else None
    ledger = {'generated_at': datetime.now(timezone.utc).isoformat(), 'baseline': str(BASELINE),
        'google_manual_checkpoint': google_manual,
        'retained_parents': 64, 'excluded': scope['excluded_parents'], 'runs': runs, 'groups': groups,
        'inventory_counts': counts, 'inventory_gate': 'OPEN: individual binding/navigation/control mapping must be completed; counts do not certify coverage',
        'release_gate': 'NOT_COMPLETE', 'passed_delta_cases': len(passes),
        'closed_gap_groups': sum(g['status'] in ('PASS_DELTA', 'PASS_RECONCILED') for g in groups)}
    (OUT / 'delta-ledger.json').write_text(json.dumps(ledger, ensure_ascii=False, indent=2), encoding='utf-8')
    lines = ['## Delta execution — 17/10/2026', '',
        'Authoritative delta ledger: `outputs/20261017-delta-completion/delta-ledger.json`. Historical audit and raw reports are preserved.', '',
        f"64 PASS_RETAINED; {ledger['closed_gap_groups']}/18 named gap groups closed; {len(passes)} passing delta case IDs. Release gate: NOT_COMPLETE.", '',
        '| Parent | Delta status | Evidence / remaining obligation |', '|---|---|---|']
    for g in groups:
        evidence = '; '.join(v['id'] + ' @ ' + v['run_id'] for v in g['delta_cases'] if v['status'] == 'passed')
        if g.get('retained_review'):
            evidence = g['retained_review']['conclusion'] + ' See reviewed-retained-links.json.'
        remaining = '; '.join(o.get('requirement', str(o)) if isinstance(o, dict) else str(o) for o in g['remaining_obligations'])
        lines.append(f"| {g['id']} | {g['status']} | {(evidence + ('; ' if evidence and remaining else '') + remaining).replace('|', '/')} |")
    lines += ['', 'Current source inventory: ' + ', '.join(f'{k}={v}' for k, v in counts.items()) + '.',
        'Individual source reconciliation remains a release gate. Manual Google sign-in at localhost is confirmed by the user and screenshot (google-manual-confirmation.json); reload/session and remaining Google branches are not yet verified. Mailbox/provider confirmations remain pending unless linked in the ledger.',
        'Harness category failures are retained in original reports; only the corrected case is retested. No broad regression is run.', '']
    section = '\n'.join(lines)
    (OUT / 'STATUS.md').write_text(section, encoding='utf-8')
    for relative in ('docs/WEB_TEST_SCENARIOS.md', 'docs/WEB_E2E_PROGRESS.md'):
        path = REPO / relative
        text = path.read_text(encoding='utf-8')
        begin, end = '<!-- DELTA-20261017-BEGIN -->', '<!-- DELTA-20261017-END -->'
        if begin in text:
            text = text[:text.index(begin)] + text[text.index(end) + len(end):].lstrip('\n')
        head, _, rest = text.partition('\n')
        path.write_text(head + '\n\n' + begin + '\n' + section + end + '\n\n' + rest.lstrip('\n'), encoding='utf-8')
    print(json.dumps({'closed_gap_groups': ledger['closed_gap_groups'], 'passed_delta_cases': len(passes), 'inventory': counts}))


if __name__ == '__main__':
    main()
