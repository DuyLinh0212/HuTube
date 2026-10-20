"""User-authorized real delivery to one recipient; no Pickup/token extraction."""
import json
import secrets
import time
from datetime import datetime,timezone
from playwright.sync_api import expect
from support.local_db import LocalDb
from support.live_suite import PrerequisiteMissing
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    recipient='ngodanh0311@gmail.com'
    assert config.get('real_mail_probe') is True and config.get('manual_mail_recipient')==recipient
    db=LocalDb(config);guest=suite.actor('manual-mail-register','user','guest');guest['api_url']=config['api_url']
    password=secrets.token_urlsafe(24)+'!A1'
    suite.credentials['manual_mail']={'email':recipient,'password':password}
    existing=db.account(recipient)
    def send(entry):
        if existing:raise PrerequisiteMissing('Recipient already exists in QC DB; preserve it and review owned previous mail run before retry')
        p=guest['page'];suite.go(guest,'/register','app-auth-page')
        p.locator('#displayName').fill('HuTube QC — kiểm tra hộp thư thật')
        p.locator('#email').fill(recipient);p.locator('#username').fill('qc_mail_'+suite.run_id[9:15])
        p.locator('#password').fill(password);p.locator('#confirmPassword').fill(password)
        p.locator('#confirmPassword').press('Tab')
        suite.response(guest,'/auth/register',lambda:p.locator('button[type=submit]').click(),method='POST',status=201)
        actual=db.account(recipient);assert actual and not actual['verified']
        entry['resource_ids']=[actual['user_id']];entry['mail_manual']='Provider accepted verification delivery; recipient inbox not yet certified'
        entry['steps']=['User authorized this exact recipient','Real UI registration with real configured mail transport',
            '201 only after AuthEmailSender completes; account remains pending','No Pickup/email-token read']
        (suite.run_dir/'manual-mail-ready.json').write_text(json.dumps({'stage':'verification','recipient':recipient,
            'subject':'Xác minh email HuTube','accepted_at':datetime.now(timezone.utc).isoformat()}),encoding='utf-8')
    if not case(suite,guest,'MAIL-REAL-PROVIDER-VERIFICATION','AUTH-REG-03','Send verification through real configured provider',send,'mail'):return
    def verify(entry):
        deadline=time.monotonic()+600
        while time.monotonic()<deadline:
            actual=db.account(recipient)
            if actual and actual['verified']:break
            guest['page'].wait_for_timeout(2000)
        else:raise PrerequisiteMissing('Recipient has not opened/completed the real verification link within this run')
        fresh=suite.actor('manual-mail-verified-login','user','manual_mail')
        assert suite.api(fresh,'get','/auth/me').json()['email']==recipient
        entry['resource_ids']=[actual['user_id']];entry['mail_manual']='Recipient opened real inbox verification link; backend verified; no token obtained by automation'
        entry['steps']=['Wait for recipient to open the delivered link','DB changes pending→verified without fixture mutation',
            'Fresh real User login succeeds with original QC credential','Recipient identity matches /auth/me']
        suite.release_actor(fresh)
    case(suite,guest,'MAIL-MANUAL-VERIFY-OPEN-LINK','AUTH-VERIFY-01','Recipient completes verification from actual inbox',verify,'mail')
