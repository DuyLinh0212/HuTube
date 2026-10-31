import time
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from tests.full_functional import pickup_link, pickup_code
from support.local_db import LocalDb

def run(suite,config,actors):
    snapshot_module(suite,__file__);db=LocalDb(config)
    guest=suite.actor('expired-link-guest','user','guest');guest['api_url']=config['api_url'];p=guest['page']
    def verify_expired(entry):
        stamp=str(int(time.time()));email='qc.expired.'+stamp+'@example.test';sent=time.time()
        result=suite.api(guest,'post','/auth/register',data={'username':'qc_expired_'+stamp,'email':email,'displayName':'QC expired link','password':'QCExpiredFixture2026!'},expected=201).json()
        uid=result['user']['userId'] if 'user' in result else db.account(email)['user_id']
        link=pickup_link(config,email,'verify-email',sent)
        # Deterministic expiry precondition, scoped to this newly created fixture.
        # The tested result still comes from actual browser/API/backend clock.
        db.sql("UPDATE users SET email_verification_expires_at=now()-interval '1 minute' WHERE user_id=:'id'::uuid AND email_verification_used_at IS NULL AND email LIKE 'qc.%@example.test';",{'id':uid})
        response=suite.response(guest,'/auth/verify-email',lambda:p.goto(link),method='POST',status=400)
        expect(p.locator('[role=alert]')).to_be_visible();assert not db.account(email)['verified']
        entry['resource_ids']=[uid];entry['steps']=['Prepare real registration/email verification token','Owned fixture only: expiry before backend clock','Browser follows genuine expired token','Actual API rejects; account stays unverified']
        entry['fixture_preparation']='Expiry timestamp adjusted in isolated owned DB; no status/verification result was seeded'
        entry['mail_manual']='NOT_EXECUTED; automated recipient-specific Pickup'
    case(suite,guest,'AUTH-VERIFY-EXPIRED','AUTH-VERIFY-01','Expired verification link cannot activate account',verify_expired,'authentication')
    def reset_expired(entry):
        member=actors['member'];email=member['identity']['email'];sent=time.time()
        suite.api(guest,'post','/auth/forgot-password',data={'email':email})
        code=pickup_code(config,email,sent);uid=member['identity']['userId']
        db.sql("UPDATE users SET password_reset_expires_at=now()-interval '1 minute' WHERE user_id=:'id'::uuid AND password_reset_used_at IS NULL AND email LIKE 'qc.%@example.test';",{'id':uid})
        suite.go(guest,'/reset-password?email='+email,'app-auth-page');p.locator('#resetCode').fill(code);p.locator('#password').fill('QCExpiredMustNotApply2026!');p.locator('#confirmPassword').fill('QCExpiredMustNotApply2026!')
        suite.response(guest,'/auth/reset-password',lambda:p.locator('button[type=submit]').click(),method='POST',status=400)
        expect(p.locator('[role=alert]')).to_be_visible()
        fresh=suite.actor('expired-reset-current-password','user','member');assert fresh['identity']['userId']==uid;suite.release_actor(fresh)
        entry['resource_ids']=[uid];entry['steps']=['Actual forgot-password creates recipient OTP','Prepare expiry in owned fixture DB','Actual UI reset rejects expired OTP','Current password still logs into same identity']
        entry['fixture_preparation']='Expiry timestamp adjusted in isolated owned DB; password was not seeded/changed'
        entry['mail_manual']='NOT_EXECUTED; automated recipient-specific Pickup'
    case(suite,guest,'AUTH-RESET-EXPIRED','AUTH-EXT-01','Expired reset OTP cannot replace password',reset_expired,'authentication')
    suite.release_actor(guest)
