from pathlib import Path
import json, base64, os
from urllib.parse import urlparse, parse_qs
from playwright.sync_api import sync_playwright, expect
ROOT=Path(os.environ.get('BUGFIX_OUTPUT_DIR', str(Path(__file__).resolve().parents[2]/'.codex-build-verify')))
ROOT.mkdir(parents=True, exist_ok=True)
UID='11111111-1111-4111-8111-111111111111'
CID='22222222-2222-4222-8222-222222222222'
VID='33333333-3333-4333-8333-333333333333'
PID='44444444-4444-4444-8444-444444444444'
NOW='2026-10-02T00:00:00Z'
channel=dict(channelId=CID,ownerUserId=UID,name='Regression Channel',handle='regression',description='Public channel',avatarUrl=None,bannerUrl=None,contactEmail=None,watermarkUrl=None,status='active',createdAt=NOW,subscriberCount=10,videoCount=1,isOwner=True,myRole='owner',permissions=['video.upload','video.edit','video.view','analytics.view'],settings='{}',ownerName='Test owner',ownerEmail='test@example.test',activeStrikeCount=0)
video=dict(videoId=VID,channelId=CID,channelName=channel['name'],channelHandle='regression',title='Regression video',description='Original description',thumbnailUrl=None,duration=120,visibility='public',status='published',moderationStatus='approved',views=8,ageRestricted=False,createdAt=NOW,publishedAt=NOW,uploadedByUserId=UID,stats=dict(views=8,likes=1,dislikes=0,comments=0,watchSeconds=30),viewerState=None,videoUrl='',fileSize=20,chapters=[],tags=[])
plan=dict(planId=PID,code='pro',name='Regression Plan',description='Plan details',price=99000,durationDays=30,storageLimit=100000000,maxUploadSize=10000000,maxVideoDuration=720,maxVideoQuality='720p',maxDownloadQuality='720p',maxMembers=1,status='active',features={})
results=[]
class Mock:
    def __init__(self,admin=False,readonly=False,anon=False): self.admin=admin;self.readonly=readonly;self.anon=anon;self.fail_save=False;self.fail_counts=False;self.saved=[]
    def route(self,route):
        u=urlparse(route.request.url); p=u.path; q=parse_qs(u.query); status=200
        headers={'Access-Control-Allow-Origin':route.request.headers.get('origin','http://127.0.0.1:4301' if self.admin else 'http://127.0.0.1:4300'),'Access-Control-Allow-Credentials':'true','Access-Control-Allow-Headers':'authorization, content-type, x-hutube-client, x-hutube-app','Access-Control-Allow-Methods':'GET, POST, PUT, PATCH, DELETE, OPTIONS'}
        if route.request.method=='OPTIONS':route.fulfill(status=204,headers=headers);return
        if p.endswith('config.json'): data=dict(API_BASE_URL='http://127.0.0.1:5080/api/v1',USER_WEB_BASE_URL='http://127.0.0.1:4300')
        elif '/api/v1/' not in p: route.continue_();return
        else:
            p=p.split('/api/v1',1)[1]
            user=dict(userId=UID,username='test',email='test@example.test',displayName='Test owner',emailVerified=True,isAdmin=self.admin,role='reviewer' if self.readonly else 'super_admin',permissions=['channel.view','video.view','role.view','plan.view','policy.view'])
            if p=='/auth/refresh':
                if self.anon: status=401;data=dict(code='UNAUTHORIZED')
                else:
                    payload=base64.urlsafe_b64encode(json.dumps(dict(sub=UID,sid=UID,exp=2000000000)).encode()).decode().rstrip('=')
                    data=dict(accessToken='e30.'+payload+'.test',expiresAt='2030-01-01T00:00:00Z',user=user)
            elif p in ['/admin/me','/auth/me']:data=user
            elif p=='/system/config':data={}
            elif p in ['/channels/me','/channels/'+CID] or p.startswith('/channels/handle/'):data=channel
            elif p=='/channels/accessible':data=[channel]
            elif p=='/admin/channels':
                data=dict(items=[channel],total=1,page=int(q.get('page',['1'])[0]),pageSize=int(q.get('pageSize',['8'])[0]))
                if self.fail_counts and q.get('pageSize')==['1']:status=500;data=dict(message='Count unavailable')
            elif p=='/admin/videos':data=dict(items=[video],total=1,page=1,pageSize=8)
            elif p=='/admin/videos/'+VID:data=dict(video=video,description=video['description'],categoryId=None,categoryName=None,videoUrl='',fileSize=20,duration=120,history=[],reports=[])
            elif p.endswith('/metadata'):
                self.saved.append(route.request.post_data_json)
                if self.fail_save:status=409;data=dict(message='Regression save conflict')
                else:status=204;data=None
            elif p=='/admin/channels/'+CID:data=dict(channel=channel,description='Details',videos=[],history=[])
            elif p=='/admin/policies':data=[dict(policyId=PID,code='REGRESSION',name='Policy',group='guidelines',content='Text',severity='medium',version='1',status='active',createdAt=NOW,updatedAt=NOW)]
            elif p=='/admin/roles':data=[dict(roleId=UID,code='reviewer',name='Reviewer',description='Role',permissions=['channel.view'],status='active',isSystemRole=False,assignedUserCount=0)]
            elif p=='/admin/permissions':data=[dict(permissionId=UID,code='channel.view',name='View channels',description='View',status='active')]
            elif p=='/videos/'+VID:data=video
            elif p=='/videos/'+VID+'/playback':data=dict(videoId=VID,renditions=[])
            elif p in ['/plans/'+PID,'/plans/my-plan']:data=dict(**plan,usedStorage=0,remainingStorage=100000000,members=[],subscription=dict(isExpired=False))
            elif p.endswith('/share'):data=dict(**plan,shareUrl='http://127.0.0.1:4300/plans/'+PID)
            elif p=='/admin/plans' or p=='/plans':data=[plan]
            elif p.startswith('/feed/'):
                data=dict(items=[dict(video,videoId=VID[:-1]+str(i),title=f'Video {i}') for i in range(4)] if p=='/feed/home' else [],total=4 if p=='/feed/home' else 0,page=1,pageSize=30,hasMore=False)
            elif p in ['/videos/manage','/videos/search'] or p.endswith('/videos') or p.endswith('/comments') or p.endswith('/replies'):data=dict(items=[],total=0,page=1,pageSize=50,hasMore=False)
            elif p=='/videos/upload-preflight':data=dict(allowed=True,maxFileSize=100000000,maxDuration=10000,maxQuality='720p',remainingStorage=100000000)
            elif p=='/notifications':data=dict(items=[],unreadCount=0,hasMore=False)
            elif p.startswith('/hubs/') or 'negotiate' in p:status=503;data={}
            else:data=[]
        route.fulfill(status=status,content_type='application/json',body='' if status==204 else json.dumps(data),headers=headers)

def go(page,base,path):
    page.goto(base+path);page.wait_for_load_state('networkidle'); print(json.dumps(dict(path=path,url=page.url,buttons=page.locator('button').all_text_contents()[:12]),ensure_ascii=False),flush=True)
def drawer(page):
    page.locator('.menu-button').click();close=page.locator('.side-nav.is-open .nav-close');expect(close).to_be_visible();close.click();expect(page.locator('.side-nav.is-open')).to_have_count(0)
def check(name,fn):
    try:fn();results.append(dict(name=name,status='passed'));print('PASS '+name,flush=True)
    except Exception as e:results.append(dict(name=name,status='failed',error=str(e)));print('FAIL '+name+': '+str(e)[:350],flush=True)

with sync_playwright() as pw:
    browser=pw.chromium.launch(executable_path=os.environ.get('CHROME_BIN'),headless=True)
    mock=Mock(admin=True);context=browser.new_context(viewport=dict(width=360,height=640));context.route('**/*',mock.route);page=context.new_page();page.set_default_timeout(5000)
    go(page,'http://127.0.0.1:4301','/channels')
    check('Admin drawer receives clicks above topbar',lambda:drawer(page))
    def keyboard():
        select=page.locator('app-custom-select button[role=combobox]').first;select.focus();select.press('ArrowDown');select.press('ArrowDown');select.press('Enter');expect(select).to_have_attribute('aria-expanded','false');assert 'Đang hoạt động' in select.inner_text() or 'Hoạt động' in select.inner_text() or 'Active' in select.inner_text()
    check('Admin select keyboard selection',keyboard)
    check('Unsupported channel time filter disabled',lambda:expect(page.locator('app-custom-select button[role=combobox]').nth(1)).to_be_disabled())
    page.set_viewport_size(dict(width=1280,height=720));go(page,'http://127.0.0.1:4301','/videos')
    def menu():
        page.set_viewport_size(dict(width=1280,height=360))
        page.locator('tbody tr').first.locator('.icon-action-btn').last.click();menu=page.locator('.dropdown-menu');expect(menu).to_be_visible();box=menu.bounding_box();assert box['y']>=0 and box['y']+box['height']<=360;assert menu.evaluate('(e)=>{const r=e.getBoundingClientRect();return e.contains(document.elementFromPoint(r.x+20,r.y+20))}')
        page.evaluate('window.scrollBy(0,-100)');expect(menu).to_have_count(0)
    check('Single-row menu escapes clipping and closes on table scroll',menu)
    def edit():
        page.locator('tbody tr').first.locator('.icon-action-btn').nth(2).click();expect(page.locator('textarea[name=desc]')).to_be_enabled();page.locator('textarea[name=desc]').fill('');page.locator('input[name=reason]').fill('Regression reason');mock.fail_save=True;page.locator('button[type=submit]').click();expect(page.locator('.modal-body [role=alert]')).to_contain_text('Regression save conflict');assert mock.saved[-1]['description']==''
        page.set_viewport_size(dict(width=640,height=360));assert page.locator('.modal-dialog').evaluate('(e)=>e.scrollHeight>e.clientHeight || getComputedStyle(e).overflowY==="auto"');page.locator('.modal-close').click()
    check('Edit clears description and shows API error inside scrollable modal',edit)
    page.set_viewport_size(dict(width=360,height=640));go(page,'http://127.0.0.1:4301','/policies')
    def policy():
        table=page.locator('.table-container');assert table.evaluate('(e)=>e.scrollWidth>e.clientWidth && ["auto","scroll"].includes(getComputedStyle(e).overflowX)');table.evaluate('(e)=>e.scrollLeft=e.scrollWidth');assert table.evaluate('(e)=>e.scrollLeft>0')
    check('Policies table scrolls horizontally on mobile',policy);page.screenshot(path=str(ROOT/'admin-policies-mobile.png'),full_page=True)
    go(page,'http://127.0.0.1:4301','/roles')
    def role():
        page.locator('button.primary-action').first.click();expect(page.locator('.role-form')).to_be_visible();assert len(page.locator('.role-form').evaluate('(e)=>getComputedStyle(e).gridTemplateColumns').split())==1;page.screenshot(path=str(ROOT/'admin-role-mobile.png'),full_page=True)
    check('RBAC form has one column on mobile',role)
    go(page,'http://127.0.0.1:4301','/plans')
    def darkplans():
        page.evaluate("localStorage.setItem('hutube_admin_theme','dark')");page.reload();page.wait_for_load_state('networkidle')
        expect(page.locator('html')).to_have_attribute('data-theme','dark')
        surface=page.locator('.plan-table');assert surface.evaluate('(e)=>{const s=getComputedStyle(e);return s.backgroundColor!=="rgb(255, 255, 255)" && s.color!==s.backgroundColor}')
    check('Plans use dark theme surface and readable foreground',darkplans)
    context.close()
    mock=Mock(admin=True,readonly=True);mock.fail_counts=True
    context=browser.new_context(viewport=dict(width=1280,height=720));context.route('**/*',mock.route);page=context.new_page();page.set_default_timeout(5000);go(page,'http://127.0.0.1:4301','/channels')
    check('Counts API failure displays unknown rather than sample totals',lambda:expect(page.locator('.channel-tabs')).to_contain_text('—'))
    def readonlychannel():
        page.locator('tbody tr').first.locator('button').last.click();items=page.locator('.dropdown-menu button');assert items.count()>0;assert all(items.nth(i).is_disabled() for i in range(1,items.count()))
    check('View-only channel mutation controls disabled',readonlychannel)
    go(page,'http://127.0.0.1:4301','/videos')
    check('View-only video edit disabled',lambda:expect(page.locator('tbody tr').first.locator('.icon-action-btn').nth(2)).to_be_disabled());context.close()
    mock=Mock(anon=True);context=browser.new_context(viewport=dict(width=360,height=640));context.route('**/*',mock.route);page=context.new_page();page.set_default_timeout(5000);go(page,'http://127.0.0.1:4300','/channel/regression')
    check('Anonymous public channel remains accessible',lambda:expect(page.locator('h1')).to_contain_text('Regression Channel'))
    check('User drawer close stays above topbar',lambda:drawer(page))
    go(page,'http://127.0.0.1:4300','/privacy')
    check('Unsupported privacy actions disabled',lambda:expect(page.locator('.btn-tool-primary')).to_be_disabled());context.close()
    mock=Mock();context=browser.new_context(viewport=dict(width=320,height=640));context.route('**/*',mock.route);page=context.new_page();page.set_default_timeout(5000);go(page,'http://127.0.0.1:4300','/plans/'+PID)
    def plancheck():
        expect(page.locator('.cta-subscribe')).to_be_disabled();assert page.locator('.detail-hero').evaluate('(e)=>e.scrollWidth<=e.clientWidth+1')
    check('Plan reload restores current plan and hero fits 320px',plancheck)
    go(page,'http://127.0.0.1:4300','/home')
    check('Home recommendations use one column on phone',lambda:expect(page.locator('.feed-section--for-you .grid')).to_have_css('grid-template-columns',page.locator('.feed-section--for-you .grid').evaluate('(e)=>getComputedStyle(e).width')))
    page.screenshot(path=str(ROOT/'user-home-mobile.png'),full_page=True)
    page.set_viewport_size(dict(width=1280,height=720));go(page,'http://127.0.0.1:4300','/studio/upload')
    def pick():
        button=page.locator('.btn-select-file');button.focus()
        with page.expect_file_chooser() as event:button.press('Enter')
        event.value.set_files(str(ROOT/'sample-720.mp4'))
        expect(page.locator('.file-name')).to_contain_text('sample-720')
        expect(page.locator('.progress-bar-labels')).to_contain_text('Sẵn sàng tải lên',timeout=15000)
    check('Upload picker opens using keyboard',pick)
    def draft():
        page.locator('.btn-wizard-next').click();expect(page.locator('#videoTitle')).to_be_visible()
        page.locator('#videoTitle').fill('Saved draft regression');page.locator('#videoDesc').fill('Retained description')
        page.locator('.btn-wizard-draft').click()
        assert json.loads(page.evaluate("key=>localStorage.getItem('hutube.upload.draft.'+key)",UID+'.'+CID))['videoTitle']=='Saved draft regression'
        page.reload();page.wait_for_load_state('networkidle')
        page.locator('#videoFile').set_input_files(str(ROOT/'sample-720.mp4'));page.wait_for_load_state('networkidle')
        page.locator('.stepper-item').nth(1).click();expect(page.locator('#videoTitle')).to_have_value('Saved draft regression');expect(page.locator('#videoDesc')).to_have_value('Retained description')
    check('Upload draft survives reload and selecting the file again',draft)
    go(page,'http://127.0.0.1:4300','/studio/content/'+VID+'/edit')
    def thumbnail():
        page.set_viewport_size(dict(width=1200,height=720));layout=page.locator('.thumbnail-layout');expect(layout).to_be_visible();assert len(layout.evaluate('(e)=>getComputedStyle(e).gridTemplateColumns').split())==1;assert layout.evaluate('(e)=>e.scrollWidth<=e.clientWidth+1')
    check('Editor thumbnail layout responds to available column width',thumbnail)
    context.close();browser.close()
(ROOT/'browser-results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf8')
assert all(r['status']=='passed' for r in results), 'Browser checks failed; see browser-results.json'
