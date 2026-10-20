"""Profile mutation/restore and every persisted preference, on the supplied account."""
from types import SimpleNamespace
from playwright.sync_api import expect
from tests.user_account import run_checks

def run(suite, owner):
    page=owner['page']
    suite.go(owner,'/account','app-account-page','/account/profile')
    def check(case_id,page,action,application,**kwargs):
        def execute(case):
            action()
            case['steps']=[case_id,'Execute profile UI and real API assertions from tests/user_account.py','Record current UI on three viewports']
        return suite.case(owner,'LIVE-'+case_id,'U-ACCOUNT.01',case_id,'Profile UI validation, persistence and restore against original account',execute,module='account')
    profile_report={}
    run_checks(SimpleNamespace(page=page,context=owner['context'],origin=owner['origin'],setup={'api_origin':owner['api_url'].removesuffix('/api/v1')},identity=owner['identity'],credentials=suite.credentials,app='user',report=profile_report,run_dir=suite.run_dir,access_headers=owner['headers'],check=check,write_profile=True))
    suite.report['cleanup'].append({'resource':'profile',**profile_report.get('cleanup',{})})
    page.set_viewport_size(suite.action_viewport)

    def notifications(case):
        suite.go(owner,'/account','app-account-page','/account/notifications')
        page.locator('.settings-nav-list button').nth(1).click()
        original=suite.api(owner,'get','/account/notifications').json()
        keys=['inAppEnabled','emailEnabled','newVideoEnabled','commentReplyEnabled','mentionEnabled','channelActivityEnabled']
        try:
            for index,key in enumerate(keys):
                page.locator('.switches-vertical-list .yt-switch').nth(index).click()
                expect(page.locator('.switches-vertical-list input').nth(index)).to_be_checked(checked=not original[key])
            suite.response(owner,'/account/notifications',lambda:page.locator('.form-buttons .btn-yt-primary').click(),method='PUT')
            suite.go(owner,'/account','app-account-page','/account/notifications')
            page.locator('.settings-nav-list button').nth(1).click()
            changed=suite.api(owner,'get','/account/notifications').json()
            for index,key in enumerate(keys):
                assert changed[key] is not original[key]
                expect(page.locator('.switches-vertical-list input').nth(index)).to_be_checked(checked=changed[key])
            suite.evidence(owner,case,'persisted')
        finally:
            suite.api(owner,'put','/account/notifications',data=original)
            assert suite.api(owner,'get','/account/notifications').json()==original
            suite.report['cleanup'].append({'case':case['id'],'status':'restored','resource':'notification preferences'})
        case['steps']=['Toggle every notification flag','Save via UI','Reload and compare all six flags','Restore exact original values']
    suite.case(owner,'U-ACCOUNT-LIVE-NOTIFICATIONS','U-ACCOUNT.02','All six notification flags save/reload/restore','Every checkbox persists; original account values are restored',notifications,module='account')

    for index,key in enumerate(['keepSubscriptionsPrivate','allowMentions','topFanRanking','celebrateSuperChat']):
        def privacy(case,index=index,key=key):
            endpoint='/account/notifications' if key=='allowMentions' else '/account/settings'
            suite.go(owner,'/account','app-account-page',endpoint)
            page.locator('.settings-nav-list button').nth(3).click()
            checkbox=page.locator('.privacy-toggle-group input').nth(index)
            original_checked=checkbox.is_checked()
            local_key='hutube.privacy.'+key
            local_original=page.evaluate('(key)=>localStorage.getItem(key)',local_key)
            original=suite.api(owner,'get',endpoint).json() if index<2 else None
            changed_key='mentionEnabled' if key=='allowMentions' else key
            try:
                if index<2:
                    suite.response(owner,endpoint,lambda:page.locator('.privacy-toggle-group .yt-switch').nth(index).click(),method='PUT')
                    changed=suite.api(owner,'get',endpoint).json()
                    assert changed[changed_key] is not original[changed_key]
                    assert all(changed[k]==original[k] for k in original if k!=changed_key)
                else:
                    page.locator('.privacy-toggle-group .yt-switch').nth(index).click()
                    assert page.evaluate('(key)=>localStorage.getItem(key)',local_key)==str(not original_checked).lower()
                suite.go(owner,'/account','app-account-page',endpoint)
                page.locator('.settings-nav-list button').nth(3).click()
                expect(page.locator('.privacy-toggle-group input').nth(index)).to_be_checked(checked=not original_checked)
                suite.evidence(owner,case,'persisted')
            finally:
                if index<2:
                    suite.api(owner,'put',endpoint,data=original)
                    assert suite.api(owner,'get',endpoint).json()==original
                else:
                    page.evaluate('(v)=>v.value===null?localStorage.removeItem(v.key):localStorage.setItem(v.key,v.value)',{'key':local_key,'value':local_original})
                suite.report['cleanup'].append({'case':case['id'],'status':'restored','resource':key})
            case['steps']=['Read original checkbox/storage','Toggle '+key,'Assert actual backend or local-storage contract','Reload and compare checkbox','Restore exact original values']
            case['storage_assertion']='Backend API read-back' if index<2 else 'localStorage persistence only; no backend contract in onToggleTopFanRanking/onToggleCelebrateSuperChat'
        suite.case(owner,'U-ACCOUNT-LIVE-PRIVACY-'+key.upper(),'U-ACCOUNT.02','Persist '+key,'Actual preference storage persists through reload and unrelated values remain unchanged',privacy,module='account')

def run_admin(suite, admin):
    page=admin['page']
    for theme in ['dark','light']:
        def change(case,theme=theme):
            suite.go(admin,'/account','app-account-page')
            original=page.locator('#adminThemeSelect').input_value()
            try:
                page.locator('#adminThemeSelect').select_option(theme)
                expect(page.locator('html')).to_have_attribute('data-theme',theme)
                page.reload()
                expect(page.locator('#adminThemeSelect')).to_have_value(theme)
                expect(page.locator('html')).to_have_attribute('data-theme',theme)
                suite.evidence(admin,case,'theme-persisted')
            finally:
                page.locator('#adminThemeSelect').select_option(original)
            case['steps']=['Select '+theme,'Assert actual root theme','Reload → theme remains','Restore original']
        suite.case(admin,'A-ACCOUNT-THEME-'+theme.upper(),'A-ACCOUNT.01','Admin '+theme+' theme persistence','Theme applies to document and survives reload',change,module='account')
    for language in ['en','vi']:
        def change(case,language=language):
            suite.go(admin,'/account','app-account-page')
            original=page.locator('#adminLangSelect').input_value()
            try:
                page.locator('#adminLangSelect').select_option(language)
                expect(page.locator('app-account-page h1')).to_have_text('Admin Account' if language=='en' else 'Tài khoản quản trị')
                page.reload()
                expect(page.locator('#adminLangSelect')).to_have_value(language)
                suite.evidence(admin,case,'language-persisted')
            finally:
                page.locator('#adminLangSelect').select_option(original)
            case['steps']=['Select '+language,'Assert translated heading','Reload → language remains','Restore original']
        suite.case(admin,'A-ACCOUNT-LANGUAGE-'+language.upper(),'A-ACCOUNT.01','Admin language '+language,'Translated UI and selected language survive reload',change,module='account')
