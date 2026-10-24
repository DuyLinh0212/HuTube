"""Verify User theme/language preferences persist through drawer, route reload and API."""
import re
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__);owner=actors['owner'];p=owner['page']
    def run_case(entry):
        def read_preferences():
            # Read through the real page interceptor so a browser token refresh
            # is reflected in the request. A direct API helper would keep its
            # own bearer header and could report a false 401 after that refresh.
            return suite.go(owner,'/account','app-account-page','/account/settings')

        def put_preferences(values):
            last_error=None
            for attempt in range(2):
                try:
                    return suite.api(owner,'put','/account/settings',data=values)
                except AssertionError as error:
                    if 'Read-back HTTP 401 /account/settings' not in str(error) or attempt:
                        raise
                    last_error=error
                    # A UI navigation refreshes the in-memory token and the
                    # suite's actor header before retrying a cleanup write.
                    read_preferences()
            raise last_error

        observed_baseline=read_preferences()
        baseline={**observed_baseline,**config.get('account_preferences_restore',{})}
        if any(observed_baseline.get(key)!=baseline.get(key) for key in ('theme','language')):
            # Recover the exact baseline captured before an interrupted prior
            # attempt so this test starts and ends without leaking fixture data.
            put_preferences({key:baseline[key] for key in ('theme','language')})
            recovered=read_preferences()
            assert all(recovered[key]==baseline[key] for key in ('theme','language')), 'Could not recover the captured Account preference baseline'
        current={key:baseline[key] for key in ('theme','language')}

        def toggle(label):
            if p.locator('#account-drawer').count()==0 or not p.locator('#account-drawer').is_visible():
                p.locator('.top-avatar').click()
            drawer=p.locator('#account-drawer');expect(drawer).to_be_visible()
            button=drawer.locator('button.drawer-action').filter(has_text=re.compile(label,re.I));expect(button).to_have_count(1)
            return suite.response(owner,'/account/settings',lambda:button.click(),method='PUT')

        def restore_preferences():
            if all(current[key]==baseline[key] for key in ('theme','language')):
                return
            if current['language']!=baseline['language']:
                response=toggle('Language|Ngôn ngữ')
                assert response.status==200, 'Restore language HTTP '+str(response.status)
                current['language']=baseline['language']
            if current['theme']!=baseline['theme']:
                put_preferences({'theme':baseline['theme']})
                current['theme']=baseline['theme']
            restored=read_preferences()
            assert all(restored[key]==baseline[key] for key in ('theme','language')), 'Preferences did not restore to their original values'

        theme='light' if baseline['theme']=='dark' else 'dark'
        language='en' if baseline['language']=='vi' else 'vi'
        try:
            response=toggle('Appearance|Giao diện');assert response.status==200
            current['theme']=theme
            persisted=read_preferences()
            assert persisted['theme']==theme, 'Theme did not persist after account route reload'
            expect(p.locator('html')).to_have_attribute('data-theme',theme)
            response=toggle('Language|Ngôn ngữ');assert response.status==200
            current['language']=language
            persisted=read_preferences()
            assert persisted['language']==language, 'Language did not persist after account route reload'
            expect(p.locator('.settings-sidebar-heading')).to_have_text('Settings' if language=='en' else 'Cài đặt')
            expect(p.locator('html')).to_have_attribute('data-theme',theme)
            p.goto(owner['origin']+'/home');expect(p.locator('app-home-page')).to_be_visible()
            expect(p.locator('html')).to_have_attribute('data-theme',theme)
            p.reload();expect(p.locator('app-home-page')).to_be_visible()
            expect(p.locator('html')).to_have_attribute('data-theme',theme)
            persisted=read_preferences()
            assert persisted['theme']==theme and persisted['language']==language, 'Preferences changed after Home navigation/reload'
            expect(p.locator('.settings-sidebar-heading')).to_have_text('Settings' if language=='en' else 'Cài đặt')
            entry['assertions']=[
                'Original preferences read from the actual Account page GET /account/settings response; any state left by an interrupted prior attempt was restored first',
                'Theme and language each changed through the authenticated account drawer; actual PUT responses were HTTP 200',
                'After each account-route reload, GET /account/settings and rendered theme/language matched the selected value',
                'Home navigation and reload retained the selected theme; returning to Account retained both persisted preferences',
                'Original theme and language restored through authenticated settings update and read back after the case'
            ]
            entry['steps']=['Read original settings via the Account page','Toggle theme and verify persisted value after full route reload','Toggle language and verify translated Account heading after full route reload','Navigate to Home, reload, then return to Account and verify both values','Capture changed-state desktop/tablet/mobile evidence; restore original settings']
            entry['preference_before']={k:baseline[k] for k in ('theme','language')};entry['preference_during']={'theme':theme,'language':language}
            suite.evidence(owner,entry,'preferences-changed')
        finally:
            restore_preferences()
    case(suite,owner,'ACCOUNT-PREFERENCE-LANGUAGE-THEME-CROSS-ROUTE','U-ACCOUNT.02','Theme and language persist through actual shared settings',run_case,'account')
