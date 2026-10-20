"""Fresh browser multipart upload, real transcoding and playback on owner channel."""
from flows.user import media
from support.live_adapter import FunctionalAdapter
from flows.user import interactions,ratings
from playwright.sync_api import expect

def run(suite,owner,other,admin=None):
    channel=suite.api(owner,'get','/channels/me').json()
    adapter=FunctionalAdapter(suite,'U-STUDIO.03',channel['channelId'])
    owner['user_id']=owner['identity']['userId']
    try:
        media.run(adapter,owner,other)
        if adapter.state.get('video_id'):
            interactions.run(adapter,owner,other)
            ratings.run(adapter,owner)
            edit_video(suite,owner,adapter.state['video_id'],channel['channelId'])
            if admin:
                from flows.cross_app.live_moderation import run as cross_moderation
                cross_moderation(suite,owner,other,admin,adapter.state['video_id'],channel['channelId'])
    finally:
        video_id=adapter.state.get('video_id')
        if video_id:
            suite.api(owner,'delete','/videos/'+video_id,expected=(200,204))
            suite.api(owner,'get','/videos/'+video_id,expected=(403,404))
            suite.report['cleanup'].append({'resource':'private uploaded fixture','id':video_id,'status':'deleted-test-fixture'})

def edit_video(suite,owner,video_id,channel_id):
    page=owner['page']
    path='/videos/'+video_id
    route='/studio/content/'+video_id+'/edit?channelId='+channel_id
    def load():
        suite.go(owner,route,'app-video-edit-page')
        expect(page.locator('#video-title')).to_be_visible()
    def invalid(case):
        original=suite.api(owner,'get',path).json()
        load()
        page.locator('#video-title').fill('   ')
        page.locator('.header-actions .button-primary').click()
        expect(page.locator('[role=alert]')).to_be_visible()
        assert suite.api(owner,'get',path).json()['title']==original['title']
        case['steps']=['Whitespace title → UI save','Error visible','Original title unchanged']
    suite.case(owner,'U-STUDIO-LIVE-EDIT-REQUIRED','U-STUDIO.02','Blank title cannot persist','Whitespace is rejected and actual metadata remains unchanged',invalid,module='studio')
    for visibility in ['unlisted','private']:
        def save(case,visibility=visibility):
            load()
            title='HuTube QC — sửa metadata '+suite.run_id
            page.locator('#video-title').fill(title)
            page.locator('#video-description').fill('Metadata Unicode sửa qua UI, fixture riêng.')
            page.locator('input[name=visibility]').nth(1 if visibility=='unlisted' else 2).check()
            page.locator('#video-tags').fill('qclive')
            page.locator('#video-tags').press('Enter')
            suite.response(owner,path,lambda:page.locator('.header-actions .button-primary').click(),method='PATCH')
            load()
            value=suite.api(owner,'get',path).json()
            assert value['title']==title and value['visibility']==visibility
            expect(page.locator('#video-title')).to_have_value(title)
            expect(page.locator('#video-description')).to_have_value(value['description'])
            expect(page.locator('input[name=visibility]').nth(1 if visibility=='unlisted' else 2)).to_be_checked()
            expect(page.locator('.edit-tag-chip').filter(has_text='qclive')).to_have_count(1)
            case['resource_ids']=[video_id]
            case['steps']=['Edit title/description/tag/'+visibility,'Save PATCH','Reload and compare real metadata','Repeated tag does not duplicate']
        suite.case(owner,'U-STUDIO-LIVE-EDIT-'+visibility.upper(),'U-STUDIO.02','Persist '+visibility+' metadata','All edited fields persist for this uploaded fixture',save,module='studio')
