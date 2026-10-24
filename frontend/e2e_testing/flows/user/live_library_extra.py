"""Actual history payload/progress and protected aliases, without new fake views."""
import math
from urllib.parse import urlsplit
from playwright.sync_api import expect

def run(suite,owner):
    page=owner['page']
    def history(case):
        data=suite.go(owner,'/history','app-library-page','/library/history')
        expect(page.locator('.library-card--skeleton')).to_have_count(0)
        assert len({item['videoId'] for item in data['items']})==len(data['items'])
        for item in data['items']:
            assert math.isfinite(item['watchedSeconds']) and item['watchedSeconds']>=0
            assert math.isfinite(item['progress']) and 0<=item['progress']<=100
            card=page.locator('.library-card').filter(has=page.locator('a[href="/watch/'+item['videoId']+'"]'))
            expect(card).to_have_count(1); expect(card).to_contain_text(item['title'])
            if item['progress']>0:
                width=card.locator('.watch-progress').evaluate('(element)=>parseFloat(element.style.width)')
                assert abs(width-item['progress'])<=0.001
        if not data['items']:
            # Infinite history may fetch an older 30-day window immediately.
            expect(page.locator('.library-empty,.library-card').first).to_be_visible()
        case['resource_ids']=[item['videoId'] for item in data['items']]
        case['steps']=['History route → compare actual history response IDs/titles','Check finite watchSeconds and progress within 0–100','Compare rendered resume/progress width for each returned video']
    suite.case(owner,'LIVE-LIBRARY-HISTORY-PAYLOAD','U-LIBRARY.01','History real payload and finite progress','History cards and progress correspond to this actor actual records',history,module='library')
    for alias,destination,component,endpoint in [('/profile','/account','app-account-page','/account/profile'),('/library','/history','app-library-page','/library/history')]:
        def redirect(case,alias=alias,destination=destination,component=component,endpoint=endpoint):
            data=suite.go(owner,alias,component,endpoint)
            assert urlsplit(page.url).path==destination
            assert suite.api(owner,'get','/auth/me').json()['userId']==owner['identity']['userId']
            if destination=='/account': assert data['userId']==owner['identity']['userId']
            else:
                expect(page.locator('.library-card--skeleton')).to_have_count(0)
                for item in data['items']:
                    expect(page.locator('.library-card').filter(has=page.locator('a[href="/watch/'+item['videoId']+'"]'))).to_contain_text(item['title'])
            page.reload(); expect(page.locator(component)).to_be_visible()
            assert urlsplit(page.url).path==destination
            case['steps']=['Direct alias '+alias+' → '+destination,'Assert actual profile/history belongs to same authenticated identity','Reload → same destination and component']
        suite.case(owner,'LIVE-LIBRARY-ALIAS-'+alias.strip('/').upper(),'U-LIBRARY.02','Protected alias '+alias,'Alias preserves identity and redirects to correct actual data route',redirect,module='library')
