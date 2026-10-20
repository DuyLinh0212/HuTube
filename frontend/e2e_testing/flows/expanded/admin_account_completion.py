"""Missing Admin-account session and profile-link behaviors, using only disposable sessions."""
from playwright.sync_api import expect

from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['admin'])
    admin = actors['admin']; page = admin['page']
    peer = suite.actor('admin-account-disposable-peer', 'admin')
    try:
        def profile_and_revoke(entry):
            identity = suite.api(admin, 'get', '/auth/me').json()
            suite.go(admin, '/account', 'app-account-page', '/auth/sessions')
            expect(page.locator('.profile-summary')).to_contain_text(identity['displayName'])
            expect(page.locator('.profile-summary')).to_contain_text(identity['email'])
            page.locator('.profile-trigger').click()
            page.locator('.account-row').click()
            page.wait_for_url('**/account')
            sessions = suite.api(admin, 'get', '/auth/sessions').json()['items']
            peer_id = next(item['sessionId'] for item in sessions if item['sessionId'] in {s['sessionId'] for s in suite.api(peer, 'get', '/auth/sessions').json()['items'] if s['isCurrent']})
            row = page.locator('.sessions-list').first.locator('.session-item').filter(has=page.locator('.session-revoke')).first
            row.locator('.session-revoke').click(); expect(page.locator('.revoke-warning')).to_be_visible()
            page.locator('.revoke-warning .secondary').click(); expect(page.locator('.revoke-warning')).to_have_count(0)
            assert suite.api(peer, 'get', '/auth/me').status == 200
            row.locator('.session-revoke').click()
            suite.response(admin, '/auth/sessions/' + peer_id, lambda: page.locator('.revoke-warning .danger').click(), method='DELETE')
            suite.api(peer, 'get', '/auth/me', expected=401)
            peer['page'].goto(peer['origin'] + '/users'); peer['page'].wait_for_url('**/login**')
            assert suite.api(admin, 'get', '/auth/me').json()['userId'] == identity['userId']
            entry['resource_ids'] = [identity['userId'], peer_id]
            entry['steps'] = ['Admin account profile and topbar account link show the authenticated identity', 'Open a disposable peer session; cancel its revoke and confirm it remains usable', 'Confirm revoke only the exact peer session; peer route/API becomes login/401 while controller remains authenticated']
        case(suite, admin, 'ADMIN-ACCOUNT-PROFILE-LINK-REVOKE-PEER', 'A-ACCOUNT.01', 'Admin account link and selected-session revoke isolate the exact peer', profile_and_revoke, 'account')

        suite.release_actor(peer)
        peer = suite.actor('admin-account-logout-others-peer', 'admin')
        def logout_others(entry):
            suite.go(admin, '/account', 'app-account-page', '/auth/sessions')
            expect(page.locator('.sessions-actions button').first).to_be_enabled()
            suite.response(admin, '/auth/logout-others', lambda: page.locator('.sessions-actions button').first.click(), method='POST')
            expect(page.locator('.notice.success')).to_be_visible()
            assert suite.api(admin, 'get', '/auth/sessions').json()['items'][0]['isCurrent']
            suite.api(peer, 'get', '/auth/me', expected=401)
            peer['page'].goto(peer['origin'] + '/users'); peer['page'].wait_for_url('**/login**')
            entry['resource_ids'] = [admin['identity']['userId']]
            entry['steps'] = ['Create a second disposable Admin session', 'Use the real Admin Account Logout others button', 'Controller remains the only current session; peer API and protected route are rejected']
        case(suite, admin, 'ADMIN-ACCOUNT-LOGOUT-OTHERS-PEER', 'A-ACCOUNT.01', 'Admin logout-others revokes only other Admin sessions', logout_others, 'account')
    finally:
        suite.release_actor(peer)
