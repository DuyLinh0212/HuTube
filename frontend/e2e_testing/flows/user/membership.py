"""Channel collaboration with two fixed users; remove member after the cycle."""
from playwright.sync_api import expect


def run(suite, owner, member):
    channel=suite.state.get('channel')
    if not channel:
        suite.blocked(owner,'U-CHANNEL-INVITE-01','Invite member','Channel checkpoint missing')
        return
    base='/channels/'+channel['channel_id']
    invitation={}

    def open_members():
        page=owner['page']
        suite.go(owner,'/channel/'+channel['handle']+'/customize','app-channel-settings-page')
        page.locator('.tab-btn').filter(has_text='Thành viên').click()
        expect(page.locator('#inviteEmail')).to_be_visible()

    def invite():
        open_members()
        existing=suite.api(owner,'get',base+'/members')
        assert existing.status==200
        if any(item['userId']==member['user_id'] for item in existing.json()):
            expect(owner['page'].locator('.member-row').filter(has_text=member['email'])).to_be_visible()
            return 'reused'
        pending=suite.api(owner,'get',base+'/invitations')
        assert pending.status==200
        invitation.update(next((item for item in pending.json() if item['invitedEmail']==member['email'] and item['status']=='pending'),{}))
        if invitation:
            return 'reused'
        page=owner['page']
        page.locator('#inviteEmail').fill(member['email'])
        page.locator('#inviteRole').select_option('editor')
        with page.expect_response(lambda response:response.request.method=='POST' and response.url.endswith(base+'/members/invite')) as pending:
            page.locator('.invite-form button[type=submit]').click()
        assert pending.value.status in (200,201)
        invitation.update(pending.value.json())
        assert invitation['invitedEmail']==member['email'] and invitation['roleCode']=='editor'
        suite.state['channel_invitation_id']=invitation['channelInvitationId'];suite.save()
    try:
        if not suite.case(owner,'U-CHANNEL-INVITE-01','Owner gửi lời mời Editor cho member fixture',invite,
                          expected='Đúng channel/email/role và invitation ID; không gửi trùng pending'):
            return

        def accept():
            page=member['page']
            suite.go(member,'/studio/invitations','app-channel-invitations-page')
            if not invitation:
                expect(page.locator('.collaboration-card').filter(has_text=channel['handle'])).to_be_visible()
                return 'reused'
            card=page.locator('.invitation-card').filter(has_text=channel['handle'])
            with page.expect_response(lambda response:response.request.method=='POST' and response.url.endswith('/invitations/'+invitation['channelInvitationId']+'/accept')) as pending:
                card.locator('.button--primary').click()
            assert pending.value.status==200
            assert pending.value.json()['userId']==member['user_id']
            expect(card).to_have_count(0)
            expect(page.locator('.collaboration-card').filter(has_text=channel['handle'])).to_be_visible()
            stored=suite.api(owner,'get',base+'/members').json()
            assert any(item['userId']==member['user_id'] and item['roleCode']=='editor' for item in stored)
        if not suite.case(member,'U-CHANNEL-ACCEPT-01','Member accept, thấy channel cộng tác',accept,
                          expected='Lời mời biến mất, channel accessible, member Editor đúng user ID'):
            return

        def role():
            open_members()
            row=owner['page'].locator('.member-row').filter(has_text=member['email'])
            with owner['page'].expect_response(lambda response:response.request.method=='PATCH' and response.url.endswith(base+'/members/'+member['user_id']+'/role')) as pending:
                row.locator('.role-select').select_option('viewer')
            assert pending.value.status==200 and pending.value.json()['roleCode']=='viewer'
            open_members()
            expect(row.locator('.role-select')).to_have_value('viewer')
            member['page'].goto(suite.config['user_url']+'/studio/invitations')
            expect(member['page'].locator('.collaboration-card').filter(has_text=channel['handle'])).to_be_visible()
            forbidden=suite.api(member,'patch',base,data={'description':'Forbidden viewer edit'})
            assert forbidden.status==403
            escalation=suite.api(member,'patch',base+'/members/'+member['user_id']+'/role',data={'roleCode':'manager'})
            assert escalation.status==403
            assert any(item['userId']==member['user_id'] and item['roleCode']=='viewer' for item in suite.api(owner,'get',base+'/members').json())
        suite.case(owner,'U-CHANNEL-ROLE-01','Đổi Editor → Viewer; chặn sửa và tự nâng quyền',role,
                   expected='Role Viewer persist; API metadata edit và self-escalation 403')
    finally:
        def cleanup():
            members=suite.api(owner,'get',base+'/members')
            assert members.status==200
            if any(item['userId']==member['user_id'] for item in members.json()):
                open_members()
                page=owner['page'];row=page.locator('.member-row').filter(has_text=member['email'])
                page.once('dialog',lambda dialog:dialog.dismiss())
                row.locator('.btn-link-danger').click()
                expect(row).to_be_visible()
                page.once('dialog',lambda dialog:dialog.accept())
                with page.expect_response(lambda response:response.request.method=='DELETE' and response.url.endswith(base+'/members/'+member['user_id'])) as pending:
                    row.locator('.btn-link-danger').click()
                assert pending.value.status in (200,204)
                expect(row).to_have_count(0)
            elif invitation:
                pending=suite.api(owner,'get',base+'/invitations').json()
                if any(item['channelInvitationId']==invitation['channelInvitationId'] and item['status']=='pending' for item in pending):
                    assert suite.api(owner,'delete',base+'/invitations/'+invitation['channelInvitationId']).status in (200,204)
            stored=suite.api(owner,'get',base+'/members').json()
            assert not any(item['userId']==member['user_id'] for item in stored)
            assert any(item['userId']==owner['user_id'] and item['roleCode']=='owner' for item in stored)
        suite.case(owner,'U-CHANNEL-REMOVE-01','Cancel rồi remove member; giữ quyền owner',cleanup,
                   expected='Member bị loại đúng ID; owner giữ quyền; pending invite thất bại được dọn')
