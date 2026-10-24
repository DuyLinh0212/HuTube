"""Download preferences, clipboard and invalid avatar files on the real UI."""
from playwright.sync_api import expect
from support.actor_cleanup import close_finished_auth_tabs

def run(suite,owner):
    close_finished_auth_tabs(suite)
    page=owner['page']
    for kind,name,mime,buffer in [('mime','qc-invalid.txt','text/plain',b'not an image'),('empty','qc-empty.png','image/png',b''),('size','qc-oversize.png','image/png',b'0'*(5*1024*1024+1))]:
        def avatar(case,kind=kind,name=name,mime=mime,buffer=buffer):
            before=suite.go(owner,'/account','app-account-page','/account/profile')
            action=lambda:page.locator('.channel-avatar-box input[type=file]').set_input_files({'name':name,'mimeType':mime,'buffer':buffer})
            if kind=='size': action()
            else: suite.response(owner,'/account/avatar',action,method='POST',status=(400,413,415,422))
            expect(page.locator('app-result-notice[tone=error]')).to_be_visible()
            suite.evidence(owner,case,'invalid-file-error')
            after=suite.api(owner,'get','/account/profile').json()
            assert after['avatarUrl']==before['avatarUrl']
            suite.response(owner,'/account/profile',page.reload)
            assert suite.api(owner,'get','/account/profile').json()['avatarUrl']==before['avatarUrl']
            case['steps']=['Profile → actual file input '+kind,'Assert validation/error and unchanged avatar URL','Reload → original avatar remains persisted']
            case['input_data']={'file_name':name,'mime':mime,'bytes':len(buffer)}
        suite.case(owner,'LIVE-ACCOUNT-AVATAR-INVALID-'+kind.upper(),'U-ACCOUNT.01','Avatar invalid '+kind,'Invalid avatar file is rejected and cannot change persisted profile',avatar,module='account')
    suite.go(owner,'/account','app-account-page','/account/profile')
    keys=['hutube.downloads.quality','hutube.downloads.smart']
    original={key:page.evaluate('(key)=>localStorage.getItem(key)',key) for key in keys}
    try:
        for quality in ['ask','1080p','720p','480p','144p']:
            def select(case,quality=quality):
                suite.go(owner,'/account','app-account-page')
                page.locator('.settings-nav-list > button').nth(2).click()
                page.locator('.yt-radio-item').filter(has=page.locator('input[value="'+quality+'"]').first).click()
                assert page.evaluate('()=>localStorage.getItem("hutube.downloads.quality")')==quality
                page.reload(); expect(page.locator('app-account-page')).to_be_visible()
                page.locator('.settings-nav-list > button').nth(2).click()
                expect(page.locator('input[name=downloadQuality][value="'+quality+'"]').first).to_be_checked()
                case['storage_assertion']='localStorage hutube.downloads.quality equals chosen quality after reload; actual downloads/entitlement are separate unexecuted branches'
                case['steps']=['Downloads tab → choose '+quality,'Assert local preference storage','Reload → radio restores selected quality']
            suite.case(owner,'LIVE-ACCOUNT-DOWNLOAD-QUALITY-'+quality.upper(),'U-ACCOUNT.04','Download preference '+quality,'Chosen local download preference persists; no download success is implied',select,module='account')
        def smart(case):
            for value in [True,False]:
                suite.go(owner,'/account','app-account-page')
                page.locator('.settings-nav-list > button').nth(2).click()
                checkbox=page.locator('.privacy-toggle-group input[type=checkbox]')
                if checkbox.is_checked()!=value:
                    page.locator('.privacy-toggle-group label.yt-switch').click()
                assert page.evaluate('()=>localStorage.getItem("hutube.downloads.smart")')==str(value).lower()
                page.reload(); expect(page.locator('app-account-page')).to_be_visible()
                page.locator('.settings-nav-list > button').nth(2).click()
                expect(page.locator('.privacy-toggle-group input[type=checkbox]')).to_be_checked(checked=value)
                suite.evidence(owner,case,'smart-'+str(value).lower())
            case['storage_assertion']='localStorage hutube.downloads.smart toggles true/false and restores after reload'
            case['steps']=['Smart downloads on and off','Assert local preference','Reload both states → checkbox agrees']
        suite.case(owner,'LIVE-ACCOUNT-DOWNLOAD-SMART','U-ACCOUNT.04','Smart download local preference','Both boolean preferences persist through reload',smart,module='account')
    finally:
        for key,value in original.items():
            page.evaluate('([key,value])=>value===null?localStorage.removeItem(key):localStorage.setItem(key,value)',[key,value])
        suite.report['cleanup'].append({'resource':'download local preferences','status':'restored'})
    def clipboard(case):
        suite.go(owner,'/account','app-account-page')
        page.locator('.settings-nav-list > button').nth(5).click()
        page.locator('.btn-copy').first.click()
        copied=page.evaluate('()=>navigator.clipboard.readText()')
        assert copied==owner['identity']['userId']
        expect(page.locator('app-result-notice[tone=success]')).to_be_visible()
        case['steps']=['Advanced tab → Copy user ID','Read actual browser clipboard','Compare exact authenticated user ID']
    suite.case(owner,'LIVE-ACCOUNT-COPY-ID','U-ACCOUNT.02','Actual clipboard user ID','Copy writes the exact authenticated identity to the real clipboard',clipboard,module='account')
