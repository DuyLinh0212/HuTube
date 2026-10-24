from support.ui_confirmation import app_confirm
import json
import re
import struct
import zlib
from playwright.sync_api import expect
from support.live_suite import PrerequisiteMissing
from flows.expanded.common import snapshot_module

def png_bytes():
    def chunk(kind,data):return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    return b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',32,32,8,2,0,0,0))+chunk(b'IDAT',zlib.compress((b'\x00'+b'\x22\x77\xaa'*32)*32))+chunk(b'IEND',b'')

def create_channel(suite,actor,key):
    page=actor['page'];result={}
    def create(case):
        suite.go(actor,'/channel/create','app-channel-create-page')
        expect(page.locator('#channelName')).to_be_visible()
        expect(page.locator('button[type=submit]')).to_be_disabled()
        page.locator('#channelName').fill('QC '+key+' '+suite.run_id[:15])
        handle='qc-'+key+'-'+suite.run_id[9:15]
        page.locator('#channelHandle').fill(handle)
        page.locator('#channelDescription').fill('Kênh fixture riêng cho QC mở rộng — Unicode.')
        expect(page.locator('button[type=submit]')).to_be_enabled(timeout=20000)
        response=suite.response(actor,'/channels',lambda:page.locator('button[type=submit]').click(),method='POST',status=201)
        result.update(response.json());assert result['ownerUserId']==actor['identity']['userId']
        me=suite.api(actor,'get','/channels/me').json();assert me['channelId']==result['channelId'] and me['handle']==handle
        suite.go(actor,'/channel/create','app-channel-create-page');expect(page.locator('.existing-channel-card')).to_contain_text(result['name'])
        suite.api(actor,'post','/channels',data={'name':'Duplicate attempt','handle':handle+'-dup'},expected=409)
        case['resource_ids']=[result['channelId']]
        case['steps']=['New owner → empty create action disabled','UI POST 201 with valid Unicode metadata/handle','Read exact owner/channel ID and normalized handle','Reload create route → existing card; repeat creation is 409']
    suite.case(actor,'FULL-CHANNEL-CREATE-'+key.upper(),'U-CHANNEL.01','Create owned channel '+key,'One actual channel per new owner, persistence and duplicate boundary',create,module='channel')
    if not result:raise PrerequisiteMissing('Channel creation did not yield fixture ID')
    return result

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    if suite.api(actors['member'],'get','/auth/me',expected=(200,401)).status==401:
        suite.release_actor(actors['member'])
        actors['member']=suite.actor('member-after-password-reset','user','member')
    owner,member,target=actors['owner'],actors['member'],actors['target'];page=owner['page']
    channel=create_channel(suite,owner,'owner');secondary=create_channel(suite,target,'secondary')
    suite.fixtures={'channel':channel,'secondary_channel':secondary}
    cid=channel['channelId'];route='/channel/'+channel['handle']+'/customize'
    def load():suite.go(owner,route,'app-channel-settings-page');expect(page.locator('#chName')).to_be_visible()
    def duplicate_handle(case):
        response=suite.api(member,'post','/channels',data={'name':'Other owner','handle':channel['handle']},expected=409)
        assert response.json()['code']=='HANDLE_ALREADY_EXISTS'
        suite.go(member,'/channel/create','app-channel-create-page');member['page'].locator('#channelName').fill('Other owner');member['page'].locator('#channelHandle').fill(channel['handle'])
        expect(member['page'].locator('button[type=submit]')).to_be_disabled(timeout=20000)
        case['steps']=['Different owner attempts exact existing handle → 409','UI handle check disables creation; no Member channel is created']
    suite.case(member,'FULL-CHANNEL-HANDLE-DUPLICATE','U-CHANNEL.01','Duplicate handle across owners','Handle uniqueness is enforced in UI and backend',duplicate_handle,module='channel')
    def links(case):
        load();page.locator('#chDesc').fill('Description saved '+suite.run_id)
        for i in range(2):
            page.locator('.btn-add-link').click();page.locator('#link-url-'+str(i)).fill('https://example.test/qc-'+str(i))
        suite.response(owner,'/channels/'+cid,lambda:page.locator('.basic-tab-pane .form-actions .btn-primary').click(),method='PATCH')
        value=suite.api(owner,'get','/channels/'+cid).json();settings=json.loads(value['settings']);assert len(settings['links'])==2
        load();expect(page.locator('.link-row-card')).to_have_count(2)
        # A changed unsaved value must be lost on full navigation.
        page.locator('#chDesc').fill('Do not persist this');load();expect(page.locator('#chDesc')).to_have_value(value['description'])
        page.locator('.btn-remove-link').first.click()
        suite.response(owner,'/channels/'+cid,lambda:page.locator('.basic-tab-pane .form-actions .btn-primary').click(),method='PATCH')
        load();expect(page.locator('.link-row-card')).to_have_count(1)
        assert len(json.loads(suite.api(owner,'get','/channels/'+cid).json()['settings'])['links'])==1
        case['resource_ids']=[cid];case['steps']=['Add two links and description → actual PATCH','Reload/API read-back retains exact links','Unsaved description discarded by navigation','Remove first link → save/reload leaves one']
    suite.case(owner,'FULL-CHANNEL-LINKS-SAVE-CANCEL-REMOVE','U-CHANNEL.02','Persist channel links and cancel unsaved metadata','Only saved values persist; exact link count/order survives reload',links,module='channel')
    for index,kind in enumerate(['avatar','banner','watermark']):
        def branding(case,index=index,kind=kind):
            load();page.locator('.settings-tabs-nav .tab-btn').nth(1).click()
            file=page.locator('.branding-card input[type=file]').nth(index)
            response=suite.response(owner,'/channels/'+cid+'/'+kind,lambda:file.set_input_files({'name':'qc-'+kind+'.png','mimeType':'image/png','buffer':png_bytes()}),method='POST')
            url=response.json()[kind+'Url'];assert url
            load();page.locator('.settings-tabs-nav .tab-btn').nth(1).click()
            image=page.locator('.branding-card').nth(index).locator('img');expect(image).to_have_count(1)
            image.evaluate('(img)=>img.decode()');assert image.evaluate('(img)=>img.naturalWidth>0')
            assert suite.api(owner,'get','/channels/'+cid).json()[kind+'Url']==url
            case['resource_ids']=[cid];case['steps']=['Real PNG file input → actual upload 200','Reload branding → browser decodes image','API read-back retains the exact uploaded URL']
        suite.case(owner,'FULL-CHANNEL-BRANDING-'+kind.upper(),'U-CHANNEL.02','Valid '+kind+' upload','Valid image is persisted and decoded after reload',branding,module='channel')
    invitation={}
    def invite_accept(case):
        load();page.locator('.settings-tabs-nav .tab-btn').nth(2).click()
        page.locator('#inviteEmail').fill(member['identity']['email']);page.locator('#inviteRole').select_option('editor')
        response=suite.response(owner,'/channels/'+cid+'/members/invite',lambda:page.locator('.invite-form button[type=submit]').click(),method='POST',status=(200,201))
        invitation.update(response.json());iid=invitation['channelInvitationId']
        suite.go(member,'/studio/invitations','app-channel-invitations-page')
        card=member['page'].locator('.invitation-card').filter(has_text=channel['name']);expect(card).to_have_count(1)
        suite.response(member,'/channels/invitations/'+iid+'/accept',lambda:card.locator('.button--primary').click(),method='POST')
        accessible=suite.api(member,'get','/channels/accessible').json();assert any(c['channelId']==cid and c['myRole']=='editor' for c in accessible)
        suite.api(member,'post','/channels/invitations/'+iid+'/accept',data={},expected=(400,409))
        suite.go(owner,route,'app-channel-settings-page');page.locator('.settings-tabs-nav .tab-btn').nth(2).click()
        expect(page.locator('.member-row').filter(has_text=member['identity']['email'])).to_have_count(1)
        case['resource_ids']=[cid,iid];case['steps']=['Owner UI invites editor with exact email','Member UI accepts exact invitation','Accessible channel gains editor permissions','Replay denied; owner UI shows one member']
        case['mail_manual']='NOT_EXECUTED; local Pickup trigger only'
    suite.case(owner,'FULL-CHANNEL-INVITE-ACCEPT-REPLAY','U-CHANNEL.04','Invite, accept and replay boundary','Separate ordinary Member joins the actual channel exactly once',invite_accept,module='channel')
    for role in ['manager','editor','moderator','viewer']:
        def role_matrix(case,role=role):
            load();page.locator('.settings-tabs-nav .tab-btn').nth(2).click()
            suite.response(owner,'/channels/'+cid+'/members/'+member['identity']['userId']+'/role',lambda:page.locator('#role-'+member['identity']['userId']).select_option(role),method='PATCH')
            suite.go(member,'/studio?channelId='+cid,'app-studio-overview-page')
            member['page'].goto(member['origin']+'/studio/settings?channelId='+cid)
            if role=='manager':
                expect(member['page'].locator('app-studio-settings-page')).to_be_visible()
            else:
                expect(member['page']).not_to_have_url(re.compile('/studio/settings'))
                expect(member['page'].locator('app-studio-overview-page')).to_be_visible()
            assigned=suite.api(member,'get','/channels/'+cid).json();assert assigned['myRole']==role
            # Expected profile rights are independently defined by the role contract.
            allowed=role=='manager'
            suite.api(member,'patch','/channels/'+cid,data={'description':'Role check '+role},expected=200 if allowed else 403)
            suite.api(member,'delete','/channels/'+cid,expected=403)
            suite.api(member,'patch','/channels/'+cid+'/members/'+owner['identity']['userId']+'/role',data={'roleCode':'viewer'},expected=(400,403,409))
            suite.go(member,'/studio?channelId='+cid,'app-studio-overview-page')
            case['resource_ids']=[cid,member['identity']['userId']]
            case['steps']=['Owner UI changes role to '+role,'Member reload reads exact role','Only manager can edit channel profile','All collaborator roles cannot delete channel or demote owner']
        suite.case(member,'FULL-CHANNEL-ROLE-'+role.upper(),'U-CHANNEL.04','Collaborator permission '+role,'Role mutation persists and profile/delete/owner boundaries are enforced',role_matrix,module='channel')
    def remove(case):
        load();page.locator('.settings-tabs-nav .tab-btn').nth(2).click()
        row=page.locator('.member-row').filter(has_text=member['identity']['email'])
        app_confirm(page, lambda: row.locator('.btn-link-danger').click(), accept=False)
        assert any(m['userId']==member['identity']['userId'] for m in suite.api(owner,'get','/channels/'+cid+'/members').json())
        suite.response(owner,'/channels/'+cid+'/members/'+member['identity']['userId'],lambda:app_confirm(page, lambda: row.locator('.btn-link-danger').click(), accept=True),method='DELETE',status=(200,204))
        assert not any(c['channelId']==cid for c in suite.api(member,'get','/channels/accessible').json())
        suite.api(member,'patch','/channels/'+cid,data={'description':'Removed collaborator'},expected=403)
        case['steps']=['Remove → cancel preserves membership','Confirm actual DELETE → no accessible channel','Former collaborator API edit denied']
    suite.case(owner,'FULL-CHANNEL-MEMBER-REMOVE-CANCEL','U-CHANNEL.04','Remove collaborator with cancel','Only confirmed removal revokes access',remove,module='channel')
    def delete_secondary(case):
        p=target['page'];sid=secondary['channelId'];suite.go(target,'/channel/'+secondary['handle']+'/customize','app-channel-settings-page')
        p.locator('.danger-tab').click();p.locator('.danger-box .btn-danger').click()
        expect(p.locator('.modal-dialog')).to_be_visible();p.locator('.modal-dialog .confirm-cancel').click()
        assert suite.api(target,'get','/channels/me').json()['channelId']==sid
        p.locator('.danger-box .btn-danger').click();p.locator('.modal-dialog input').fill(secondary['name'])
        suite.response(target,'/channels/'+sid,lambda:p.locator('.modal-dialog .confirm-submit').click(),method='DELETE',status=(200,204))
        suite.api(target,'get','/channels/'+sid,expected=404)
        assert suite.api(owner,'get','/channels/me').json()['channelId']==cid
        case['resource_ids']=[sid,cid];case['steps']=['Secondary owner delete → cancel leaves channel','Exact name confirmation → actual delete','Deleted ID 404; main owner channel still exists']
    suite.case(target,'FULL-CHANNEL-DELETE-SECONDARY','U-CHANNEL.06','Delete only secondary channel','Cancel/confirm and isolation protect the main channel',delete_secondary,module='channel')
