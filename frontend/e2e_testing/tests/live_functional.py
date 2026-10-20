"""Run functional journeys against the requested 4200/4201 services.

WEB_E2E_CREDENTIALS is required. No live credentials are committed or written.
"""
import argparse
import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from support.live_suite import LiveSuite
from flows.user.live_account import run as account,run_admin as admin_account
from flows.user.live_discovery import run as discovery,run_library
from flows.admin.live_videos import run as videos
from flows.user.live_auth import run as auth
from flows.admin.live_users import run as users
from flows.user.live_playlists import run as playlists
from flows.admin.live_catalog import run as catalog
from flows.user.live_media import run as media
from support.live_recovery import recover,recover_subscription
from flows.admin.live_channels import run as channels
from flows.admin.live_recommendation import run as recommendation
from flows.user.live_policy import run as policy
from flows.user.live_auth_extra import run as auth_extra,run_negative
from flows.user.live_sessions import run as sessions
from flows.user.live_analytics import run as analytics
from flows.user.live_subscriptions import run as subscriptions
from flows.user.live_account_extra import run as account_extra
from flows.user.live_library_extra import run as library_extra
from flows.admin.live_moderation_lists import run as moderation_lists
from flows.user.live_channel_validation import run as channel_validation
from flows.user.live_plans import run as user_plans
from flows.user.live_studio_settings import run as studio_settings
from flows.user.live_comment_ownership import run as comment_ownership
from flows.admin.live_admin_upload import run as admin_upload
from flows.admin.live_review_layout import run as review_layout

def main():
    if hasattr(sys.stdout,'reconfigure'):
        sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--headed',action='store_true')
    parser.add_argument('--recover-run',action='append',default=[])
    parser.add_argument('--recover-subscription-run',action='append',default=[])
    parser.add_argument('--groups',default='auth,auth-extra,auth-negative,sessions,analytics,account-extra,history,library,moderation-lists,channel-validation,user-plans,studio-settings,comment-ownership,subscriptions,playlists,cross-app,taxonomy,plans,rbac,channels,recommendation,policy,users,account,admin-account,discovery,videos')
    args=parser.parse_args()
    groups=args.groups.split(',')
    with sync_playwright() as pw:
        suite=LiveSuite(pw,headed=args.headed)
        suite.skip_legacy_comment_denial='comment-ownership' in groups
        try:
            owner=suite.actor('owner','user')
            admin=suite.actor('admin','admin')
            for run_dir in args.recover_run:
                recover(suite,admin,run_dir)
            for run_dir in args.recover_subscription_run:
                recover_subscription(suite,owner,admin,run_dir)
            if 'auth' in groups:
                auth(suite,owner,admin)
            if 'auth-extra' in groups:
                auth_extra(suite,owner,admin)
            if 'auth-negative' in groups:
                run_negative(suite,owner,admin)
            if 'sessions' in groups:
                sessions(suite,owner,admin)
            if 'analytics' in groups:
                analytics(suite,owner)
            if 'account-extra' in groups:
                account_extra(suite,owner)
            if 'history' in groups:
                library_extra(suite,owner)
            if 'library' in groups:
                run_library(suite,owner)
            if 'moderation-lists' in groups:
                moderation_lists(suite,admin)
            if 'review-layout' in groups and not any(group in groups for group in ['videos','admin-upload']):
                review_layout(suite,admin)
            if 'channel-validation' in groups:
                channel_validation(suite,owner)
            if 'user-plans' in groups:
                user_plans(suite,owner)
            if 'studio-settings' in groups:
                studio_settings(suite,owner)
            if any(group in groups for group in ['playlists','media','subscriptions','cross-app','comment-ownership','videos','admin-upload']):
                other=suite.actor('second-supplied-account','user','admin')
            if 'comment-ownership' in groups:
                comment_ownership(suite,owner,other)
            if 'admin-upload' in groups and 'videos' not in groups:
                admin_upload(suite,admin,other)
            if 'subscriptions' in groups:
                subscriptions(suite,owner,other)
            if 'playlists' in groups:
                playlists(suite,owner,other)
            if 'media' in groups and 'cross-app' not in groups:
                media(suite,owner,other)
            if 'cross-app' in groups:
                media(suite,owner,other,admin)
            catalog(suite,admin,owner,groups)
            if 'channels' in groups:
                channels(suite,admin,owner)
            if 'recommendation' in groups:
                recommendation(suite,admin)
            if 'policy' in groups:
                policy(suite,owner)
            if 'users' in groups:
                users(suite,admin,owner)
            for name,action,actor in [('account',account,owner),('admin-account',admin_account,admin),('discovery',discovery,owner),('videos',videos,admin)]:
                if name in groups:
                    print('GROUP',name,flush=True)
                    action(suite,actor)
                    if name=='videos': admin_upload(suite,admin,other)
        except Exception as error:
            suite.report['run_error']=type(error).__name__
            print('RUN prerequisite failure:',type(error).__name__,flush=True)
        finally:
            suite.close()
            print('Report:',suite.run_dir/'report.json',flush=True)
    return 1 if suite.report['failed'] or suite.report['blocked'] or suite.report.get('run_error') else 0

if __name__=='__main__':
    sys.exit(main())
