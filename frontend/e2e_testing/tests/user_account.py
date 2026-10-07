"""User Web Account test cases."""
import json
import sys
from pathlib import Path
from urllib.parse import urlsplit

from playwright.sync_api import expect

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from support.web_session import run_suite


def run_checks(session):
    page, context, origin = session.page, session.context, session.origin
    setup, identity, credentials = session.setup, session.identity, session.credentials
    app, report, run_dir = session.app, session.report, session.run_dir
    access_headers, check = session.access_headers, session.check
    original_profile = {}
    def profile_read():
        expect(page.locator('.channel-display-name')).to_have_text(identity['displayName'])
        page.locator('.yt-action-link-btn.primary-action').click()
        expect(page.locator('#dn')).to_have_value(identity['displayName'])
        expect(page.locator('#bio')).to_have_attribute('maxlength', '160')
        original_profile['bio'] = page.locator('#bio').input_value()
    check('U-ACCOUNT-READ-01', page, profile_read, app)

    def cancel():
        page.locator('#dn').fill('Temporary unsaved E2E name')
        page.locator('#bio').fill('Temporary unsaved E2E bio')
        page.locator('.profile-inline-form .btn-yt-secondary').click()
        expect(page.locator('.profile-inline-form')).to_have_count(0)
        page.reload()
        expect(page.locator('app-account-page')).to_be_visible(timeout=45000)
        expect(page.locator('.channel-display-name')).to_have_text(identity['displayName'])
        page.locator('.yt-action-link-btn.primary-action').click()
        expect(page.locator('#dn')).to_have_value(identity['displayName'])
        expect(page.locator('#bio')).to_have_value(original_profile['bio'])
    check('U-ACCOUNT-CANCEL-01', page, cancel, app)

    def mobile():
        page.set_viewport_size({'width': 390, 'height': 844})
        expect(page.locator('#dn')).to_be_visible()
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth + 1'), 'Horizontal overflow'
    check('U-ACCOUNT-MOBILE-01', page, mobile, app)
    if session.write_profile:
        api = setup['api_origin'] + '/api/v1'
        assert urlsplit(api).hostname in ('localhost', '127.0.0.1', '::1'), 'Profile writes require a local API'
        # Reload rotates the session. Follow the current token actually
        # used by the Web instead of retaining the login token.
        headers = access_headers
        assert headers.get('Authorization'), 'No authenticated profile request observed'
        original_response = context.request.get(api + '/account/profile', headers=headers)
        assert original_response.status == 200
        baseline = original_response.json()
        baseline_values = {'displayName': baseline['displayName'], 'bio': baseline.get('bio') or ''}
        recovery = run_dir / 'profile-recovery.json'
        recovery.write_text(json.dumps({'user_id': identity['userId'], 'api_origin': setup['api_origin'], 'profile': baseline_values}, ensure_ascii=False), encoding='utf-8')
        report['cleanup'] = {'status': 'pending', 'recovery_file': str(recovery)}

        def edit():
            page.set_viewport_size({'width': 1440, 'height': 960})
            with page.expect_response(lambda r: r.request.method == 'GET' and r.url == api + '/account/profile') as loaded:
                page.goto(origin + '/account')
            assert loaded.value.status == 200
            expect(page.locator('app-account-page')).to_be_visible(timeout=45000)
            page.locator('.yt-action-link-btn.primary-action').click()
            expect(page.locator('#dn')).to_be_visible()
            expect(page.locator('#dn')).to_have_value(loaded.value.json()['displayName'])

        def submit(expected_status):
            with page.expect_response(lambda r: r.request.method == 'PATCH' and r.url == api + '/account/profile') as response:
                page.locator('.profile-inline-form .btn-yt-primary').click()
            assert response.value.status == expected_status
            return response.value

        def unchanged():
            response = context.request.get(api + '/account/profile', headers=headers)
            assert response.status == 200
            value = response.json()
            assert value['displayName'] == baseline_values['displayName']
            assert (value.get('bio') or '') == baseline_values['bio']

        try:
            def blank_name():
                edit()
                page.locator('#dn').fill('   ')
                response = submit(400)
                assert response.json()['code'] == 'INVALID_DISPLAY_NAME'
                expect(page.locator('.yt-alert-error')).to_be_visible()
                unchanged()
            check('U-ACCOUNT-VALIDATION-01', page, blank_name, app)

            def long_name():
                edit()
                page.locator('#dn').fill('N' * 121)
                response = submit(400)
                assert response.json()['code'] == 'INVALID_DISPLAY_NAME'
                expect(page.locator('.yt-alert-error')).to_be_visible()
                unchanged()
            check('U-ACCOUNT-VALIDATION-02', page, long_name, app)

            def bio_limit():
                edit()
                page.locator('#bio').fill('')
                page.locator('#bio').press_sequentially('B' * 161)
                expect(page.locator('#bio')).to_have_value('B' * 160)
                unchanged()
            check('U-ACCOUNT-BIO-LIMIT-01', page, bio_limit, app)

            def save():
                edit()
                temporary_name = 'HuTube E2E — Kiểm tra lưu hồ sơ'
                temporary_bio = 'Kiểm thử hồ sơ User, dữ liệu tạm sẽ được khôi phục.'
                page.locator('#dn').fill('  ' + temporary_name + '  ')
                page.locator('#bio').fill('  ' + temporary_bio + '  ')
                response = submit(200)
                assert response.json()['displayName'] == temporary_name
                assert response.json()['bio'] == temporary_bio
                expect(page.locator('.profile-inline-form')).to_have_count(0)
                expect(page.locator('.yt-alert-success')).to_be_visible()
                edit()
                expect(page.locator('#dn')).to_have_value(temporary_name)
                expect(page.locator('#bio')).to_have_value(temporary_bio)
            check('U-ACCOUNT-SAVE-01', page, save, app)
        finally:
            def restore():
                edit()
                page.locator('#dn').fill(baseline_values['displayName'])
                page.locator('#bio').fill(baseline_values['bio'])
                submit(200)
                edit()
                expect(page.locator('#dn')).to_have_value(baseline_values['displayName'])
                expect(page.locator('#bio')).to_have_value(baseline_values['bio'])
                unchanged()
                report['cleanup']['status'] = 'restored'
                recovery.unlink()
                report['cleanup'].pop('recovery_file', None)
            check('U-ACCOUNT-RESTORE-01', page, restore, app)
            if report['cleanup']['status'] != 'restored':
                response = context.request.patch(api + '/account/profile', headers=headers, data=baseline_values)
                assert response.status == 200, 'Fallback restoration failed'
                unchanged()
                report['cleanup']['status'] = 'restored-via-api'
                recovery.unlink()
                report['cleanup'].pop('recovery_file', None)


if __name__ == '__main__':
    sys.exit(run_suite('user', run_checks))
