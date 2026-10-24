"""Assert studio analytics against every actual managed-video page."""
import math
from playwright.sync_api import expect
from support.live_suite import PrerequisiteMissing

def run(suite,owner):
    page=owner['page']
    channel=suite.api(owner,'get','/channels/me').json()
    channel_id=channel['channelId']
    videos=[]
    number=1
    while True:
        result=suite.api(owner,'get','/videos/manage',params={'channelId':channel_id,'page':number,'pageSize':50}).json()
        videos.extend(result['items'])
        if number*result['pageSize']>=result['total']: break
        number+=1
    assert len({video['videoId'] for video in videos})==len(videos)==result['total']
    def load():
        suite.go(owner,'/studio/analytics?channelId='+channel_id,'app-studio-analytics-page')
        if not videos: raise PrerequisiteMissing('Owned channel has no analytics video dataset')
        expect(page.locator('.video-picker option')).to_have_count(len(videos)+1)
        expect(page.locator('.metric-card')).to_have_count(5)
    def values(selected=None):
        stats=selected['stats'] if selected else None
        count=len(videos)
        total_views=sum(video['stats']['views'] for video in videos)
        total_seconds=sum(video['stats'].get('watchSeconds') or 0 for video in videos)
        rating_count=sum(video['stats']['ratingCount'] for video in videos if video['stats']['averageRating'] is not None)
        weighted=sum(video['stats']['averageRating']*video['stats']['ratingCount'] for video in videos if video['stats']['averageRating'] is not None)
        expected=[stats[key] if stats else sum(video['stats'][key] for video in videos)/count for key in ['views','likes','comments']]
        expected.append((stats.get('watchSeconds') or 0)/stats['views'] if stats and stats['views'] else 0 if stats else total_seconds/total_views if total_views else 0)
        expected.append(stats['averageRating'] if stats and stats['ratingCount'] else None if stats else weighted/rating_count if rating_count else None)
        actual=page.locator('.metric-card strong').all_text_contents()
        for index in range(3):
            number=float(actual[index].strip().replace('.','').replace(',','.'))
            assert math.isfinite(number) and abs(number-expected[index])<=0.051,(index,number,expected[index])
        seconds=max(0,math.floor(expected[3]+0.5))
        duration=f'{seconds//3600}:{seconds%3600//60:02d}:{seconds%60:02d}' if seconds>=3600 else f'{seconds//60}:{seconds%60:02d}'
        assert actual[3].strip()==duration,(actual[3],duration)
        assert actual[4].strip()==('—' if expected[4] is None else f'{expected[4]:.2f} / 5')
        expect(page.locator('.radar-area')).to_have_attribute('points',__import__('re').compile(r'^[\d., -]+$'))
        assert len(page.locator('.radar-area').get_attribute('points').split())==5
    def all_videos(case):
        load(); values()
        expect(page.locator('.top-video')).to_have_count(min(5,len(videos)))
        # Assert numeric rank and payload identity without assuming Python and
        # Intl use the same Unicode collation for ties.
        rendered=page.locator('.top-video .video-info strong').all_text_contents()
        counts=[next(video['stats']['views'] for video in videos if video['title']==title) for title in rendered]
        assert counts==sorted(counts,reverse=True)
        case['resource_ids']=[channel_id]
        case['steps']=['Read every managed-video API page','Assert picker includes all IDs','Compare averages, weighted rating and watchSeconds/views','Assert top-five ranking and finite radar geometry']
    suite.case(owner,'LIVE-STUDIO-ANALYTICS-ALL','U-STUDIO.07','All-video analytics against full real dataset','Displayed metrics use actual totals/averages and watchSeconds, with all API pages included',all_videos,module='studio-analytics')
    def selection(case):
        load()
        picks=videos[:2]
        for video in picks:
            page.locator('.video-picker select').select_option(video['videoId'])
            expect(page.locator('.selected-video-card')).to_have_attribute('href','/watch/'+video['videoId'])
            expect(page.locator('.selected-video-info strong')).to_have_text(video['title'])
            values(video)
            suite.evidence(owner,case,'selected-'+video['videoId'])
        page.locator('.selected-video-panel .text-button').click()
        expect(page.locator('.video-picker select')).to_have_value('all')
        values()
        page.locator('.top-video').first.click()
        expect(page.locator('.video-picker select')).not_to_have_value('all')
        selected=page.locator('.video-picker select').input_value()
        values(next(video for video in videos if video['videoId']==selected))
        case['resource_ids']=[video['videoId'] for video in picks]
        case['steps']=['Select two exact video IDs consecutively','Compare every metric and watch link for each selection','Back to all → restore averages','Top-video button selects the same real ID']
    suite.case(owner,'LIVE-STUDIO-ANALYTICS-SELECT','U-STUDIO.07','Per-video selection and back-to-all analytics','Selection changes every metric and watch link without stale data',selection,module='studio-analytics')
