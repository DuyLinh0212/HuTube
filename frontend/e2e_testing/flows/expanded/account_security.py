from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from flows.expanded.channels import png_bytes

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    actor=suite.actor('password-controller','user','target');twin=suite.actor('password-other-device','user','target');p=actor['page'];old=suite.credentials['target']['password'];new='QCChangedPassword2026!';changed=False
    def avatar(entry):
        suite.go(actor,'/account','app-account-page','/account/profile')
        result=suite.response(actor,'/account/avatar',lambda:p.locator('.channel-avatar-box input[type=file]').set_input_files({'name':'qc-valid.png','mimeType':'image/png','buffer':png_bytes()}),method='POST').json()
        current=suite.api(actor,'get','/account/profile').json();assert current['avatarUrl']
        p.reload();expect(p.locator('app-account-page')).to_be_visible()
        p.wait_for_function('(url)=>[...document.images].some(i=>i.src===new URL(url,location.origin).href&&i.complete&&i.naturalWidth>0)',arg=current['avatarUrl'])
        entry['steps']=['Target actual PNG file input → avatar upload','Persisted profile contains storage URL','Reload actual image decodes successfully']
        entry['resource_ids']=[actor['identity']['userId']]
    case(suite,actor,'ACCOUNT-VALID-AVATAR-DECODE','U-ACCOUNT.01','Valid avatar upload persists and decodes',avatar,'account')
    try:
        def password(entry):
            nonlocal changed
            suite.go(actor,'/account','app-account-page','/account/profile');p.locator('.settings-nav-list > button').nth(5).click()
            p.locator('#cp').fill('QCDeliberatelyWrong2026!');p.locator('#np').fill(new);p.locator('#cnp').fill(new)
            suite.response(actor,'/account/change-password',lambda:p.locator('.password-box button').click(),method='POST',status=(400,401))
            assert suite.api(twin,'get','/auth/me').json()['userId']==actor['identity']['userId']
            p.locator('#cp').fill(old)
            suite.response(actor,'/account/change-password',lambda:p.locator('.password-box button').click(),method='POST');changed=True;suite.credentials['target']['password']=new
            suite.api(twin,'get','/auth/me',expected=401)
            fresh=suite.actor('password-new-credential','user','target');assert fresh['identity']['userId']==actor['identity']['userId'];suite.release_actor(fresh)
            entry['resource_ids']=[actor['identity']['userId']];entry['steps']=['Wrong current password rejected; second device stays valid','Real UI changes password with valid current credential','Other device old JWT revoked','New password authenticates same identity']
        case(suite,actor,'ACCOUNT-PASSWORD-CHANGE-REVOKES-DEVICES','U-ACCOUNT.03','Password change revokes existing devices',password,'account')
    finally:
        if changed:
            restore=suite.actor('password-restore','user','target');suite.api(restore,'post','/account/change-password',data={'currentPassword':new,'newPassword':old});suite.credentials['target']['password']=old;suite.release_actor(restore)
            suite.report['cleanup'].append({'resource':'synthetic target password','status':'restored through actual change-password API'})
        suite.release_actor(actor);suite.release_actor(twin)
        if not actors['target'].get('released'):suite.release_actor(actors['target'])
        actors['target']=suite.actor('target-security-restored','user','target')
