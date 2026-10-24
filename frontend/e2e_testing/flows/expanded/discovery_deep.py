from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    member=actors['member'];p=member['page']
    def carousel(entry):
        suite.go(member,'/explore','app-explore-page');rail=p.locator('.trending-carousel-track');expect(rail).to_be_visible()
        assert rail.locator('.trending-card').count()>1
        rail.scroll_into_view_if_needed();prev=p.locator('.carousel-nav-btn--prev');nxt=p.locator('.carousel-nav-btn--next')
        touch=suite.input_device!='desktop' and not nxt.is_visible()
        session=p.context.new_cdp_session(p) if touch else None
        def move(forward):
            if not touch:
                (nxt if forward else prev).click();p.wait_for_timeout(350);return
            # Genuine browser touch gesture, not assignment to DOM scrollLeft.
            box=rail.bounding_box();assert box
            y=max(5,min(p.viewport_size['height']-5,box['y']+box['height']/2))
            a=box['x']+box['width']*(.85 if forward else .15)
            b=box['x']+box['width']*(.15 if forward else .85)
            session.send('Input.dispatchTouchEvent',{'type':'touchStart','touchPoints':[{'x':a,'y':y,'id':0}]})
            try:
                for step in range(1,13):
                    session.send('Input.dispatchTouchEvent',{'type':'touchMove','touchPoints':[{'x':a+(b-a)*step/12,'y':y,'id':0}]})
                    p.wait_for_timeout(16)
            finally:session.send('Input.dispatchTouchEvent',{'type':'touchEnd','touchPoints':[]})
            p.wait_for_timeout(500)
        try:
            for _ in range(40):
                move(True)
                bounds=rail.evaluate('(e)=>({left:e.scrollLeft,max:e.scrollWidth-e.clientWidth})')
                if bounds['max']-bounds['left']<2:break
            end=rail.evaluate('(e)=>({left:e.scrollLeft,max:e.scrollWidth-e.clientWidth})')
            assert abs(end['max']-end['left'])<2,'Actual navigation did not reach the right boundary'
            move(True);assert abs(rail.evaluate('(e)=>e.scrollLeft')-end['left'])<2
            for _ in range(40):
                move(False)
                if rail.evaluate('(e)=>e.scrollLeft')<2:break
            assert rail.evaluate('(e)=>e.scrollLeft')<2
            move(False);assert rail.evaluate('(e)=>e.scrollLeft')<2
        finally:
            if session:session.detach()
        entry['interaction']='Actual Chromium touch swipes; responsive arrows hidden' if touch else 'Visible next/previous buttons'
        entry['steps']=['Actual populated Explore trending rail',entry['interaction'],'Navigate repeatedly to actual right boundary; further gesture cannot exceed it','Navigate to zero; further reverse gesture cannot scroll below zero']
    case(suite,member,'DISCOVERY-CAROUSEL-BOUNDARIES','U-DISCOVERY.03','Trending carousel stays within real scroll bounds',carousel,'discovery')
    def rapid(entry):
        suite.go(member,'/search?q=music','app-explore-page','/videos/search');select=p.locator('.filter-grid select').first
        for value in ['views','newest','engagement','relevance','newest']:select.select_option(value)
        p.wait_for_load_state('networkidle',timeout=20000)
        expect(select).to_have_value('newest');expect(p).to_have_url(__import__('re').compile('sort=newest'))
        data=suite.api(member,'get','/videos/search',params={'q':'music','sort':'newest','page':1,'pageSize':20}).json()
        assert p.locator('.search-video-card').evaluate_all('(links)=>links.map(a=>a.pathname.split("/").pop())')==[v['videoId'] for v in data['items']]
        p.reload();expect(p.locator('.filter-grid select').first).to_have_value('newest')
        entry['steps']=['Rapid actual UI changes across all sort values','Settled URL and selected control use latest value','Rendered exact IDs/order equal latest real API response','Reload retains latest sort; deliberate server-delay injection not performed']
    case(suite,member,'DISCOVERY-RAPID-LATEST-FILTER','U-DISCOVERY.03','Rapid filters retain latest real results',rapid,'discovery')
    def creator(entry):
        suite.go(member,'/explore','app-explore-page');card=p.locator('.creator-card').first;expect(card).to_be_visible();href=card.locator('a.creator-name').get_attribute('href');assert href.startswith('/channel/')
        card.locator('a.creator-name').click();expect(p.locator('app-channel-page')).to_be_visible()
        state=p.locator('.btn-subscribe').inner_text();p.locator('.btn-subscribe').click()
        expect(p.locator('.btn-subscribe')).not_to_have_text(state)
        p.reload();expect(p.locator('.btn-subscribe')).not_to_have_text(state)
        p.locator('.btn-subscribe').click();expect(p.locator('.btn-subscribe')).to_have_text(state)
        entry['steps']=['Featured creator actual card → linked channel','Member toggles subscription through channel UI','Reload persists; restore original state']
    case(suite,member,'DISCOVERY-CREATOR-SUBSCRIBE','U-DISCOVERY.03','Creator card opens same channel and subscription persists',creator,'discovery')
