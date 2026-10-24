"""Hold an actual older detail request while selecting a newer user target."""
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['admin'])
    admin = actors['admin']; p = admin['page']
    def switch(entry):
        data = suite.go(admin, '/users', 'app-admin-users-page', '/admin/users')
        assert len(data['items']) >= 3
        older, newer = data['items'][1:3]
        expect(p.locator('.detail-loading')).to_have_count(0)
        pattern = '**/api/v1/admin/users/' + older['userId']
        held = []
        p.route(pattern, lambda route: held.append(route))
        try:
            p.locator('.user-row').filter(has_text=older['email']).click()
            p.wait_for_timeout(100)
            assert len(held) == 1
            suite.response(admin, '/admin/users/' + newer['userId'], lambda: p.locator('.user-row').filter(has_text=newer['email']).click())
            expect(p.locator('.detail-identity')).to_contain_text(newer['userId'])
            suite.evidence(admin, entry, 'new-target-before-old-release')
            with p.expect_response(lambda response: response.url.endswith('/admin/users/' + older['userId'])):
                held.pop().continue_()
            p.wait_for_timeout(300)
            expect(p.locator('.detail-identity')).to_contain_text(newer['userId'])
            expect(p.locator('.user-row.is-selected')).to_contain_text(newer['email'])
            entry['resource_ids'] = [older['userId'], newer['userId']]
            entry['steps'] = ['Hold genuine older user-detail request', 'Select another real row while older request is pending; new response renders exact ID', 'Release actual older response; selected row and detail/action target must both remain the newest user', 'Source review: Users offers fixed pageSize=10, no page-size selector; all offered sizes means only this fixed size']
        finally:
            for route in held: route.continue_()
            p.unroute(pattern)
    case(suite, admin, 'ADMIN-USERS-LATE-DETAIL-TARGET-ISOLATION', 'A-USERS.01', 'Late user detail cannot overwrite a newer selected target', switch, 'users')
