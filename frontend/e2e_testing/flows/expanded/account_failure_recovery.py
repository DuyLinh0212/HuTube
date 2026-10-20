"""Actual request transport failures must not persist profile/settings or show success."""
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    actor=suite.actor('account-failure-recovery','user','member');p=actor['page']
    try:
        def read(entry):
            expected=suite.api(actor,'get','/account/profile').json();blocked=[]
            def drop(route):
                blocked.append(route.request.method);route.abort('internetdisconnected')
            route='**/api/v1/account/profile';p.route(route,drop)
            try:
                p.goto(actor['origin']+'/account');expect(p.locator('app-account-page [role=alert]')).to_be_visible()
                assert blocked and all(method=='GET' for method in blocked),'Expected at least one actual profile GET to fail'
                entry['failed_profile_get_count']=len(blocked)
                assert p.locator('.yt-alert-success').count()==0
                suite.evidence(actor,entry,'profile-read-transport-error')
            finally:p.unroute(route,drop)
            actual=suite.go(actor,'/account','app-account-page','/account/profile')
            assert actual['userId']==expected['userId'] and actual['displayName']==expected['displayName']
            expect(p.locator('.channel-display-name')).to_have_text(expected['displayName'])
            expect(p.locator('app-account-page [role=alert]')).to_have_count(0)
            entry['steps']=['Abort only actual profile GET transport, without fabricating an HTTP response','Error visible and no success feedback','Restore network and reload; real 200 shows exact persisted identity/name and clears prior error']
        case(suite,actor,'ACCOUNT-PROFILE-GET-NETWORK-RELOAD','U-ACCOUNT.01','Profile read failure is visible and recovers on actual reload',read,'account')
        def save(entry):
            baseline=suite.go(actor,'/account','app-account-page','/account/profile')
            p.locator('.yt-action-link-btn.primary-action').click();p.locator('#dn').fill('QC lỗi mạng chưa lưu')
            p.locator('#bio').fill('Nội dung chưa được gửi tới máy chủ')
            blocked=[]
            def drop(route):
                assert route.request.method=='PATCH';blocked.append(True);route.abort('internetdisconnected')
            route='**/api/v1/account/profile';p.route(route,drop)
            try:
                p.locator('.profile-inline-form .btn-yt-primary').click()
                expect(p.locator('app-account-page [role=alert]')).to_be_visible()
                expect(p.locator('.profile-inline-form .btn-yt-primary')).to_be_enabled()
                expect(p.locator('#dn')).to_have_value('QC lỗi mạng chưa lưu');assert len(blocked)==1
                assert p.locator('.yt-alert-success').count()==0
                persisted=suite.api(actor,'get','/account/profile').json()
                assert persisted==baseline
                suite.evidence(actor,entry,'profile-save-error-retains-draft')
            finally:p.unroute(route,drop)
            p.locator('.profile-inline-form .btn-yt-secondary').click()
            current=suite.go(actor,'/account','app-account-page','/account/profile');assert current==baseline
            expect(p.locator('.channel-display-name')).to_have_text(baseline['displayName'])
            entry['steps']=['Edit actual Unicode profile fields then abort PATCH transport only','Error visible, busy released, draft remains and no success','Direct real API read proves every profile field unchanged','Cancel draft and reload exact original profile; no fixture restore mutation needed']
        case(suite,actor,'ACCOUNT-PROFILE-SAVE-NETWORK-NO-MUTATION','U-ACCOUNT.01','Failed profile save retains editable draft and never mutates persisted account',save,'account')
        def notifications(entry):
            original=suite.api(actor,'get','/account/notifications').json()
            suite.go(actor,'/account','app-account-page','/account/notifications')
            p.locator('.settings-nav-list button').nth(1).click()
            p.locator('.switches-vertical-list .yt-switch').first.click()
            blocked=[]
            def drop(route):
                assert route.request.method=='PUT';blocked.append(True);route.abort('internetdisconnected')
            route='**/api/v1/account/notifications';p.route(route,drop)
            try:
                p.locator('.form-buttons .btn-yt-primary').click()
                expect(p.locator('app-account-page [role=alert]')).to_be_visible()
                expect(p.locator('.form-buttons .btn-yt-primary')).to_be_enabled();assert len(blocked)==1
                assert p.locator('.yt-alert-success').count()==0
                assert suite.api(actor,'get','/account/notifications').json()==original
            finally:p.unroute(route,drop)
            suite.go(actor,'/account','app-account-page','/account/notifications');p.locator('.settings-nav-list button').nth(1).click()
            expect(p.locator('.switches-vertical-list input').first).to_be_checked(checked=original['inAppEnabled'])
            entry['steps']=['Toggle actual notification option then abort PUT transport','Visible error, busy released and no success','All eleven actual API flags remain unchanged','Reload resets unsaved toggle to original persisted value']
        case(suite,actor,'ACCOUNT-NOTIFICATION-SAVE-NETWORK-NO-MUTATION','U-ACCOUNT.02','Failed notification save cannot claim success or change persisted flags',notifications,'account')
    finally:suite.release_actor(actor)
