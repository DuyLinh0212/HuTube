from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__);member=actors['member'];owner=actors['owner'];cid=suite.fixtures['channel']['channelId']
    data=suite.api(owner,'get','/videos/manage',params={'channelId':cid,'page':1,'pageSize':100}).json()['items']
    video=next(v for v in data if v['title'].startswith('QC RESUME ') and v['duration']>=30 and v['moderationStatus']=='approved' and v['visibility']=='public');vid=video['videoId']
    def resume(entry):
        suite.go(member,'/watch/'+vid,'app-watch-page');p=member['page'];v=p.locator('video').first
        p.wait_for_function('()=>document.querySelector("video")?.readyState>=1')
        if not v.evaluate('(v)=>v.paused'):v.hover();p.locator('.player-control-group').first.locator('button').first.click()
        p.locator('.player-progress').fill('0');p.wait_for_timeout(250)
        suite.response(member,'/videos/'+vid+'/watch-progress',lambda:p.locator('.player-progress').fill('11'),method='PUT')
        if v.evaluate('(v)=>v.paused'):p.locator('.player-big-play').click()
        p.wait_for_function('()=>document.querySelector("video").currentTime>12',timeout=15000)
        v.hover();p.locator('.player-control-group').first.locator('button').first.click();assert v.evaluate('(v)=>v.paused')
        history=suite.api(member,'get','/library/history',params={'page':1,'pageSize':50}).json();record=next(v for v in history['items'] if v['videoId']==vid)
        assert 10<=record['watchedSeconds']<27
        suite.go(member,'/history','app-library-page');expect(p.locator('a[href="/watch/'+vid+'"]').first).to_be_visible()
        suite.go(member,'/watch/'+vid,'app-watch-page');p.wait_for_function('()=>document.querySelector("video")?.readyState>=1')
        p.wait_for_function('(seconds)=>document.querySelector("video").currentTime>=seconds-1',arg=record['watchedSeconds'],timeout=10000)
        v=p.locator('video').first
        if not v.evaluate('(v)=>v.paused'):v.hover();p.locator('.player-control-group').first.locator('button').first.click()
        entry['resource_ids']=[vid];entry['steps']=['Real thirty-second browser playback','UI seek uses real PUT watch-progress after save interval','Pause preserves unfinished history checkpoint','History shows exact ID','Actual reopened native player resumes saved position']
    case(suite,member,'WATCH-HISTORY-RESUME','U-WATCH.02','Watch resumes actual unfinished history checkpoint',resume,'watch')
