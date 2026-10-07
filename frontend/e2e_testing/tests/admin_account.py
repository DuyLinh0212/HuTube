"""Admin Web Account test cases."""
import sys
from pathlib import Path

from playwright.sync_api import expect

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from support.web_session import run_suite


def run_checks(session):
    page, identity, credentials = session.page, session.identity, session.credentials
    app, check = session.app, session.check
    def admin_read():
        expect(page.locator('.profile-summary')).to_contain_text(credentials[app]['email'])
        expect(page.locator('.profile-summary h2')).to_have_text(identity['displayName'])
    check('A-ACCOUNT-READ-01', page, admin_read, app)
    def admin_reload():
        page.reload()
        admin_read()
    check('A-ACCOUNT-RELOAD-01', page, admin_reload, app)
    def admin_mobile():
        page.set_viewport_size({'width': 390, 'height': 844})
        admin_read()
        assert page.evaluate('document.documentElement.scrollWidth <= window.innerWidth + 1'), 'Horizontal overflow'
    check('A-ACCOUNT-MOBILE-01', page, admin_mobile, app)


if __name__ == '__main__':
    sys.exit(run_suite('admin', run_checks))
