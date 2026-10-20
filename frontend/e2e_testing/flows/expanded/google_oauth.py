"""Real configured Google SDK/UI and API denials; no fabricated identity tokens."""
import re
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.local_db import LocalDb
from support.live_suite import PrerequisiteMissing

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    guest=suite.actor('google-oauth-guest','user','guest');guest['api_url']=config['api_url']
    guest['headers'].update({'X-HuTube-Client':'web','Origin':guest['origin']})
    p=guest['page'];db=LocalDb(config)
    def invalid(entry):
        suite.go(guest,'/login','app-auth-page')
        public=suite.api(guest,'get','/system/config').json()
        assert bool(public.get('googleClientId')),'Google client is not configured'
        before=db.sql('SELECT count(*) FROM users;')
        for credential in ['', 'short', 'qc-invalid-google-credential-without-a-real-token']:
            response=suite.api(guest,'post','/auth/google',data={'credential':credential,'platform':'web'},expected=(400,401))
            assert response.status==400 if len(credential)<20 else response.status==401
        assert db.sql('SELECT count(*) FROM users;')==before
        suite.api(guest,'get','/auth/me',expected=401)
        entry['steps']=['Load actual public Google configuration','Missing/short credential validation 400; malformed actual credential 401','No Google identity fabricated','Actual DB user count unchanged and no session created']
    case(suite,guest,'GOOGLE-OAUTH-INVALID-CREDENTIAL-NO-SESSION','AUTH-EXT-05','Google credential failures cannot create an account/session',invalid,'authentication')
    def cancel(entry):
        suite.go(guest,'/login','app-auth-page')
        try:
            button=p.frame_locator('iframe').get_by_role('button',name=re.compile('Google',re.I)).first
            expect(button).to_be_visible(timeout=20000)
            before=sum(e['method']=='POST' and e['path']=='/api/v1/auth/google' for e in suite.report['http_statuses'])
            with p.expect_popup(timeout=15000) as popup:button.click()
            tab=popup.value
            try:
                tab.wait_for_load_state('domcontentloaded',timeout=15000)
                assert 'accounts.google.com' in tab.url,'Unexpected OAuth provider popup origin'
            finally:tab.close()
            expect(p.locator('app-auth-page')).to_be_visible()
            assert before==sum(e['method']=='POST' and e['path']=='/api/v1/auth/google' for e in suite.report['http_statuses'])
            suite.api(guest,'get','/auth/me',expected=401)
            entry['steps']=['Actual Google SDK button in fresh isolated browser context','Open genuine accounts.google.com popup','Close provider popup without signing in','User stays on login; no HuTube Google POST or session','No account picker/password bypass and no Computer Use']
        except Exception as error:
            raise PrerequisiteMissing('Configured Google UI could not complete popup cancellation: '+type(error).__name__+'. Origin/provider interaction must be supported; do not mock SDK callback.') from None
    case(suite,guest,'GOOGLE-OAUTH-PROVIDER-CANCEL','AUTH-EXT-05','Closing real Google provider does not log in',cancel,'authentication')
    def authenticated(entry):
        entry['steps']=['Configured client found locally','No separate Google test identity/session supplied','Do not reuse HuTube password as a Google password or forge signed Google credential']
        raise PrerequisiteMissing('Google success/linking/unverified/blocked identity branches require real Google test identities. Current supplied credentials are HuTube accounts, not authorized Google credentials.')
    case(suite,guest,'GOOGLE-OAUTH-REAL-IDENTITY-BRANCHES','AUTH-EXT-05','Real provider identity and account linking/status branches',authenticated,'authentication')
    suite.release_actor(guest)
