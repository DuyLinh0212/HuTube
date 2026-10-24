"""Admin entrypoint → actual User Studio file upload → persisted Admin row."""
from playwright.sync_api import expect
from flows.user import media
from support.live_adapter import FunctionalAdapter
from support.live_suite import PrerequisiteMissing
from flows.admin.live_review_layout import run as review_layout

def run(suite,admin,other):
    upload_owner=None; adapter=None
    try:
        def enter(case):
            nonlocal upload_owner,adapter
            suite.go(admin,'/videos','app-admin-videos-page')
            link=admin['page'].locator('a.btn-add-video')
            expect(link).to_have_attribute('href',suite.report['environment']['user']+'/studio/upload')
            expect(link).to_have_attribute('rel','noopener noreferrer')
            suite.evidence(admin,case,'admin-upload-link')
            with admin['page'].expect_popup() as opened: link.click()
            popup=opened.value
            upload_owner=suite.actor('admin-upload-owner','user','user',page=popup)
            channel=suite.api(upload_owner,'get','/channels/me').json()
            adapter=FunctionalAdapter(suite,'A-VIDEOS.04',channel['channelId'],prefix='LIVE-ADMIN-UPLOAD-')
            adapter.state['video_title']='HuTube QC — Admin upload '+suite.run_id
            case['steps']=['Admin real upload link → User Web popup','Login with supplied owner in the popup','Read exact owner identity/channel; separate Admin cookie remains present']
        suite.case(admin,'LIVE-ADMIN-UPLOAD-ENTRY','A-VIDEOS.04','Admin entrypoint to real Studio','Admin routes creation through the actual file upload pipeline and never reports a metadata-only success',enter,module='videos')
        if adapter:
            upload_owner['user_id']=upload_owner['identity']['userId']
            media.run(adapter,upload_owner,other)
        def persist(case):
            if not adapter or not adapter.state.get('video_id'):raise PrerequisiteMissing('The actual Studio upload did not create a video checkpoint')
            video_id=adapter.state['video_id']
            actual=suite.api(upload_owner,'get','/videos/'+video_id).json()
            assert actual['title']==adapter.state['video_title'] and actual['visibility']=='private'
            suite.go(admin,'/videos','app-admin-videos-page')
            search=admin['page'].locator('input[type=search]')
            search.fill(actual['title'])
            response=suite.response(admin,'/admin/videos',lambda:search.press('Enter'),params={'search':actual['title']})
            records=[v for v in response.json()['items'] if v['videoId']==video_id]
            assert len(records)==1 and records[0]['visibility']=='private'
            expect(admin['page'].locator('tbody .video-row').filter(has_text=actual['title'])).to_have_count(1)
            suite.go(admin,'/videos','app-admin-videos-page')
            search=admin['page'].locator('input[type=search]');search.fill(actual['title'])
            response=suite.response(admin,'/admin/videos',lambda:search.press('Enter'),params={'search':actual['title']})
            assert any(v['videoId']==video_id for v in response.json()['items'])
            case['resource_ids']=[video_id]
            case['steps']=['Admin upload entry → real browser file input → POST 201 checkpoint','Real decoding/playback and private access assertions run for this same ID','Owner read-back title/private; Admin searches same exact ID','Full navigation and repeat search → record still persisted']
        suite.case(admin,'A-VIDEOS-ADD-PERSISTENCE','A-VIDEOS.04','Admin upload persists a real video','The video created through the Admin → Studio journey has an actual ID and persists in the Admin list',persist,module='videos')
        def concurrent(case):
            if not adapter or not adapter.state.get('video_id'):raise PrerequisiteMissing('No new uploaded fixture for concurrent resolve')
            video_id=adapter.state['video_id']
            suite.api(upload_owner,'patch','/videos/'+video_id,data={'visibility':'public'})
            assert suite.api(upload_owner,'get','/videos/'+video_id).json()['moderationStatus']=='pending'
            queue=suite.api(admin,'get','/admin/moderation/queue',params={'page':1,'pageSize':100}).json()
            item=next(v for v in queue if v['videoId']==video_id)
            case_id=item['moderationCaseId']
            suite.go(admin,'/moderation/videos','app-admin-moderation-page')
            row=admin['page'].locator('.queue-table tbody tr').filter(has_text=video_id[:8])
            suite.response(admin,'/admin/moderation/'+case_id+'/claim',lambda:row.locator('.table-action.primary').click(),method='POST')
            review_layout(suite,admin,adapter.state['video_title'])
            # Two real concurrent requests from the authenticated Admin browser;
            # bearer stays in memory and is never stored in evidence/input data.
            results=admin['page'].evaluate('''async args => Promise.all([0,1].map(async () => {
              const response=await fetch(args.url,{method:'POST',headers:{'Content-Type':'application/json','Authorization':args.authorization},body:JSON.stringify({decision:'approve',reason:'QC concurrent resolve',internalNote:'New upload fixture'})});
              const body=await response.json(); return {status:response.status,code:body.code};
            }))''',{'url':admin['api_url']+'/admin/moderation/'+case_id+'/resolve','authorization':admin['headers']['Authorization']})
            assert sorted(v['status'] for v in results)==[200,409], results
            assert next(v for v in results if v['status']==409)['code']=='CASE_ALREADY_PROCESSED'
            assert suite.api(upload_owner,'get','/videos/'+video_id).json()['moderationStatus']=='approved'
            suite.api(other,'get','/videos/'+video_id+'/playback')
            suite.go(admin,'/moderation/videos','app-admin-moderation-page')
            admin['page'].locator('.status-tabs [role=tab]').nth(2).click()
            expect(admin['page'].locator('.queue-table tbody tr').filter(has_text=video_id[:8])).to_have_count(1)
            case['resource_ids']=[video_id,case_id]
            case['steps']=['New private upload → Public pending case','Actual Admin UI claims exact case','Two simultaneous real resolve requests → one 200 and one 409','Owner approved + other identity playback allowed','Reload processed list → same case once']
        suite.case(admin,'LIVE-MODERATION-CONCURRENT-RESOLVE','A-MODERATION.01','Concurrent approval is serialized','Only one concurrent decision succeeds and the exact fresh case remains consistent across both applications',concurrent,module='moderation')
    finally:
        try:
            if adapter and adapter.state.get('video_id'):
                video_id=adapter.state['video_id']
                suite.api(upload_owner,'delete','/videos/'+video_id,expected=(200,204))
                suite.api(upload_owner,'get','/videos/'+video_id,expected=(403,404))
                suite.report['cleanup'].append({'resource':'Admin entrypoint uploaded fixture','id':video_id,'status':'deleted-test-fixture'})
        finally:
            if upload_owner:suite.release_actor(upload_owner)
