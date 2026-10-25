"""Every public policy tab, reload/back/forward and live published-content check."""
import re
from playwright.sync_api import expect
from support.live_suite import PrerequisiteMissing

def run(suite,owner):
    page=owner['page']
    tabs=['all','guidelines','privacy','terms','enforcement']
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
        published=[item for item in data if item['status']=='published' and item['group'].lower()!='monetization' and item['code'].upper() not in {'PARTNER_ELIGIBILITY','AD_SUITABILITY_GUIDE','REVENUE_PAYOUTS'}]
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
        case['steps']=['Read real published policies','Visit all policies and all four groups; wait for actual active-tab render',
            'Map actual card IDs, exact DOM textContent and version; compare each to published API resource']
        assert not missing,'Published API policies are missing from all public UI groups: '+', '.join(missing)
    suite.case(owner,'U-POLICY-LIVE-CURRENT-CONTENT','U-POLICY.01','Public UI uses published policy content','Current published names/content from backend are rendered in appropriate UI groups',current,module='policy')
    def removed_tools(case):
        suite.go(owner,'/policies?tab=privacy','app-public-policy-page','/policies')
        expect(page.locator('#quyen-va-lua-chon,.tools-grid,.custom-switch')).to_have_count(0)
        expect(page.locator('.policy-card').first).to_be_visible()
        case['steps']=['Privacy group still renders policies','Data export, algorithm reset and advertising controls are absent']
    suite.case(owner,'U-POLICY-LIVE-REMOVED-TOOLS','U-POLICY.02','Removed privacy tools stay absent','No unsupported privacy tool block is rendered',removed_tools,module='policy')
