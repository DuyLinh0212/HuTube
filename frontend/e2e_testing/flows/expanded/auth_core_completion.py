"""Explicit field and no-mutation clauses not asserted by the old generic alert tests."""
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.local_db import LocalDb

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    guest=suite.actor('auth-core-completion','user','guest');p=guest['page'];db=LocalDb(config)
    def attempts():
        return sum(r['actor']==guest['name'] and r['method']=='POST' and r['path']=='/api/v1/auth/register' for r in suite.report['http_statuses'])
    try:
        def required(entry):
            suite.go(guest,'/register','app-auth-page');before=attempts()
            p.locator('button[type=submit]').click()
            for name in ['username','email','displayName','password','confirmPassword']:
                field=p.locator('#'+name)
                expect(field).to_have_class(__import__('re').compile(r'\bng-invalid\b'))
                if field.get_attribute('aria-invalid') is not None:
                    expect(field).to_have_attribute('aria-invalid','true')
                assert not field.evaluate('(e)=>e.validity.valid')
            assert attempts()==before
            entry['steps']=['Empty real registration form submitted','Every required field has invalid Angular/native validity; exposed aria-invalid states agree','No registration POST issued']
        case(suite,guest,'AUTH-REGISTER-ALL-FIELD-REQUIRED','AUTH-REG-01','Each required registration field is invalid without a POST',required,'authentication')
        def mismatch(entry):
            suite.go(guest,'/register','app-auth-page')
            data={'username':'qc_mismatch_'+suite.run_id[9:15],'email':('qc.mismatch.'+suite.run_id+'@example.test').lower(),
                'displayName':'QC Unicode Đăng ký','password':'QCMismatchFixture2026!','confirmPassword':'QCDifferentFixture2026!'}
            for name,value in data.items():p.locator('#'+name).fill(value)
            before=attempts();p.locator('button[type=submit]').click()
            expect(p.locator('[role=alert]')).to_contain_text('Mật khẩu xác nhận chưa khớp.')
            assert attempts()==before
            assert db.account_count(data['email'])==0
            entry['steps']=['Fill valid independent synthetic registration except mismatching confirmation','Mismatch error visible after submit','No POST and no user exists for exact fixture email']
        case(suite,guest,'AUTH-REGISTER-MISMATCH-FIELD-NO-USER','AUTH-REG-02','Mismatched confirmation creates no account',mismatch,'authentication')
        def duplicate(entry):
            existing=actors['member']['identity'];email=existing['email'];assert db.account_count(email)==1
            before_id=db.account(email)['user_id'];new_email=('qc.duplicate.'+suite.run_id+'@example.test').lower()
            data={'username':existing['username'],'email':email,'displayName':'QC duplicate denied',
                  'password':'QCDuplicateBoundary2026!','confirmPassword':'QCDuplicateBoundary2026!'}
            outcomes=[]
            for kind in ['both','email','username']:
                fields=dict(data)
                if kind=='email':fields['username']='qc_dup_'+suite.run_id[9:15]
                if kind=='username':fields['email']=new_email
                suite.go(guest,'/register','app-auth-page')
                for name,value in fields.items():p.locator('#'+name).fill(value)
                before=attempts()
                response=suite.response(guest,'/auth/register',lambda:p.locator('button[type=submit]').click(),method='POST',status=409)
                code=response.json()['code'];assert code in ['EMAIL_ALREADY_EXISTS','USERNAME_ALREADY_EXISTS']
                if kind=='email':assert code=='EMAIL_ALREADY_EXISTS'
                if kind=='username':assert code=='USERNAME_ALREADY_EXISTS'
                expect(p.locator('[role=alert]')).to_be_visible();assert attempts()==before+1
                assert db.account_count(email)==1 and db.account(email)['user_id']==before_id
                assert db.account_count(new_email)==0
                assert p.url.split('?')[0].endswith('/register')
                outcomes.append({'branch':kind,'status':response.status,'code':code})
            entry['outcomes']=outcomes;entry['resource_ids']=[before_id]
            entry['steps']=['Actual UI submits duplicate email+username, email-only and username-only branches','Each sends exactly one request and returns exact 409 uniqueness code with visible error','Original account count remains exactly one with unchanged ID; attempted new email has zero accounts','No success navigation or duplicate user']
        case(suite,guest,'AUTH-REGISTER-DUPLICATE-COUNT-IDENTITY','AUTH-REG-04','Every registration uniqueness branch preserves the single original account',duplicate,'authentication')
    finally:suite.release_actor(guest)
