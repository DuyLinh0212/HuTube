"""Expanded real-UI journeys on an owned local PostgreSQL test cluster.

Registration/verification use the production API and local Email Pickup. Only the
initial synthetic Super Admin role is bootstrapped in the isolated database.
All tested role/status/channel/content changes go through the application's APIs.
"""
import argparse
import html
import json
import os
import re
import sys
import time
from email import policy
from email.parser import BytesParser
from email.utils import getaddresses
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from playwright.sync_api import sync_playwright, expect

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT))
from support.live_suite import LiveSuite, PrerequisiteMissing
from support.local_db import LocalDb

def pickup_link(config,email,route,not_before=0):
    deadline=time.monotonic()+30
    while time.monotonic()<deadline:
        for path in sorted(Path(config['mail_dir']).glob('*.eml'),key=lambda p:p.stat().st_mtime,reverse=True):
            if path.stat().st_mtime<not_before:continue
            message=BytesParser(policy=policy.default).parsebytes(path.read_bytes())
            if email.lower() not in {e.lower() for _,e in getaddresses(message.get_all('to',[]))}:continue
            part=message.get_body(preferencelist=('plain','html'))
            body=html.unescape(part.get_content() if part else '')
            match=re.search(re.escape(config['user_url'])+'/'+route+r'\?[^\s<>"\']+',body)
            if match:return match.group(0)
        time.sleep(.2)
    raise PrerequisiteMissing('Email Pickup did not contain the expected recipient/link; mailbox manual evidence is separate')

def register(suite,config,key,db):
    guest=suite.actor('register-'+key,'user','guest');guest['api_url']=config['api_url']
    page=guest['page'];creds=suite.credentials[key]; checkpoint={}
    def create(case):
        suite.go(guest,'/register','app-auth-page')
        for selector,value in [('#displayName','QC '+key),('#username',creds['username']),('#email',creds['email']),('#password',creds['password']),('#confirmPassword',creds['password'])]:page.locator(selector).fill(value)
        checkpoint['sent_at']=time.time()
        suite.response(guest,'/auth/register',lambda:page.locator('button[type=submit]').click(),method='POST',status=201)
        expect(page.locator('app-result-notice[tone=success]')).to_be_visible()
        assert db.account_count(creds['email'])==1
        account=db.account(creds['email']);assert account and not account['verified']
        checkpoint['user_id']=account['user_id']
        case['resource_ids']=[account['user_id']]
        case['steps']=['Fresh synthetic identity → actual UI registration POST 201','One DB account, pending/unverified','Real recipient-specific Email Pickup trigger; no verification SQL']
        case['mail_manual']='NOT_EXECUTED; Email Pickup automation only'
    if not suite.case(guest,'FULL-REGISTER-'+key.upper(),'AUTH-REG-03','Fresh registration '+key,'Exactly one pending account is created by the UI',create,module='authentication'):raise PrerequisiteMissing('Fresh registration failed')
    if key=='user':
        def unverified(case):
            suite.go(guest,'/login','app-auth-page');page.locator('#email').fill(creds['email']);page.locator('#password').fill(creds['password'])
            response=suite.response(guest,'/auth/login',lambda:page.locator('button[type=submit]').click(),method='POST',status=403)
            assert response.json()['code'] in ('EMAIL_UNVERIFIED','EMAIL_NOT_VERIFIED')
            expect(page.locator('[role=alert]')).to_be_visible()
            assert page.url.endswith('/login')
            case['steps']=['New account before verification → real login','403 email-unverified contract; stays on login']
        suite.case(guest,'FULL-AUTH-UNVERIFIED','AUTH-LOGIN-01','Login before verification','Unverified account cannot log in',unverified,module='authentication')
    def verify(case):
        link=pickup_link(config,creds['email'],'verify-email',checkpoint['sent_at'])
        with page.expect_response(lambda r:urlsplit(r.url).path=='/api/v1/auth/verify-email' and r.request.method=='POST') as response:page.goto(link)
        assert response.value.status==200
        expect(page.locator('app-result-notice[tone=success]')).to_be_visible()
        assert db.account(creds['email'])['verified']
        case['resource_ids']=[checkpoint['user_id']]
        case['steps']=['Read actual recipient-specific Pickup message','Browser opens actual verification link → POST 200','Read DB verified state; keep token out of report/storage']
        case['mail_manual']='NOT_EXECUTED; Email Pickup automation only'
    if not suite.case(guest,'FULL-VERIFY-'+key.upper(),'AUTH-VERIFY-01','Verify new identity '+key,'Real emailed token verifies exactly the registered user',verify,module='authentication'):raise PrerequisiteMissing('Fixture verification failed')
    suite.release_actor(guest)
    return checkpoint['user_id']


def register_fixture(suite, config, key, db):
    """Create a disposable identity without re-executing retained UI cases.

    Delta journeys need independent actors, but registration and verification are
    already retained evidence.  This is deliberately *fixture setup*, not a
    scenario result: it uses the real local API and Email Pickup, records the
    created user ID, and never adds a case to the E2E ledger.
    """
    guest = suite.actor('fixture-register-' + key, 'user', 'guest')
    guest['api_url'] = config['api_url']
    creds = suite.credentials[key]
    sent_at = time.time()
    response = guest['context'].request.post(config['api_url'] + '/auth/register', data={
        'username': creds['username'],
        'email': creds['email'],
        'displayName': 'QC fixture ' + key,
        'password': creds['password'],
    })
    assert response.status == 201, 'Fixture registration HTTP ' + str(response.status)
    account = db.account(creds['email'])
    assert account and not account['verified'] and db.account_count(creds['email']) == 1
    link = pickup_link(config, creds['email'], 'verify-email', sent_at)
    token = parse_qs(urlsplit(link).query).get('token', [''])[0]
    assert token, 'Fixture verification link has no token'
    verified = guest['context'].request.post(config['api_url'] + '/auth/verify-email', data={'token': token})
    assert verified.status == 200, 'Fixture verification HTTP ' + str(verified.status)
    assert db.account(creds['email'])['verified']
    suite.report['setup'].append({
        'actor': 'fixture-register-' + key,
        'status': 'created-via-real-api-email-pickup',
        'scope': 'Delta fixture setup only; AUTH-REG-03 and AUTH-VERIFY-01 were not re-executed as cases',
        'user_id': account['user_id'],
    })
    suite.release_actor(guest)
    return account['user_id']

def auth_deep(suite,config,actors):
    member=actors['member'];guest=suite.actor('auth-boundaries','user','guest');guest['api_url']=config['api_url'];page=guest['page']
    denied=suite.actor('member-admin-denial','admin','guest');denied['api_url']=config['api_url']
    def admin_deny(case):
        p=denied['page']
        suite.go(denied,'/login','app-auth-page');p.locator('#email').fill(suite.credentials['member']['email']);p.locator('#password').fill(suite.credentials['member']['password'])
        result=suite.response(denied,'/auth/login',lambda:p.locator('button[type=submit]').click(),method='POST',status=403)
        assert result.json()['code']=='ADMIN_ACCESS_DENIED'
        expect(p.locator('[role=alert]')).to_be_visible();case['steps']=['Verified ordinary Member → actual Admin login','403 ADMIN_ACCESS_DENIED; no Admin session/route']
    suite.case(denied,'FULL-MEMBER-ADMIN-DENY','AUTH-ADMIN-01','Ordinary Member cannot access Admin','Member role is not silently elevated',admin_deny,module='authentication')
    def forgot_reset(case):
        creds=suite.credentials['member'];original=creds['password'];new_password='QCResetPassword2026!'
        suite.go(guest,'/forgot-password','app-auth-page');page.locator('#email').fill('qc-no-user-'+suite.run_id[:15]+'@example.test')
        absent=suite.response(guest,'/auth/forgot-password',lambda:page.locator('button[type=submit]').click(),method='POST').json()
        suite.go(guest,'/forgot-password','app-auth-page');page.locator('#email').fill(creds['email']);sent_at=time.time()
        existing=suite.response(guest,'/auth/forgot-password',lambda:page.locator('button[type=submit]').click(),method='POST').json()
        assert absent==existing,'Forgot-password leaks existence through contract'
        link=pickup_link(config,creds['email'],'reset-password',sent_at)
        page.goto(link);page.locator('#password').fill(new_password);page.locator('#confirmPassword').fill(new_password)
        suite.response(guest,'/auth/reset-password',lambda:page.locator('button[type=submit]').click(),method='POST')
        expect(page.locator('app-result-notice[tone=success]')).to_be_visible()
        # Token stays in memory; HTTP observers store path/status only.
        page.goto(link);page.locator('#password').fill(original);page.locator('#confirmPassword').fill(original)
        replay=suite.response(guest,'/auth/reset-password',lambda:page.locator('button[type=submit]').click(),method='POST',status=(400,409))
        assert replay.status in (400,409)
        suite.go(guest,'/login','app-auth-page');page.locator('#email').fill(creds['email']);page.locator('#password').fill(original)
        suite.response(guest,'/auth/login',lambda:page.locator('button[type=submit]').click(),method='POST',status=401)
        creds['password']=new_password
        logged=suite.actor('reset-new-password','user','member')
        assert logged['identity']['userId']==member['identity']['userId']
        suite.release_actor(member)
        actors['member']=logged
        case['resource_ids']=[member['identity']['userId']]
        case['steps']=['Unknown/known email → identical response','Actual Pickup reset link → UI resets password','Consumed link replay denied','Old password 401; new password logs into same user ID']
        case['mail_manual']='NOT_EXECUTED; Email Pickup automation only'
    suite.case(guest,'FULL-FORGOT-RESET-REPLAY','AUTH-EXT-01','Forgot/reset with recipient and replay checks','New password works, old/replayed credential cannot change identity',forgot_reset,module='authentication')

def main():
    if hasattr(sys.stdout,'reconfigure'):sys.stdout.reconfigure(encoding='utf-8',errors='replace')
    parser=argparse.ArgumentParser();parser.add_argument('--config',type=Path,required=True);parser.add_argument('--groups',default='auth-deep');parser.add_argument('--headed',action='store_true');parser.add_argument('--resume-run');parser.add_argument('--delta-only',action='store_true',help='Fail closed if a selected group tries to execute retained or excluded scenario evidence.');args=parser.parse_args()
    config=json.loads(args.config.read_text(encoding='utf-8'));db=LocalDb(config)
    if args.delta_only:
        os.environ['HUTUBE_E2E_DELTA_SCOPE']='1'
    suffix=str(int(time.time()))
    creds={key:{'email':'qc.'+key+'.'+suffix+'@example.test','username':'qc_'+key+'_'+suffix,'password':'QCFixturePassword2026!'} for key in ['user','admin','member','reviewer1','reviewer2','target']}
    previous=None;ids={}
    if args.resume_run:
        if not re.fullmatch(r'\d{8}T\d{6}\.\d+Z',args.resume_run):raise ValueError('Invalid owned run ID')
        previous=json.loads((ROOT/'artifacts/runs'/args.resume_run/'report.json').read_text(encoding='utf-8'))
        assert previous.get('environment_kind')=='isolated-local-postgresql-fixtures'
        for key in creds:
            checkpoint=next((c for c in previous['cases'] if c['id']=='FULL-REGISTER-'+key.upper() and c['status']=='passed'), None)
            if checkpoint:
                ids[key]=checkpoint['resource_ids'][0]
            else:
                setup=next(s for s in previous.get('setup', []) if s.get('actor') == 'fixture-register-' + key and s.get('status') == 'created-via-real-api-email-pickup')
                ids[key]=setup['user_id']
            identity=json.loads(db.sql("SELECT json_build_object('email',email,'username',username) FROM users WHERE user_id=:'id'::uuid AND email LIKE 'qc.%@example.test';",{'id':ids[key]}))
            creds[key].update(identity)
        if any(c['id']=='FULL-FORGOT-RESET-REPLAY' and c['status']=='passed' for c in previous['cases']):creds['member']['password']='QCResetPassword2026!'
    os.environ['WEB_E2E_CREDENTIALS']=json.dumps(creds)
    with sync_playwright() as pw:
        suite=LiveSuite(pw,headed=args.headed,environment={'user':config['user_url'],'admin':config['admin_url']},run_dir=config.get('run_dir'))
        suite.flush()
        suite.report['fixture_policy']='Owned local database, local storage, synthetic accounts; bootstrap Super Admin is fixture setup, not tested RBAC behavior'
        suite.report['runtime_rate_limit_note']='Local multi-actor suite uses higher permit counts; this is not rate-limit/performance certification'
        actors={}
        try:
            if previous:
                suite.report['resumed_from']=args.resume_run
                suite.report['fixture_policy']='Resume owned synthetic actors/resources; earlier assertions remain in earlier report and are not newly executed cases'
            else:
                # A delta run owns new synthetic actors but must not rerun the
                # retained registration/verification scenario cards merely to
                # create them.  The fixture helper uses the real API/Pickup
                # path and is intentionally absent from ``cases``.
                registrar = register_fixture if args.delta_only else register
                ids={key:registrar(suite,config,key,db) for key in creds}
            # Only the first admin identity needs SQL bootstrap. Database and
            # connection are hard-restricted to the owned runner cluster.
            db.sql("UPDATE users SET role_id=(SELECT role_id FROM roles WHERE code='super_admin' AND status='active') WHERE user_id=:'id'::uuid AND email LIKE '%@example.test';",{'id':ids['admin']})
            assert db.account(creds['admin']['email'])['role']=='super_admin'
            admin=actors['admin']=suite.actor('admin','admin')
            permissions=suite.api(admin,'get','/admin/permissions').json()
            reviewer_codes=[p['code'] for p in permissions if p['code'].startswith(('moderation.','report.','appeal.')) or p['code'] in ('video.view','channel.view','strike.view','admin.access','system.view_setting')]
            assert 'moderation.approve' in reviewer_codes and 'moderation.reject' in reviewer_codes
            reviewer_role=suite.api(admin,'post','/admin/roles',data={'code':'qc_reviewer_'+suffix,'name':'QC independent reviewer','description':'Only moderation/report/appeal fixture rights','permissionCodes':reviewer_codes,'reason':'Prepare isolated reviewer role'},expected=201).json()
            for key in ['reviewer1','reviewer2']:
                suite.api(admin,'put','/admin/users/'+ids[key]+'/role',data={'roleCode':reviewer_role['code'],'reason':'Synthetic reviewer fixture preparation'})
            actors['owner']=suite.actor('owner','user')
            actors['member']=suite.actor('member','user','member')
            if previous:
                # A stop can land after change-password commits but before its
                # finally restores this synthetic fixture. Recover via the real
                # auth API using only the two known test passwords, never SQL.
                probe=suite.actor('resume-target-credential','user','guest')
                probe['api_url']=config['api_url']
                probe['headers'].update({'X-HuTube-Client':'web','Origin':probe['origin']})
                target_login={'email':creds['target']['email'],'password':creds['target']['password']}
                login=suite.api(probe,'post','/auth/login',data=target_login,expected=(200,401))
                if login.status==401:
                    changed='QCChangedPassword2026!'
                    login=suite.api(probe,'post','/auth/login',data={**target_login,'password':changed})
                    value=login.json()
                    assert value['user']['userId']==ids['target']
                    probe['headers']['Authorization']='Bearer '+value['accessToken']
                    probe['identity']=value['user']
                    suite.api(probe,'post','/account/change-password',data={'currentPassword':changed,'newPassword':creds['target']['password']})
                    suite.report['cleanup'].append({'resource':'interrupted synthetic target password',
                        'status':'restored through actual change-password API','user_id':ids['target']})
                else:
                    probe['identity']=login.json()['user']
                    assert probe['identity']['userId']==ids['target']
                suite.release_actor(probe)
            actors['target']=suite.actor('target','user','target')
            actors['reviewer1']=suite.actor('reviewer1','admin','reviewer1')
            actors['reviewer2']=suite.actor('reviewer2','admin','reviewer2')
            if previous:
                channel_response=suite.api(actors['owner'],'get','/channels/me',expected=(200,404))
                suite.fixtures={'channel':channel_response.json()} if channel_response.status == 200 else {}
                videos=suite.api(actors['owner'],'get','/videos/manage',params={'channelId':suite.fixtures['channel']['channelId'],'page':1,'pageSize':100}).json()['items'] if 'channel' in suite.fixtures else []
                suite.fixtures['videos']=videos
                candidates=[v for v in videos if v['title'].startswith('QC MEDIA ') and v['moderationStatus']=='approved' and v['visibility']=='public' and v['status']=='published']
                if candidates:suite.fixtures['video']=suite.api(actors['owner'],'get','/videos/'+candidates[0]['videoId']).json()
            for group in args.groups.split(','):
                execution={'group':group,'status':'running','meaning':'Execution progress, not a feature PASS'}
                suite.report.setdefault('group_executions',[]).append(execution)
                if group=='auth-deep':
                    auth_deep(suite,config,actors)
                    execution['status']='completed'
                else:
                    import importlib
                    try:
                        importlib.import_module('flows.expanded.'+group.replace('-','_')).run(suite,config,actors)
                        execution['status']='completed'
                    except Exception as group_error:
                        execution['status']='prerequisite-failed'
                        import traceback
                        suite.report.setdefault('group_errors',[]).append({'group':group,'error_type':type(group_error).__name__,
                            'location':[{'file':Path(frame.filename).name,'line':frame.lineno,'function':frame.name}
                                for frame in traceback.extract_tb(group_error.__traceback__)[-6:]]})
                        # A fixture failure is a runner error, not an extra
                        # unreviewed scenario that bypasses delta scope.
                        suite.report['run_error'] = 'GroupPrerequisiteError'
                        print('Group prerequisite failed:', group, type(group_error).__name__, flush=True)
                suite.flush()
        except Exception as error:
            suite.report['run_error']=type(error).__name__
            import traceback
            suite.report['run_error_location']=[{'file':Path(frame.filename).name,'line':frame.lineno,'function':frame.name} for frame in traceback.extract_tb(error.__traceback__)[:5]]
            print('Expanded suite prerequisite:',type(error).__name__,flush=True)
        finally:
            suite.close()
            print('Expanded report:',suite.run_dir/'report.json',flush=True)
            # The owned DB is retained to inspect failures, never restored into
            # the real database or counted as the supplied live identities.
    return int(bool(suite.report['failed'] or suite.report['blocked'] or suite.report.get('run_error')))

if __name__=='__main__':sys.exit(main())
