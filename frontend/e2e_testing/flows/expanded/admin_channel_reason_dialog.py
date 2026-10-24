"""Supplement missing deletion-modal viewport and exact reason-length boundaries; no confirmed delete."""
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['target', 'admin'])
    owner, admin = actors['target'], actors['admin']; p = admin['page']
    response = suite.api(owner, 'get', '/channels/me', expected=(200, 404)); created = response.status == 404
    channel = suite.api(owner, 'post', '/channels', data={'name': 'QC reason dialog ' + suite.run_id, 'handle': 'qc-dialog-' + suite.run_id[9:15]}, expected=201).json() if created else response.json()
    cid = channel['channelId']
    try:
        def reason(entry):
            suite.go(admin, '/channels', 'app-admin-channels-page', '/admin/channels')
            p.locator('.search-box input').fill(channel['handle'])
            suite.response(admin, '/admin/channels', lambda: p.locator('.btn-filter').click(), params={'search': channel['handle']})
            p.locator('.channel-row').filter(has_text=channel['handle']).locator('.btn-dots').click()
            p.locator('.dropdown-menu .menu-item').last.click()
            expect(p.locator('.modal-dialog .modal-lead')).to_contain_text(channel['handle'])
            for value, valid in [('', False), (' x ', False), ('xy', False), ('xyz', True)]:
                p.locator('.modal-textarea').fill(value)
                expect(p.locator('.btn-modal-confirm')).to_be_enabled(enabled=valid)
                suite.evidence(admin, entry, 'trimmed-reason-length-' + str(len(value.strip())))
            p.locator('.btn-modal-cancel').click()
            expect(p.locator('.modal-dialog')).to_have_count(0)
            baseline = suite.api(admin, 'get', '/admin/channels/' + cid).json()['channel']
            suite.api(admin, 'delete', '/admin/channels/' + cid, data={'reason': ' x ', 'notifyOwner': False}, expected=400)
            persisted = suite.api(admin, 'get', '/admin/channels/' + cid).json()['channel']
            assert persisted == baseline and persisted['status'] == 'active'
            entry['resource_ids'] = [cid]
            entry['steps'] = ['Open actual deletion dialog for exact owned QC channel', 'All three viewports: trimmed reason lengths 0/1/2 keep confirm disabled, exactly 3 enables', 'Cancel closes dialog and preserves channel', 'Actual invalid-reason DELETE rejects 400 and complete Admin channel record remains unchanged']
        case(suite, admin, 'ADMIN-CHANNEL-DELETE-REASON-BOUNDARY-DIALOG', 'A-CHANNELS.02', 'Delete reason boundaries and cancel are visible on all viewports', reason, 'channels')
    finally:
        if created:
            ensure_actor_pages(suite, actors, ['target'])
            suite.api(actors['target'], 'delete', '/channels/' + cid, expected=(200, 204))
