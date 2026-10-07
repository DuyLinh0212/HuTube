"""Creator public submission -> Admin claim/approve -> another User playback."""
from playwright.sync_api import expect
from flows.user.playlist_items import run as run_playlist_items


def run(suite, owner, member, admin):
    video_id = suite.state.get('video_id')
    if not video_id:
        suite.blocked(owner, 'X-MODERATION-PUBLISH-01', 'Public submission', 'No uploaded fixture')
        return
    path='/videos/' + video_id
    video={}
    moderation={}

    def visibility(value):
        page=owner['page']
        suite.go(owner, '/studio/content', 'app-studio-content-page')
        row=page.locator('.video-row').filter(has=page.locator('a.video-title[href="/watch/'+video_id+'"]'))
        expect(row).to_be_visible()
        field=row.locator('.visibility-select')
        if field.input_value()!=value:
            with page.expect_response(lambda response:response.request.method=='PATCH' and response.url.endswith(path)) as pending:
                field.select_option(value)
            assert pending.value.status==200
        expect(field).to_have_value(value)
        expect(field).to_be_enabled()
        stored=suite.api(owner,'get',path)
        assert stored.status==200 and stored.json()['visibility']==value
        return stored.json()

    def submit_public():
        video.update(visibility('public'))
        assert video['visibility']=='public'
        suite.go(admin, '/moderation/videos', 'app-admin-moderation-page')
        suffix = '&status=processed' if video['moderationStatus']=='approved' else ''
        queue=suite.api(admin,'get','/admin/moderation/queue?page=1&pageSize=100'+suffix)
        assert queue.status==200
        matches=[item for item in queue.json() if item['videoId']==video_id]
        assert matches
        if video['moderationStatus']!='approved':
            assert len(matches)==1
        moderation.update(next((item for item in matches if item['moderationCaseId']==suite.state.get('moderation_case_id')),matches[0]))
        if video['moderationStatus']=='approved':
            return 'reused'
        assert moderation['status'] in ('pending','reviewing')
        suite.state['moderation_case_id']=moderation['moderationCaseId'];suite.save()
    try:
        suite.case(owner,'X-MODERATION-PUBLISH-01','User đổi public; Admin thấy đúng moderation case',submit_public,
                   module='moderation',expected='Cùng video ID trong queue; không tạo trùng case khi retry')

        if moderation:
            def claim_approve():
                page=admin['page']
                suite.go(admin,'/moderation/videos','app-admin-moderation-page')
                page.locator('input[type=search]').fill(video['title'])
                if moderation['status']=='approved':
                    page.locator('.status-tabs [role=tab]').nth(2).click()
                    expect(page.locator('tbody tr').filter(has_text=video_id[:8])).to_be_visible()
                    assert suite.api(owner,'get',path).json()['moderationStatus']=='approved'
                    return 'reused'
                if moderation['status']=='pending':
                    row=page.locator('tbody tr').filter(has_text=video_id[:8])
                    with page.expect_response(lambda response:response.request.method=='POST' and response.url.endswith('/'+moderation['moderationCaseId']+'/claim')) as pending:
                        row.locator('.table-action.primary').click()
                    assert pending.value.status==200
                page.locator('.status-tabs [role=tab]').nth(1).click()
                row=page.locator('tbody tr').filter(has_text=video_id[:8])
                row.locator('.table-action:not(.subtle)').first.click()
                page.locator('.decision-column input[type=text]').fill('Video fixture kỹ thuật E2E đáp ứng chính sách.')
                with page.expect_response(lambda response:response.request.method=='POST' and response.url.endswith('/'+moderation['moderationCaseId']+'/resolve')) as pending:
                    page.locator('.decision-button.approve').click()
                assert pending.value.status==200 and pending.value.json()['decision']=='approve'
                current=suite.api(owner,'get',path)
                assert current.status==200 and current.json()['moderationStatus']=='approved'
                page.locator('.status-tabs [role=tab]').nth(2).click()
                expect(page.locator('tbody tr').filter(has_text=video_id[:8])).to_be_visible()
            suite.case(admin,'A-MODERATION-APPROVE-01','Claim và approve video User qua UI',claim_approve,
                       expected='Decision approve persist đúng video ID; row chuyển sang processed')

        def member_playback():
            current=suite.api(owner,'get',path)
            assert current.status==200 and current.json()['moderationStatus']=='approved'
            suite.go(member,'/watch/'+video_id,'app-watch-page')
            expect(member['page'].locator('.video-header h1')).to_have_text(video['title'])
            playback=suite.api(member,'get',path+'/playback')
            assert playback.status==200 and playback.json()['renditions']
            member['page'].wait_for_function('() => {const v=document.querySelector("video");return v&&v.readyState>=1&&v.duration>0}',timeout=45000)
        suite.case(member,'X-MODERATION-WATCH-01','User khác lấy playback sau khi Admin approve',member_playback,
                   module='moderation',expected='Playback 200 có rendition; UI metadata video đúng ID')
        run_playlist_items(suite, owner, member)
    finally:
        def restore_private():
            visibility('private')
            assert suite.api(member,'get',path+'/playback').status in (403,404)
        suite.case(owner,'X-MODERATION-RESTORE-01','Khôi phục video fixture về private',restore_private,
                   module='moderation',expected='Private persist và chặn lại playback của member')
