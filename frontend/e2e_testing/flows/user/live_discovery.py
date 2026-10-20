"""Real search/filter/library journeys; assert the payload rendered by the UI."""
from urllib.parse import parse_qs,urlsplit
import re
from playwright.sync_api import expect
from support.live_suite import PrerequisiteMissing

def run(suite, owner):
    page = owner['page']
    def assert_results(data,selector):
        expect(page.locator('.library-card--skeleton')).to_have_count(0)
        expect(page.locator(selector)).to_have_count(len(data['items']))
        for item in data['items']:
            card=page.locator(selector+'[href="/watch/'+item['videoId']+'"]') if selector=='.search-video-card' else page.locator(selector).filter(has=page.locator('a[href="/watch/'+item['videoId']+'"]'))
            expect(card).to_have_count(1)
            expect(card).to_contain_text(item['title'])
        assert data['total'] >= len(data['items'])

    for query in ('__hutube_qc_no_matching_video__','music','  music  ','<script>alert(1)</script>','Tiếng Việt 🎬'):
        def search(case,query=query):
            suite.go(owner,'/home','app-home-page')
            searchbox = page.locator('input[type=search]').first
            searchbox.fill(query)
            response = suite.response(owner,'/videos/search',lambda:searchbox.press('Enter'))
            data = response.json()
            expect(page.locator('app-explore-page')).to_be_visible()
            assert_results(data,'.search-video-card')
            assert parse_qs(urlsplit(response.url).query)['q'][0] == query.strip()
            expect(page.locator('.search-query-tag')).to_contain_text(query.strip())
            if not data['items']:
                expect(page.locator('.empty-state')).to_be_visible()
            case['steps']=['Header search → Enter → assert actual response and rendered results']
            case['assertions']=['Request query trimmed','Every rendered title matches response','Result count agrees with API']
        suite.case(owner,'U-DISCOVERY-SEARCH-'+str(('__hutube_qc_no_matching_video__','music','  music  ','<script>alert(1)</script>','Tiếng Việt 🎬').index(query)+1),'U-DISCOVERY.01','Search '+repr(query),'Search returns the correct real API items; no script execution or fake empty state',search)

    for index,key,values in [(0,'sort',['relevance','newest','views','engagement']),(1,'duration',['','short','medium','long']),(2,'dateRange',['','today','this_week','this_month','this_year'])]:
        for value in values:
            def select(case,index=index,key=key,value=value):
                data = suite.go(owner,'/search?q=music','app-explore-page','/videos/search')
                select = page.locator('.filter-grid select').nth(index)
                if select.input_value()==value:
                    alternate = next(v for v in values if v != value)
                    suite.response(owner,'/videos/search',lambda:select.select_option(alternate))
                response = suite.response(owner,'/videos/search',lambda:select.select_option(value))
                params = parse_qs(urlsplit(response.url).query)
                assert params.get(key,[''])[0] == value
                assert params['page']==['1']
                expect(select).to_have_value(value)
                assert_results(response.json(),'.search-video-card')
                if value and not (key=='sort' and value=='relevance'):
                    expect(page).to_have_url(re.compile('[?&]'+key+'='+re.escape(value)+'(?:&|$)'))
                case['assertions'].append('Selection and URL correct before reload')
                # URL state must survive reload, including an empty selection.
                reloaded = suite.response(owner,'/videos/search',page.reload)
                expect(page.locator('.filter-grid select').nth(index)).to_have_value(value)
                assert_results(reloaded.json(),'.search-video-card')
                case['steps']=['Select '+key+'='+value,'Assert request/page reset/results','Reload and assert selected value and results']
            suite.case(owner,'U-DISCOVERY-'+key.upper()+'-'+(value.upper() or 'ALL'),'U-DISCOVERY.02','Filter '+key+' '+(value or 'all'),'Selected enum drives real request and persists through URL/reload',select)

    def pagination(case):
        data = suite.go(owner,'/search?q=music','app-explore-page','/videos/search')
        if data['total']<=20:
            raise PrerequisiteMissing('Search query music has <=20 results; multi-page journey needs a larger real fixture')
        expect(page.locator('.pagination .page-button').first).to_be_disabled()
        response = suite.response(owner,'/videos/search',lambda:page.locator('.pagination .page-button').last.click())
        assert parse_qs(urlsplit(response.url).query)['page']==['2']
        assert_results(response.json(),'.search-video-card')
        original_ids = {v['videoId'] for v in data['items']}
        assert not original_ids.intersection({v['videoId'] for v in response.json()['items']})
        reset = suite.response(owner,'/videos/search',lambda:page.locator('.filter-grid select').first.select_option('views'))
        assert parse_qs(urlsplit(reset.url).query)['page']==['1']
        assert_results(reset.json(),'.search-video-card')
        case['steps']=['First page → next page','Check no duplicate IDs','Sort → resets page to 1']
    suite.case(owner,'U-DISCOVERY-PAGINATION-01','U-DISCOVERY.02','Search pagination and filter page reset','Different pages contain distinct real video IDs; sort resets first page',pagination)

    run_library(suite,owner,assert_results)

def run_library(suite,owner,assert_results=None):
    page=owner['page']
    if assert_results is None:
        def assert_results(data,selector):
            expect(page.locator('.library-card--skeleton')).to_have_count(0)
            expect(page.locator(selector)).to_have_count(len(data['items']))
            for item in data['items']:
                card=page.locator(selector).filter(has=page.locator('a[href="/watch/'+item['videoId']+'"]'))
                expect(card).to_have_count(1)
                expect(card).to_contain_text(item['title'])
            assert data['total']>=len(data['items'])
    for rating in range(1,6):
        def library(case,rating=rating):
            baseline=suite.go(owner,'/liked','app-library-page','/library/liked',params={'pageSize':20})
            assert_results(baseline,'.library-card')
            response = suite.response(owner,'/library/liked',lambda:page.locator('.rating-filter__btn').nth(rating-1).click(),params={'rating':rating})
            data = response.json()
            assert parse_qs(urlsplit(response.url).query)['rating']==[str(rating)]
            assert parse_qs(urlsplit(response.url).query)['page']==['1']
            expect(page.locator('.rating-filter__btn').nth(rating-1)).to_have_attribute('aria-pressed','true')
            assert_results(data,'.library-card')
            assert all(v['myRating']==rating for v in data['items'])
            reset = suite.response(owner,'/library/liked',lambda:page.locator('.rating-filter__options button').first.click())
            assert 'rating' not in parse_qs(urlsplit(reset.url).query)
            assert_results(reset.json(),'.library-card')
            case['steps']=['Liked → rating '+str(rating),'Compare every API/DOM item','Reset → all ratings']
        suite.case(owner,'U-LIBRARY-RATING-'+str(rating),'U-LIBRARY.02','Liked rating '+str(rating),'Exact rating filter, count and reset match actual API data',library)
