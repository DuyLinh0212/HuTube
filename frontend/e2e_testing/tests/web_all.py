"""Independent Web suites on run_local.py's managed database and servers."""
import argparse
import json
from pathlib import Path
import sys
import traceback
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from playwright.sync_api import sync_playwright
from support.web_suite import WebSuite
from flows.user.functional import run as run_user
from flows.admin.functional import run as run_admin
from flows.admin.taxonomy import run as run_taxonomy
from flows.admin.plans import run as run_plans
from flows.admin.rbac import run as run_rbac
from flows.cross_app.moderation import run as run_moderation
from flows.admin.user_controls import run as run_user_controls
from flows.admin.policies import run as run_policies
from flows.admin.pagination import run as run_pagination
from flows.admin.channels import run as run_channels
from flows.user.channel_settings import run as run_channel_settings
from flows.user.playlist_settings import run as run_playlist_settings
from flows.user.ratings import run as run_ratings
from flows.user.media import run as run_media
from flows.user.preferences import run as run_preferences
from flows.user.interactions import run as run_interactions
from flows.user.membership import run as run_membership
from flows.user.errors import run as run_errors
from user_account import run_checks as run_user_account
from admin_account import run_checks as run_admin_account

ACCOUNT_CASES = {
    'U-ACCOUNT-READ-01': ('Đọc hồ sơ và mở form sửa', 'Tên/email đúng fixture; form giữ tên/bio; bio maxlength 160'),
    'U-ACCOUNT-CANCEL-01': ('Hủy sửa hồ sơ rồi reload', 'Tên/bio chưa lưu không persist'),
    'U-ACCOUNT-MOBILE-01': ('Form hồ sơ ở viewport mobile', 'Form hiển thị; không overflow ngang 390px'),
    'U-ACCOUNT-VALIDATION-01': ('Tên chỉ có khoảng trắng', 'PATCH 400 INVALID_DISPLAY_NAME; dữ liệu không thay đổi'),
    'U-ACCOUNT-VALIDATION-02': ('Tên quá giới hạn 120 ký tự', 'PATCH 400 INVALID_DISPLAY_NAME; dữ liệu không thay đổi'),
    'U-ACCOUNT-BIO-LIMIT-01': ('Nhập bio 161 ký tự', 'UI giữ tối đa 160 ký tự; chưa lưu không persist'),
    'U-ACCOUNT-SAVE-01': ('Lưu tên/bio có khoảng trắng đầu cuối', 'PATCH 200 trim; UI và GET sau reload giữ giá trị'),
    'U-ACCOUNT-RESTORE-01': ('Phục hồi hồ sơ fixture', 'Tên/bio gốc được lưu và đối chiếu GET; xóa recovery file'),
    'A-ACCOUNT-READ-01': ('Đọc hồ sơ Admin', 'Tên/email đúng tài khoản fixture Admin'),
    'A-ACCOUNT-RELOAD-01': ('Reload hồ sơ Admin', 'Phiên được restore và identity giữ nguyên'),
    'A-ACCOUNT-MOBILE-01': ('Hồ sơ Admin trên mobile', 'Identity hiển thị; không overflow ngang 390px'),
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, required=True)
    args = parser.parse_args()
    config = json.loads(args.config.read_text(encoding='utf-8'))
    with sync_playwright() as playwright:
        suite = WebSuite(config, playwright)
        try:
            owner = suite.actor('owner')
            member = suite.actor('member')
            admin = suite.actor('superadmin', 'super_admin')
            for actor, checks in ((owner, run_user_account), (admin, run_admin_account)):
                def check(case_id, page, action, application, on_failure='failed', actor=actor):
                    title, expected = ACCOUNT_CASES[case_id]
                    return suite.case(actor, case_id, title, action, module='account', expected=expected,
                                      steps='Mở Account; thực hiện thao tác trong scenario; kiểm tra UI/API và trạng thái sau thao tác', data=actor['email'])
                checks(SimpleNamespace(page=actor['page'], context=actor['context'], origin=config[actor['application'] + '_url'],
                    setup={'api_origin': config['api_url'].removesuffix('/api/v1')}, identity=actor['identity'],
                    credentials={actor['application']: {'email': actor['email']}}, app=actor['application'],
                    report=suite.report, run_dir=suite.run_dir, access_headers=actor['headers'], check=check,
                    write_profile=actor['application'] == 'user'))
                actor['page'].set_viewport_size({'width': 1440, 'height': 960})
            run_user(suite, owner, member)
            run_preferences(suite, owner)
            run_media(suite, owner, member)
            run_interactions(suite, owner, member)
            run_membership(suite, owner, member)
            run_errors(suite, owner)
            run_admin(suite, admin, owner)
            run_taxonomy(suite, admin, member)
            run_plans(suite, admin, member)
            run_rbac(suite, admin, member)
            run_moderation(suite, owner, member, admin)
            run_user_controls(suite, admin, member)
            run_policies(suite, admin, member)
            run_pagination(suite, admin, owner)
            run_channels(suite, admin, owner)
            run_channel_settings(suite, owner, member)
            run_playlist_settings(suite, owner, member)
            run_ratings(suite, owner)
        except Exception as error:
            suite.report['run_error'] = type(error).__name__
            suite.report['run_error_message'] = str(error)[:2000]
            suite.report['run_error_trace'] = traceback.format_exc(limit=12)
            raise
        finally:
            suite.close()
    return 1 if suite.report['failed'] or suite.report['blocked'] else 0


if __name__ == '__main__':
    sys.exit(main())
