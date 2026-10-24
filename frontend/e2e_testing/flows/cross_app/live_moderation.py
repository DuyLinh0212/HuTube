"""Fresh uploaded ID through public review, metadata, hide/remove and restore."""
from playwright.sync_api import expect
from support.live_suite import PrerequisiteMissing

def run(suite,owner,other,admin,video_id,channel_id):
    path='/videos/'+video_id
    page=owner['page']; admin_page=admin['page']
    checkpoint={}
    def submit(case):
        suite.go(owner,'/studio/content?channelId='+channel_id,'app-studio-content-page')
        row=page.locator('.video-row').filter(has=page.locator('a.video-title[href="/watch/'+video_id+'"]'))
        expect(row).to_be_visible()
        suite.response(owner,path,lambda:row.locator('.visibility-select').select_option('public'),method='PATCH')
        value=suite.api(owner,'get',path).json()
        assert value['visibility']=='public' and value['moderationStatus']=='pending'
        pending=suite.api(admin,'get','/admin/moderation/queue',params={'page':1,'pageSize':100}).json()
        matches=[item for item in pending if item['videoId']==video_id]
        assert len(matches)==1
        checkpoint.update(matches[0])
        (suite.run_dir/'moderation-fixture.json').write_text(__import__('json').dumps({'video_id':video_id,'moderation_case_id':checkpoint['moderationCaseId']}),encoding='utf-8')
        case['resource_ids']=[video_id,checkpoint['moderationCaseId']]
        case['steps']=['Fresh private upload → Studio visibility Public','Read pending video and exact queue case ID','Assert one case for this same video']
    suite.case(owner,'LIVE-MODERATION-PUBLIC-SUBMIT','A-MODERATION.01','Submit fresh video to review','New public submission creates exactly one pending review case for this uploaded ID',submit,module='moderation')
    def review_row(status_index):
        suite.go(admin,'/moderation/videos','app-admin-moderation-page')
        admin_page.locator('input[type=search]').fill(suite.api(owner,'get',path).json()['title'])
        admin_page.locator('.status-tabs [role=tab]').nth(status_index).click()
        row=admin_page.locator('tbody tr').filter(has_text=video_id[:8])
        expect(row).to_have_count(1)
        return row
    def approve(case):
        if not checkpoint: raise PrerequisiteMissing('Fresh public submission did not yield a review checkpoint')
        case_id=checkpoint['moderationCaseId']
        row=review_row(0)
        suite.response(admin,'/admin/moderation/'+case_id+'/claim',lambda:row.locator('.table-action.primary').click(),method='POST')
        row=review_row(1)
        suite.response(admin,'/admin/moderation/'+case_id+'/release',lambda:row.locator('.table-action.subtle').click(),method='POST')
        row=review_row(0)
        suite.response(admin,'/admin/moderation/'+case_id+'/claim',lambda:row.locator('.table-action.primary').click(),method='POST')
        row=review_row(1)
        row.locator('.table-action:not(.subtle)').first.click()
        admin_page.locator('.decision-column input[type=text]').fill('QC fresh video technical approval '+suite.run_id)
        admin_page.locator('.decision-column textarea').fill('Exact fixture ID '+video_id)
        suite.evidence(admin,case,'claimed-review')
        response=suite.response(admin,'/admin/moderation/'+case_id+'/resolve',lambda:admin_page.locator('.decision-button.approve').click(),method='POST')
        assert response.json()['decision']=='approve'
        assert suite.api(owner,'get',path).json()['moderationStatus']=='approved'
        review_row(2)
        processed=suite.api(admin,'get','/admin/moderation/queue',params={'status':'processed','page':1,'pageSize':100}).json()
        assert sum(item['moderationCaseId']==case_id for item in processed)==1
        case['resource_ids']=[video_id,case_id]
        case['steps']=['Admin finds exact fresh queue case','Claim → reviewing → release → pending','Claim same case again','Approve with reason/internal note','Owner API approved; Admin processed row has same ID once']
    suite.case(admin,'LIVE-MODERATION-CLAIM-RELEASE-APPROVE','A-MODERATION.01','Claim, release and approve same fresh video','State transitions and decision persist across both applications with the same video/case IDs',approve,module='moderation')
    def replay(case):
        if not checkpoint or suite.api(owner,'get',path).json()['moderationStatus']!='approved':
            raise PrerequisiteMissing('No approved fresh fixture for processed-decision replay')
        case_id=checkpoint['moderationCaseId']
        # Only replay our just-created fixture, never an existing user's case.
        response=suite.api(admin,'post','/admin/moderation/'+case_id+'/resolve',data={'decision':'approve','reason':'QC replay of already processed fixture','internalNote':'Replay boundary '+suite.run_id},expected=(200,400,409,422))
        assert response.status in (400,409,422), 'Already processed moderation case accepted another resolve HTTP '+str(response.status)+'; duplicate resolution/notification must be prevented'
        assert suite.api(owner,'get',path).json()['moderationStatus']=='approved'
        case['resource_ids']=[video_id,case_id]
        case['steps']=['Read approved state of exact new fixture','Replay approval on the same processed case ID','Require conflict/validation rejection and unchanged approved state']
    suite.case(admin,'LIVE-MODERATION-PROCESSED-REPLAY','A-MODERATION.01','Processed decision replay boundary','A processed moderation decision cannot execute approval/notification again',replay,module='moderation')
    def playback(case):
        if suite.api(owner,'get',path).json()['moderationStatus']!='approved': raise PrerequisiteMissing('Fixture review is not approved')
        suite.go(other,'/watch/'+video_id,'app-watch-page')
        expected=suite.api(owner,'get',path).json()
        expect(other['page'].locator('.video-header h1')).to_have_text(expected['title'])
        actual=suite.api(other,'get',path+'/playback').json()
        assert actual['renditions']
        other['page'].wait_for_function('()=>{const video=document.querySelector("video");return video&&video.readyState>=1&&video.duration>0}',timeout=45000)
        case['resource_ids']=[video_id]
        case['steps']=['Other supplied identity opens approved public video','Compare exact title and real playback renditions','Native player decodes nonzero duration']
    suite.case(other,'LIVE-MODERATION-OTHER-PLAYBACK','U-WATCH.05','Other identity playback after approval','Approval enables real playback for a different supplied identity',playback,module='moderation')
    def load_video():
        suite.go(admin,'/videos','app-admin-videos-page')
        title=suite.api(admin,'get','/admin/videos/'+video_id).json()['video']['title']
        admin_page.locator('input[type=search]').fill(title)
        suite.response(admin,'/admin/videos',lambda:admin_page.locator('input[type=search]').press('Enter'),params={'search':title})
        row=admin_page.locator('tbody .video-row').filter(has_text=title)
        expect(row).to_have_count(1)
        return row
    def edit(case):
        row=load_video()
        suite.response(admin,'/admin/videos/'+video_id,lambda:row.locator('button[title="Chỉnh sửa thông tin"]').click())
        expect(admin_page.locator('input[name=title]')).to_be_enabled()
        expect(admin_page.locator('.btn-modal-confirm')).to_be_disabled()
        title='HuTube QC Admin sửa 🎬 '+suite.run_id
        admin_page.locator('input[name=title]').fill(title)
        admin_page.locator('textarea[name=desc]').fill('')
        admin_page.locator('select[name=cat]').select_option('')
        admin_page.locator('input[name=reason]').fill('QC metadata and clear fields')
        suite.evidence(admin,case,'metadata-before-save')
        suite.response(admin,'/admin/videos/'+video_id+'/metadata',lambda:admin_page.locator('.btn-modal-confirm').click(),method='PUT',status=(200,204))
        expect(admin_page.locator('.modal-dialog')).to_have_count(0)
        saved=suite.api(admin,'get','/admin/videos/'+video_id).json()
        assert saved['video']['title']==title and not saved['description'] and saved['video']['categoryId'] is None
        assert any(item['action']=='admin.video.edit_metadata' for item in saved['history'])
        row=load_video(); expect(row).to_contain_text(title)
        case['resource_ids']=[video_id]
        case['steps']=['Exact fresh video → edit metadata','Reason required; set Unicode title and clear description/category','Real PUT → read back all cleared fields and audit','Reload list → same fresh ID/title']
    suite.case(admin,'LIVE-ADMIN-VIDEO-METADATA-SAVE','A-VIDEOS.02','Save and clear metadata on fresh fixture','Title/description/category mutation persists and creates correct audit entry',edit,module='videos')
    for action,label,blocked in [('hide','Ẩn video',True),('unhide','Bỏ ẩn video',False),('remove','Gỡ video vi phạm',True),('restore','Khôi phục video',False)]:
        def mutate(case,action=action,label=label,blocked=blocked):
            before=suite.api(admin,'get','/admin/videos/'+video_id).json()['video']
            def open_action():
                row=load_video()
                row.locator('button[title="Thao tác khác"]').click()
                admin_page.locator('.dropdown-menu').get_by_role('button',name=label,exact=True).click()
                expect(admin_page.locator('app-confirm-dialog .confirm-submit')).to_be_disabled()
            open_action()
            admin_page.locator('.modal-textarea').fill('QC cancel '+action)
            admin_page.locator('app-confirm-dialog .confirm-cancel').click()
            assert suite.api(admin,'get','/admin/videos/'+video_id).json()['video']['status']==before['status']
            open_action()
            admin_page.locator('.modal-textarea').fill('QC '+action+' fresh fixture '+video_id)
            admin_page.locator('.modal-checkbox-label input').uncheck()
            suite.evidence(admin,case,action+'-pending')
            suite.response(admin,'/admin/videos/'+video_id+'/'+action,lambda:admin_page.locator('app-confirm-dialog .confirm-submit').click(),method='POST',status=(200,204))
            expect(admin_page.locator('.modal-dialog')).to_have_count(0)
            detail=suite.api(admin,'get','/admin/videos/'+video_id).json()
            assert (detail['video']['status']=='blocked')==blocked
            assert any(item['action']=='admin.video.'+action for item in detail['history'])
            suite.api(other,'get',path+'/playback',expected=(403,404) if blocked else 200)
            load_video()
            suite.evidence(admin,case,action+'-persisted')
            case['resource_ids']=[video_id]
            case['steps']=['Open '+action+' for exact fresh fixture; required reason','Cancel → original state unchanged','Confirm with reason and notifyOwner=false','Read persisted state/audit and cross-user playback deny/allow','Reload exact Admin list row']
        suite.case(admin,'LIVE-ADMIN-VIDEO-'+action.upper(),'A-VIDEOS.03','Cancel/confirm '+action+' and cross-user playback','Action affects only this fixture and User playback agrees with persisted Admin state',mutate,module='videos')
