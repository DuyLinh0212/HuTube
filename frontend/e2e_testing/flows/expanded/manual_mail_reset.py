"""Real mailbox password reset, completed by recipient; OTP and password stay private."""
import json
import time
from datetime import datetime,timezone
from support.local_db import LocalDb
from support.live_suite import PrerequisiteMissing
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__);recipient='ngodanh0311@gmail.com'
    assert config.get('real_mail_probe') and config.get('manual_mail_recipient')==recipient
    db=LocalDb(config);account=db.account(recipient)
    if not account or not account['verified']:raise PrerequisiteMissing('Real recipient verification must be completed first')
    uid=account['user_id'];guest=suite.actor('manual-mail-forgot','user','guest');guest['api_url']=config['api_url']
    before=db.sql("SELECT coalesce(password_reset_used_at::text,'') FROM users WHERE user_id=:'uid'::uuid;",{'uid':uid})
    def send(entry):
        p=guest['page'];suite.go(guest,'/forgot-password','app-auth-page');p.locator('#email').fill(recipient)
        suite.response(guest,'/auth/forgot-password',lambda:p.locator('button[type=submit]').click(),method='POST')
        entry['resource_ids']=[uid];entry['mail_manual']='Real provider accepted; recipient inbox confirmation is a separate assertion'
        entry['steps']=['Verified QC recipient only','Actual Forgot UI POST 200 using configured real mail transport','Automation does not read the OTP from Pickup or inbox']
        (suite.run_dir/'manual-mail-ready.json').write_text(json.dumps({'stage':'reset','recipient':recipient,
            'subject':'Mã OTP đặt lại mật khẩu Dalitu','accepted_at':datetime.now(timezone.utc).isoformat()}),encoding='utf-8')
    if not case(suite,guest,'MAIL-REAL-PROVIDER-RESET','AUTH-EXT-01','Send actual password reset to approved inbox',send,'mail'):return
    def finish(entry):
        p=guest['page'];deadline=time.monotonic()+600
        while time.monotonic()<deadline:
            used=db.sql("SELECT coalesce(password_reset_used_at::text,'') FROM users WHERE user_id=:'uid'::uuid;",{'uid':uid})
            sessions=int(db.sql("SELECT count(*) FROM refresh_tokens WHERE user_id=:'uid'::uuid AND revoked_at IS NULL AND issued_at>(SELECT password_reset_used_at FROM users WHERE user_id=:'uid'::uuid);",{'uid':uid}))
            if used and used!=before and sessions>0:break
            p.wait_for_timeout(2000)
        else:raise PrerequisiteMissing('Recipient has not completed real reset and a fresh login within this run')
        entry['resource_ids']=[uid];entry['mail_manual']='Actual recipient OTP consumed and new authenticated session issued afterwards; recipient chooses private QC password'
        entry['steps']=['Recipient enters the OTP from the delivered email in the reset form', 'OTP changes to used without SQL mutation',
            'Fresh user session is issued after reset using recipient-chosen password','Automation never reads email OTP or new password']
    case(suite,guest,'MAIL-MANUAL-RESET-OPEN-LOGIN','AUTH-EXT-01','Real inbox OTP completes reset and a fresh login',finish,'mail')
