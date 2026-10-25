"""Policy-local search availability and keyboard navigation destination visibility."""
from urllib.parse import parse_qs,urlsplit
import re
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__);guest=suite.actor('policy-surface','user','guest');guest['api_url']=config['api_url'];p=guest['page']
    try:
        def search(entry):
            data=suite.go(guest,'/policies?tab=guidelines','app-public-policy-page','/policies');assert data
            expect(p.locator('.policy-card').first).to_be_visible()
            entry['steps']=['Guest loads actual published policy API and rendered policy cards','Inspect search controls inside policy component, excluding unrelated global video search','Checklist requires filtering/searching policy text, group or detail']
            suite.evidence(guest,entry,'policy-local-search-controls')
            entry['policy_search_controls']=p.locator('app-public-policy-page input[type=search],app-public-policy-page input[type=text],app-public-policy-page [role=searchbox]').count()
            assert entry['policy_search_controls']>0,'U-POLICY.01: policy search state exists in source but no policy search control is rendered; global search is for videos'
            query=p.locator('app-public-policy-page input[type=search]')
            cards=p.locator('.policy-card');total=cards.count();assert total>1
            code=cards.first.get_attribute('id');assert code
            query.fill(code.lower());expect(cards).to_have_count(1)
            assert cards.first.get_attribute('id')==code
            query.fill('  '+code+'  ');expect(cards).to_have_count(1)
            query.fill('QC_NO_POLICY_MATCH_20261016');expect(cards).to_have_count(0)
            expect(p.locator('.empty-results-box')).to_be_visible()
            suite.evidence(guest,entry,'policy-search-empty-no-stale-cards')
            p.locator('.btn-clear-search').click();expect(query).to_have_value('');expect(cards).to_have_count(total)
            query.fill('<script>QC_NO_MATCH</script>');expect(cards).to_have_count(0)
            assert p.locator('app-public-policy-page script').count()==0
            query.fill('');expect(cards).to_have_count(total)
            entry['steps']+=['Filter exact published code case-insensitively and with surrounding whitespace','Unmatched query removes all cards and shows exact empty state; Clear restores complete set','HTML-looking query stays literal text and never creates a script element']
        case(suite,guest,'POLICY-LOCAL-SEARCH-CONTROL-CONTRACT','U-POLICY.01','Published policies provide the required local search operation',search,'policy')
        def keyboard(entry):
            suite.go(guest,'/policies?tab=privacy','app-public-policy-page','/policies')
            button=p.locator('.footer-links-row button').first;button.focus();expect(button).to_be_focused()
            suite.evidence(guest,entry,'footer-keyboard-focus-before-activation')
            button.focus();p.keyboard.press('Enter')
            p.wait_for_function('()=>new URLSearchParams(location.search).get("tab")==="guidelines"');p.wait_for_timeout(800)
            assert parse_qs(urlsplit(p.url).query)['tab']==['guidelines']
            value=p.evaluate('()=>{const e=document.activeElement,r=e.getBoundingClientRect();return {tag:e.tagName,text:e.textContent?.trim().slice(0,100),top:r.top,bottom:r.bottom,viewport:innerHeight,scrollY}}')
            entry['focus_after_navigation']=value
            entry['steps']=['Actual keyboard focus placed on first policy footer navigation control','Real Enter key activates Guidelines and updates route/query','After programmed scrolling, keyboard focus must remain visible or move to a visible destination','Do not count route change alone as keyboard accessibility PASS']
            assert value['bottom']>0 and value['top']<value['viewport'],'Footer navigation scrolls to policy content but leaves keyboard focus off screen'
            expect(p.locator('.tab-title')).to_be_focused()
            suite.evidence(guest,entry,'policy-visible-keyboard-destination')
        case(suite,guest,'POLICY-FOOTER-KEYBOARD-FOCUS-VISIBLE','U-POLICY.02','Keyboard policy navigation leaves a visible focus destination',keyboard,'policy')
        def removed_tools(entry):
            suite.go(guest,'/privacy','app-public-policy-page','/policies')
            expect(p.locator('#quyen-va-lua-chon,.tools-grid,.custom-switch')).to_have_count(0)
            expect(p.locator('.footer-links-row a[href="/home"]')).to_be_visible()
            entry['steps']=['Privacy policies load','Removed tools do not render','Home navigation remains available']
        case(suite,guest,'POLICY-REMOVED-PRIVACY-TOOLS','U-POLICY.02','Removed privacy tools stay absent',removed_tools,'policy')
        def routes(entry):
            for route,tab in [('/terms','terms'),('/privacy','privacy'),('/guidelines','guidelines'),('/policies?tab=enforcement','enforcement'),('/policies?tab=monetization','all')]:
                suite.go(guest,route,'app-public-policy-page','/policies')
                expect(p.locator('.hub-nav button.active')).to_have_count(1)
                index=['all','guidelines','privacy','terms','enforcement'].index(tab)
                expect(p.locator('.hub-nav button').nth(index)).to_have_class('hub-nav-item active')
                expect(p.locator('.tab-title')).not_to_be_empty()
                assert p.locator('.policy-card').count()>0
            entry['steps']=['Load each of four real policy routes/groups independently','Rendered selected group/title and nonempty policy content must agree','No fabricated published-version fixture in the test']
        case(suite,guest,'POLICY-ALL-PUBLIC-ROUTES-GROUPS','U-POLICY.01','Every public policy route and group renders content',routes,'policy')
        member=actors['member'];mp=member['page']
        def published(entry):
            guest_data=suite.api(guest,'get','/policies').json()
            member_data=suite.api(member,'get','/policies').json()
            assert sorted(guest_data,key=lambda x:x['policyId'])==sorted(member_data,key=lambda x:x['policyId'])
            fixtures=[x for x in member_data if x['code'].startswith('QC_POLICY_') and x['group'].lower()!='monetization' and x['code'].upper() not in {'PARTNER_ELIGIBILITY','AD_SUITABILITY_GUIDE','REVENUE_PAYOUTS'}]
            assert fixtures,'Require existing actually published QC version fixtures'
            checked=[]
            for tab in ['guidelines','privacy','terms','enforcement']:
                items=[x for x in fixtures if (x['group'] if x['group'] in ['guidelines','privacy','terms','enforcement'] else ('terms' if x['group']=='legal' else 'guidelines'))==tab]
                if not items:continue
                suite.go(member,'/policies?tab='+tab,'app-public-policy-page','/policies')
                query=mp.locator('#policy-search')
                for item in items:
                    assert re.fullmatch(r'[A-Za-z0-9_-]+',item['code'])
                    query.fill(item['code']);card=mp.locator('.policy-card[id="'+item['code']+'"]')
                    expect(card).to_have_count(1)
                    expect(card.locator('.policy-card-title')).to_have_text(item['name'])
                    expect(card.locator('.policy-card-summary')).to_have_text(item['content'])
                    expect(card.locator('.policy-version')).to_contain_text(item['version'])
                    expect(card.locator('.sev-badge')).to_have_class(re.compile(r'\b'+re.escape(item['severity'])+r'\b'))
                    checked.append({'id':item['policyId'],'version':item['version'],'group':tab,'severity':item['severity']})
                query.fill('')
            assert len(checked)==len(fixtures)
            entry['checked_published_versions']=checked
            entry['resource_ids']=[x['id'] for x in checked]
            entry['steps']=['Guest and authenticated Member receive identical actual public-policy API data','For every existing published QC version, open its real group and filter exact code','UI name/content/version/severity match API exactly, without replacing server content with built-in explanation','No new policy or synthetic response is created by this read-only test']
        case(suite,member,'POLICY-MEMBER-PUBLISHED-VERSIONS-SEVERITY-SEARCH','U-POLICY.01','Authenticated policy search preserves exact published versions and severities',published,'policy')
        def footer(entry):
            suite.go(member,'/policies?tab=privacy','app-public-policy-page','/policies')
            checked=[]
            for index,tab in enumerate(['guidelines','privacy','terms','enforcement']):
                button=mp.locator('.footer-links-row button').nth(index);button.focus();mp.keyboard.press('Enter')
                mp.wait_for_function('(tab)=>new URLSearchParams(location.search).get("tab")===tab',arg=tab)
                expect(mp.locator('.tab-title')).to_be_focused()
                rect=mp.locator('.tab-title').bounding_box();assert rect and rect['y']>=0 and rect['y']<mp.evaluate('innerHeight')
                expect(mp.locator('.hub-nav button').nth(index + 1)).to_have_class('hub-nav-item active')
                checked.append(tab);suite.evidence(member,entry,'keyboard-footer-'+tab)
            link=mp.locator('.footer-links-row a[href="/home"]');link.focus();mp.keyboard.press('Enter');mp.wait_for_url('**/home')
            expect(mp.locator('app-public-policy-page')).to_have_count(0)
            entry['keyboard_targets']=checked+['/home']
            entry['steps']=['Actual Member keyboard Enter activates each of four footer legal groups','Each exact query/selected navigation agrees and actual content heading owns visible focus','Real keyboard Home link leaves policy route; no click/evaluate handler substitution']
        case(suite,member,'POLICY-ALL-FOOTER-KEYBOARD-TARGETS','U-POLICY.02','Every footer legal navigation target preserves visible keyboard focus',footer,'policy')
    finally:suite.release_actor(guest)
