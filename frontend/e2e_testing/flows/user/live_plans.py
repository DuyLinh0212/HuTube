"""Public plan data, current quota, details and real clipboard; no payment."""
import math
from urllib.parse import parse_qs,urlsplit
from playwright.sync_api import expect
from support.live_suite import PrerequisiteMissing

def run(suite,owner):
    page=owner['page']
    plans=suite.api(owner,'get','/plans').json()
    assert plans and len({p['planId'] for p in plans})==len(plans)
    guest=suite.actor('plan-guest','user','guest')
    def catalog(case):
        suite.go(owner,'/plans','app-plans-page','/plans')
        page.locator('.plans-view-switch [role=tab]').nth(1).click()
        expect(page.locator('.plan-card')).to_have_count(len(plans))
        for row,item in zip(page.locator('.plan-card').all(),plans):
            assert item['status']=='active'
            expect(row.locator('h2')).to_have_text(item['name'])
            expect(row.locator('.plan-code')).to_have_text(item['code'])
            expect(row.locator('.plan-button')).to_have_attribute('href','/plans/'+item['planId'])
            amount=row.locator('.price').inner_text().split('/')[0]
            assert int(''.join(c for c in amount if c.isdigit()))==round(item['price'])
            expect(row.locator('dl dd').nth(2)).to_have_text(str(item['maxMembers']))
            expect(row.locator('dl dd').nth(3)).to_contain_text(item['maxVideoQuality'] or '720p')
        page.reload(); expect(page.locator('.plans-view-switch [role=tab]').first).to_have_attribute('aria-selected','true')
        page.locator('.plans-view-switch [role=tab]').nth(1).click()
        expect(page.locator('.plan-card')).to_have_count(len(plans))
        case['resource_ids']=[p['planId'] for p in plans]
        case['steps']=['Catalog tab → exact active API plan count/IDs','Compare all names/codes/prices/member limits/quality and detail links','Reload and reopen catalog → same data; no subscription mutation']
    suite.case(owner,'LIVE-PLAN-CATALOG-DATA','U-PLAN.01','All active plan catalog data','Every rendered plan has actual API values and inactive plans are absent',catalog,module='plans')
    def current(case):
        data=suite.api(owner,'get','/plans/my-plan').json()
        if not data: raise PrerequisiteMissing('Supplied identity has no current plan')
        suite.go(owner,'/plans','app-plans-page')
        expect(page.locator('.plan-hero-card h2')).to_have_text(data['name'])
        width=float(page.locator('.progress-fill').evaluate('(el)=>parseFloat(el.style.width)'))
        expected=min(100,data['usedStorage']/data['storageLimit']*100) if data['storageLimit'] else 0
        assert math.isfinite(width) and abs(width-expected)<0.001
        assert data['remainingStorage']>=0 and data['usedStorage']>=0
        page.locator('.hero-actions a').click()
        expect(page.locator('.cta-subscribe.is-active-plan')).to_be_disabled()
        expect(page.locator('.detail-hero h1')).to_have_text(data['name'])
        case['resource_ids']=[data['planId']]
        case['steps']=['Current plan → API name and actual quota percent','Nonnegative used/remaining storage and finite progress','UI current-plan detail link → exact name and disabled current-plan action']
    suite.case(owner,'LIVE-PLAN-CURRENT-QUOTA','U-PLAN.01','Current plan and quota','Current identity plan/quota and current-plan detail state agree with API',current,module='plans')
    for item in plans:
        def detail(case,item=item):
            path='/plans/'+item['planId']
            suite.go(guest,path,'app-plan-detail-page')
            p=guest['page']
            expect(p.locator('.detail-hero h1')).to_have_text(item['name'])
            expect(p.locator('.plan-pill')).to_have_text(item['code'].upper())
            assert int(''.join(c for c in p.locator('.amount').inner_text() if c.isdigit()))==round(item['price'])
            share=suite.api(owner,'get',path+'/share').json()
            expect(p.locator('#share-url-input')).to_have_value(share['shareUrl'])
            p.locator('.btn-copy').click()
            assert p.evaluate('()=>navigator.clipboard.readText()')==share['shareUrl']
            suite.evidence(guest,case,'plan-'+item['code']+'-detail')
            href=p.locator('a.cta-subscribe').get_attribute('href')
            assert urlsplit(href).path=='/login' and parse_qs(urlsplit(href).query)['returnUrl']==[path]
            p.locator('a.cta-subscribe').click(); p.wait_for_url('**/login**')
            assert parse_qs(urlsplit(p.url).query)['returnUrl']==[path]
            p.go_back(); expect(p.locator('.detail-hero h1')).to_have_text(item['name'])
            p.reload(); expect(p.locator('#share-url-input')).to_have_value(share['shareUrl'])
            case['resource_ids']=[item['planId']]
            case['steps']=['Guest detail → exact API name/code/price','Public share API → actual readonly URL','Copy → real clipboard exact match','Login CTA retains this plan return URL','Back/reload → same plan and share data']
        suite.case(guest,'LIVE-PLAN-DETAIL-'+item['code'].upper(),'U-PLAN.01','Plan detail '+item['code'],'Exact plan data, clipboard and guest login context persist through navigation',detail,module='plans')
    def missing(case):
        path='/plans/00000000-0000-0000-0000-000000000000'
        suite.api(owner,'get',path,expected=404)
        suite.go(guest,path,'app-plan-detail-page')
        expect(guest['page'].locator('.state.error')).to_be_visible()
        expect(guest['page'].locator('.detail-hero')).to_have_count(0)
        guest['page'].locator('a.back-btn').click()
        expect(guest['page'].locator('app-plans-page')).to_be_visible()
        case['steps']=['Known absent nil UUID → actual API 404','Guest detail → visible error, no plan/buy content','Back button → catalog route']
    suite.case(guest,'LIVE-PLAN-MISSING-ID','U-PLAN.01','Missing plan ID','Missing plan shows an error and no purchasable fabricated data',missing,module='plans')
    suite.release_actor(guest)
