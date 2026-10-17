"""Direct purchase and catalog denial for inactive/archived owned plan fixtures."""
import json
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module


def run(suite, config, actors, statuses=('inactive', 'archived')):
    snapshot_module(suite, __file__)
    admin, member = actors['admin'], actors['member']
    p = member['page']
    payload = {'code': 'qc_status_' + suite.run_id[9:15], 'name': 'QC status ' + suite.run_id,
               'price': 12345, 'durationDays': 30, 'storageLimit': 1024**3, 'maxUploadSize': 1024**2,
               'maxVideoDuration': 60, 'maxVideoQuality': '360p', 'maxDownloadQuality': '360p',
               'maxMembers': 1, 'features': json.dumps({'download': True}), 'isDefaultForNewUsers': False}
    plan = suite.api(admin, 'post', '/admin/plans', data=payload, expected=201).json()
    pid = plan['planId']
    baseline = suite.api(member, 'get', '/plans/my-plan').json()
    try:
        for status in statuses:
            def denied(entry, status=status):
                if status == 'inactive':
                    suite.api(admin, 'put', '/admin/plans/' + pid, data={**payload, 'status': status})
                else:
                    suite.api(admin, 'post', '/admin/plans/' + pid + '/archive', data={}, expected=204)
                persisted = next(v for v in suite.api(admin, 'get', '/admin/plans').json() if v['planId'] == pid)
                assert persisted['status'] == status
                assert not any(v['planId'] == pid for v in suite.api(member, 'get', '/plans').json())
                for suffix in ['', '/share']:
                    response = suite.api(member, 'get', '/plans/' + pid + suffix, expected=404)
                    assert response.json()['code'] == 'PLAN_NOT_FOUND'
                for endpoint, data in [('/plans/' + pid + '/subscribe', {}), ('/payments', {'planId': pid, 'autoRenew': False, 'idempotencyKey': 'qc-denied-' + status + suite.run_id})]:
                    response = suite.api(member, 'post', endpoint, data=data, expected=404)
                    assert response.json()['code'] == 'PLAN_NOT_FOUND'
                suite.go(member, '/plans/' + pid, 'app-plan-detail-page')
                expect(p.locator('.state.error')).to_be_visible()
                expect(p.locator('button.cta-subscribe')).to_have_count(0)
                p.reload()
                expect(p.locator('.state.error')).to_be_visible()
                suite.evidence(member, entry, status + '-plan-unavailable')
                suite.go(member, '/account', 'app-account-page', '/account/profile')
                current = suite.api(member, 'get', '/plans/my-plan').json()
                assert current['planId'] == baseline['planId']
                entry['resource_ids'] = [pid, member['identity']['userId']]
                entry['steps'] = ['Admin actual mutation sets plan ' + status + '; API read confirms persisted status', 'Public catalog, direct detail and share deny inaccessible plan', 'Direct subscribe and payment initiation reject PLAN_NOT_FOUND without entitlement mutation', 'Real User detail route and reload show error with no purchase button']
            case(suite, member, 'PLAN-' + status.upper() + '-DIRECT-PURCHASE-DENIED', 'U-PLAN.01', status + ' plans cannot be purchased through stale direct links', denied, 'plans')
    finally:
        suite.api(admin, 'post', '/admin/plans/' + pid + '/archive', data={}, expected=204)
