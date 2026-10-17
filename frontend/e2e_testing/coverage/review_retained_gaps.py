"""Link reviewed existing assertions to gaps; performs no product/test actions."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parents[1]
OUT = REPO / 'outputs/20261017-delta-completion'


def main():
    retained = json.loads((ROOT / 'coverage/retained-evidence.json').read_text(encoding='utf-8'))['cases']
    reviews = {
        'U-WATCH.02': {
            'cases': ['FULL-PLAYLIST-NEXT-PREVIOUS-EXACT-DECODED-SOURCES', 'FULL-WATCH-PROGRESS-SESSION-COOLDOWN-RELOAD', 'FULL-WATCH-PLAYBACK-NETWORK-RETRY-REAL-RECOVERY'],
            'conclusion': 'Existing actual-source next/previous decode, repeated progress/session cooldown/reload and real playback transport retry assertions cover the named residual gap. No retained case re-executed.',
            'sources': ['frontend/e2e_testing/flows/expanded/playlist_remaining_actions.py', 'frontend/e2e_testing/flows/expanded/watch_view_session_completion.py', 'frontend/e2e_testing/flows/expanded/watch_rendition_recovery.py', 'backend/tests/HuTube.UnitTests/ViewSessionBoundaryTests.cs'],
        },
        'A-USERS.02': {
            'cases': ['FULL-USER-LOCK-UNLOCK-SESSION', 'FULL-PRIORITY-ROLE-DEMOTION-LIVE-TWO-PLATFORMS'],
            'conclusion': 'Existing lock/session and both-platform demotion evidence linked. Status Notify calls PublishInAppAsync with account target/action; no email contract for this action (N/A per master mail rule). Role/session audit remains in retained reports.',
            'sources': ['backend/src/HuTube.Infrastructure/Users/AdminUserService.cs', 'backend/src/HuTube.Infrastructure/Notifications/NotificationHub.cs', 'frontend/e2e_testing/flows/expanded/admin_deep.py', 'frontend/e2e_testing/flows/expanded/security_sessions.py'],
        },
    }
    for review in reviews.values():
        review['evidence'] = []
        for case_id in review.pop('cases'):
            assert case_id in retained, case_id
            record = retained[case_id][-1]
            path = ROOT / record['report']
            report = json.loads(path.read_text(encoding='utf-8'))
            case = next(c for c in report['cases'] if c.get('logical_id', c['id']) == case_id and c['status'] == 'passed')
            assert {s['viewport'] for s in case['screenshots']} >= {'desktop', 'mobile', 'tablet'}
            for shot in case['screenshots']:
                assert (ROOT / shot['path']).is_file(), shot['path']
            review['evidence'].append({'id': case_id, 'run_id': record['run_id'], 'report': record['report'], 'steps': case.get('steps', []), 'screenshots': case['screenshots']})
        review['sources'] = [{'path': path, 'sha256': hashlib.sha256((REPO / path).read_bytes()).hexdigest()} for path in review['sources']]
        review['status'] = 'PASS_RECONCILED'
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'reviewed-retained-links.json').write_text(json.dumps(reviews, ensure_ascii=False, indent=2), encoding='utf-8')
    print(json.dumps({key: value['status'] for key, value in reviews.items()}))


if __name__ == '__main__':
    main()
