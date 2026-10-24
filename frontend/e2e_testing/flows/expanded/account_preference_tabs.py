"""Verify Account tabs keep the selected theme and language across navigation."""
import re
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module


def run(suite,config,actors):
    snapshot_module(suite,__file__);owner=actors['owner'];p=owner['page']

    def run_case(entry):
        def read_preferences():
            return suite.go(owner,'/account','app-account-page','/account/settings')

        def put_preferences(values):
            for attempt in range(2):
                try:
                    return suite.api(owner,'put','/account/settings',data=values)
                except AssertionError as error:
                    if 'Read-back HTTP 401 /account/settings' not in str(error) or attempt:
                        raise
                    read_preferences()

        observed=read_preferences()
        baseline={**observed,**config.get('account_preferences_restore',{})}
        if any(observed.get(key)!=baseline.get(key) for key in ('theme','language')):
            put_preferences({key:baseline[key] for key in ('theme','language')})
            observed=read_preferences()
            assert all(observed[key]==baseline[key] for key in ('theme','language')), 'Could not restore the captured Account preference baseline'

        original_local_theme=p.evaluate("localStorage.getItem('hutube_theme')")
        original_document_theme=p.locator('html').get_attribute('data-theme')
        current={'theme':baseline['theme'],'language':baseline['language']}

        def toggle(label):
            drawer=p.locator('#account-drawer')
            if drawer.count()==0 or not drawer.is_visible():
                p.locator('.top-avatar').click()
            expect(drawer).to_be_visible()
            button=drawer.locator('button.drawer-action').filter(has_text=re.compile(label,re.I))
            expect(button).to_have_count(1)
            return suite.response(owner,'/account/settings',lambda:button.click(),method='PUT')

        try:
            displayed_theme=p.locator('html').get_attribute('data-theme')
            target_theme='light' if displayed_theme=='dark' else 'dark'
            target_language='en' if baseline['language']=='vi' else 'vi'
            response=toggle('Appearance|Giao diện');assert response.status==200
            current['theme']=target_theme
            response=toggle('Language|Ngôn ngữ');assert response.status==200
            current['language']=target_language

            persisted=read_preferences()
            assert persisted['theme']==target_theme and persisted['language']==target_language, 'Selected preferences did not persist before tab traversal'
            expect(p.locator('html')).to_have_attribute('data-theme',target_theme)
            expect(p.locator('.settings-sidebar-heading')).to_have_text('Settings' if target_language=='en' else 'Cài đặt')

            expected_tabs=['Account','Notifications','Downloads','Privacy','Billing and payments','Advanced settings'] if target_language=='en' else ['Tài khoản','Thông báo','Nội dung tải xuống','Quyền riêng tư','Lập hóa đơn và thanh toán','Cài đặt nâng cao']
            tabs=p.locator('button.settings-nav-btn')
            expect(tabs).to_have_count(6)
            actual_tabs=[text.strip() for text in tabs.all_text_contents()]
            assert actual_tabs==expected_tabs, 'Visible Account tabs differ from the supported tab set: '+repr(actual_tabs)

            visited=[]
            for index,label in enumerate(expected_tabs):
                tab=tabs.nth(index)
                tab.click()
                expect(tab).to_have_class(re.compile(r'\bactive\b'))
                expect(p.locator('#main-content .settings-pane')).to_be_visible()
                expect(p.locator('.settings-sidebar-heading')).to_have_text('Settings' if target_language=='en' else 'Cài đặt')
                expect(p.locator('html')).to_have_attribute('data-theme',target_theme)
                visited.append(label)

            # Navigate away and back through the real router, then reload the
            # Account page so its GET response verifies persisted server state.
            p.goto(owner['origin']+'/home');expect(p.locator('app-home-page')).to_be_visible()
            expect(p.locator('html')).to_have_attribute('data-theme',target_theme)
            p.reload();expect(p.locator('app-home-page')).to_be_visible()
            expect(p.locator('html')).to_have_attribute('data-theme',target_theme)
            persisted=read_preferences()
            assert persisted['theme']==target_theme and persisted['language']==target_language, 'Preferences changed after visiting all Account tabs and reloading Home'
            expect(p.locator('.settings-sidebar-heading')).to_have_text('Settings' if target_language=='en' else 'Cài đặt')

            entry['steps']=['Toggle theme and language through actual account drawer; observe real HTTP 200 mutations','Activate all six visible Account tabs and verify translated label, active state, panel and document theme at each step','Navigate to Home, reload and return to Account; compare real persisted settings response','Capture all viewports and restore exact original backend/browser preferences']
            entry['assertions']=['Actual UI PUTs changed theme/language','All supported Account tabs rendered and retained active language/theme','Full route transition and Home reload preserved backend theme/language','Cleanup restored the exact original preference values and browser theme override']
            entry['visited_tabs']=visited
            entry['preference_before']={key:baseline[key] for key in ('theme','language')}
            entry['preference_during']={'theme':target_theme,'language':target_language}
            entry['local_theme_before']=original_local_theme
            suite.evidence(owner,entry,'all-tabs-preferences-retained')
        finally:
            if current['language']!=baseline['language']:
                response=toggle('Language|Ngôn ngữ');assert response.status==200
                current['language']=baseline['language']
            if current['theme']!=baseline['theme']:
                if baseline['theme'] in ('light','dark'):
                    response=toggle('Appearance|Giao diện');assert response.status==200
                else:
                    put_preferences({'theme':baseline['theme']})
                current['theme']=baseline['theme']
            if original_local_theme is None:
                p.evaluate("localStorage.removeItem('hutube_theme')")
                p.reload();expect(p.locator('app-home-page,app-account-page').first).to_be_visible()
                expect(p.locator('html')).to_have_attribute('data-theme',original_document_theme)
            elif original_local_theme in ('light','dark'):
                p.evaluate("theme => localStorage.setItem('hutube_theme',theme)",original_local_theme)
                p.reload();expect(p.locator('app-home-page,app-account-page').first).to_be_visible()
                expect(p.locator('html')).to_have_attribute('data-theme',original_local_theme)
            restored=read_preferences()
            assert all(restored[key]==baseline[key] for key in ('theme','language')), 'Preferences did not restore to their original values'

    case(suite,owner,'ACCOUNT-PREFERENCES-ALL-TABS-PERSIST','U-ACCOUNT.02','All Account tabs retain selected theme and language',run_case,'account')
