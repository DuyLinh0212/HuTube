"""Every public policy tab, reload/back/forward and live published-content check."""
import re
from playwright.sync_api import expect
from support.live_suite import PrerequisiteMissing

def run(suite,owner):
    page=owner['page']
    tabs=['guidelines','privacy','terms','monetization','enforcement']
    for index,tab in enumerate(tabs):
        def navigate(case,index=index,tab=tab):
            suite.go(owner,'/policies','app-public-policy-page','/policies')
            button=page.locator('.hub-nav-item').nth(index)
            button.focus()
            expect(button).to_be_focused()
            button.press('Enter')
            expect(page).to_have_url(re.compile('[?&]tab='+tab+'(?:&|$)'))
            expect(button).to_have_class(re.compile('active'))
            ids=page.locator('.policy-card').evaluate_all('(els)=>els.map(e=>e.id)')
            assert ids and len(ids)==len(set(ids))
            suite.response(owner,'/policies',page.reload)
            expect(page.locator('.hub-nav-item').nth(index)).to_have_class(re.compile('active'))
            assert page.locator('.policy-card').evaluate_all('(els)=>els.map(e=>e.id)')==ids
            page.locator('.hub-nav-item').nth((index+1)%len(tabs)).click()
            page.go_back()
            expect(page.locator('.hub-nav-item').nth(index)).to_have_class(re.compile('active'))
            page.go_forward()
            expect(page.locator('.hub-nav-item').nth((index+1)%len(tabs))).to_have_class(re.compile('active'))
            case['steps']=['Keyboard Enter on '+tab,'Record real card IDs','Reload same IDs','Change tab → back/forward']
        suite.case(owner,'U-POLICY-LIVE-TAB-'+tab.upper(),'U-POLICY.01','Policy tab '+tab,'Keyboard navigation, URL, reload and browser history preserve tab and card IDs',navigate,module='policy')
    def current(case):
        data=suite.go(owner,'/policies','app-public-policy-page','/policies')
        published=[item for item in data if item['status']=='published']
        if not published: raise PrerequisiteMissing('No published policy in real API to verify version rendering')
        rendered={}
        for index,tab in enumerate(tabs):
            button=page.locator('.hub-nav-item').nth(index)
            button.click();expect(button).to_have_class(re.compile('active'))
            rendered.update(page.locator('.policy-cards-feed .policy-card').evaluate_all('''cards=>Object.fromEntries(cards.map(card=>[card.id,{
                name:card.querySelector('.policy-card-title')?.textContent?.trim(),
                content:card.querySelector('.policy-card-summary')?.textContent,
                version:card.querySelector('.policy-version')?.textContent?.trim()
            }]))'''))
        missing=[item['code'] for item in published if item['code'] not in rendered or
            rendered[item['code']]['name']!=item['name'] or rendered[item['code']]['content']!=item['content'] or
            item['version'] not in (rendered[item['code']]['version'] or '')]
        case['resource_ids']=[item['policyId'] for item in published]
        case['steps']=['Read real published policies','Visit all five groups; wait for actual active-tab render',
            'Map actual card IDs, exact DOM textContent and version; compare each to published API resource']
        assert not missing,'Published API policies are missing from all public UI groups: '+', '.join(missing)
    suite.case(owner,'U-POLICY-LIVE-CURRENT-CONTENT','U-POLICY.01','Public UI uses published policy content','Current published names/content from backend are rendered in appropriate UI groups',current,module='policy')
    def disabled(case):
        suite.go(owner,'/policies?tab=privacy','app-public-policy-page','/policies')
        controls=page.locator('.policy-hub button[disabled],.policy-hub input[disabled]')
        assert controls.count()>=3
        for index in range(controls.count()):
            expect(controls.nth(index)).to_be_disabled()
            assert controls.nth(index).get_attribute('title'),'Unsupported control needs a visible explanation'
        case['steps']=['Privacy group','Inspect each unsupported tool/toggle','Disabled and explanation present']
    suite.case(owner,'U-POLICY-LIVE-DISABLED','U-POLICY.02','Unsupported privacy tools explain disabled state','Unsupported actions cannot submit fake save and have an explanation',disabled,module='policy')
