from urllib.parse import urlsplit
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.live_suite import PrerequisiteMissing
from tests.full_functional import register
from support.local_db import LocalDb
import json

def run(suite,config,actors):
    snapshot_module(suite,__file__);owner,member=actors['owner'],actors['member'];p=owner['page']
    key='shell_realtime'
    suite.credentials[key]={'email':'qc.shell.realtime.'+suite.run_id.lower()+'@example.test',
        'username':'qc_shell_rt_'+suite.run_id[9:15],'password':'QCShellRealtime2026!'}
    register(suite,config,key,LocalDb(config))
    receiver=suite.actor('shell-realtime-receiver','user',key);q=receiver['page'];frames=[];invited={}
    def websocket(ws):
        if urlsplit(ws.url).path!='/hubs/notifications':return
        def received(payload):
            if not isinstance(payload,str):return
            for part in payload.split('\x1e'):
                try:
                    message=json.loads(part)
                    if message.get('target') in ('NotificationReceived','InvitationReceived','UnreadCountChanged'):
                        frames.append(message)
                except (ValueError,TypeError):pass
        ws.on('framereceived',received)
    q.on('websocket',websocket)
    def realtime(entry):
        cid=suite.fixtures['channel']['channelId'];name=suite.fixtures['channel']['name']
        suite.go(receiver,'/home','app-home-page','/notifications');q.wait_for_timeout(1500)
        q.locator('.notif-btn').click();panel=q.locator('app-notification-panel .notification-panel');expect(panel).to_be_visible()
        initial_url=q.url
        invited.update(suite.api(owner,'post','/channels/'+cid+'/members/invite',data={
            'email':suite.credentials[key]['email'],'roleCode':'viewer'},expected=(200,201)).json())
        expect(panel.locator('.notification-item').filter(has_text=name)).to_have_count(1,timeout=15000)
        assert q.url==initial_url
        q.wait_for_timeout(3500)
        matching=[m for m in frames if m.get('target')=='NotificationReceived' and
                  any(a.get('type')=='channel_invitation' and name in a.get('title','') for a in m.get('arguments',[]) if isinstance(a,dict))]
        assert matching,'UI delivery alone cannot certify SignalR: no actual matching hub frame received'
        notification=matching[0]['arguments'][0]
        stored=suite.api(receiver,'get','/notifications').json()
        assert sum(i['notificationId']==notification['notificationId'] for i in stored['items'])==1
        expect(panel.locator('.notification-item').filter(has_text=name)).to_have_count(1)
        entry['resource_ids']=[invited['channelInvitationId'],notification['notificationId']]
        entry['hub_event_targets']=[m['target'] for m in frames]
        entry['steps']=['Fresh independently verified recipient on Home with notification panel already open',
            'Owner creates real viewer invitation through application API','Actual SignalR NotificationReceived frame matches persisted notification ID',
            'Existing panel updates without navigation/reload','Polling interval passes; same item remains unique, no duplicate delivery rows']
    try:case(suite,receiver,'SHELL-REALTIME-SIGNALR-INVITATION','X-SHELL','Real SignalR invitation updates an open recipient panel once',realtime,'shell')
    finally:
        q.remove_listener('websocket',websocket)
        if invited:suite.api(owner,'delete','/channels/'+suite.fixtures['channel']['channelId']+'/invitations/'+invited['channelInvitationId'],expected=(200,204))
        suite.release_actor(receiver)
    def notifications(entry):
        data=suite.go(owner,'/home','app-home-page','/notifications')
        if not data['items']:raise PrerequisiteMissing('Actual moderation notification fixture required')
        chosen=next((i for i in data['items'] if not i['isRead']),data['items'][0]);nid=chosen['notificationId']
        p.locator('.notif-btn').click();panel=p.locator('app-notification-panel .notification-panel');expect(panel).to_be_visible()
        row=panel.locator('.notification-item').nth(data['items'].index(chosen))
        expect(row.locator('strong')).to_have_text(chosen['title']);expect(row.locator('small')).to_have_text(chosen['content'])
        suite.api(member,'patch','/notifications/'+nid+'/read',expected=(403,404))
        read_path='/api/v1/notifications/'+nid+'/read'
        if chosen['isRead']:
            before=sum(e['actor']=='owner' and e['method']=='PATCH' and e['path']==read_path for e in suite.report['http_statuses'])
            row.click();expect(panel).to_have_count(0)
            assert before==sum(e['actor']=='owner' and e['method']=='PATCH' and e['path']==read_path for e in suite.report['http_statuses'])
            entry['notification_branch']='Already-read item navigates without redundant PATCH'
        else:
            suite.response(owner,'/notifications/'+nid+'/read',lambda:row.click(),method='PATCH',status=204)
            entry['notification_branch']='Unread item is persisted as read through actual PATCH 204'
        expect(panel).to_have_count(0)
        assert next(i for i in suite.api(owner,'get','/notifications').json()['items'] if i['notificationId']==nid)['isRead']
        if chosen['actionUrl']:expect(p).to_have_url(__import__('re').compile(__import__('re').escape(urlsplit(chosen['actionUrl']).path)))
        suite.go(owner,'/home','app-home-page');p.locator('.notif-btn').click()
        suite.response(owner,'/notifications/read-all',lambda:p.locator('app-notification-panel header button').click(),method='POST',status=204)
        assert suite.api(owner,'get','/notifications').json()['unreadCount']==0
        p.reload();p.locator('.notif-btn').click();expect(p.locator('.notification-item.unread')).to_have_count(0)
        entry['resource_ids']=[nid];entry['steps']=['Real moderation notifications displayed in owner panel','Foreign Member cannot mark owner notification',entry['notification_branch']+'; matching target route','Read-all actual POST → zero unread','Reload retains read state']
    case(suite,owner,'SHELL-NOTIFICATION-READ-TARGET-ALL','X-SHELL','Notification ownership, read state and targets',notifications,'shell')
    def keyboard(entry):
        suite.go(member,'/home','app-home-page');q=member['page'];q.keyboard.press('Control+k');expect(q.locator('input[type=search]').first).to_be_focused()
        q.locator('.top-avatar').click();expect(q.locator('.account-drawer')).to_be_visible();q.keyboard.press('Escape');expect(q.locator('.account-drawer')).to_have_count(0)
        suite.go(member,'/account','app-account-page')
        link=q.get_by_role('link',name='Bỏ qua để đến nội dung chính');link.focus();expect(link).to_be_focused()
        destination=link.evaluate('(e)=>e.href')
        assert urlsplit(destination).path==urlsplit(q.url).path,'Skip-to-content link resolves to '+urlsplit(destination).path+' instead of the current account route'
        q.keyboard.press('Enter');q.wait_for_function('()=>location.hash==="#main-content"')
        q.keyboard.press('Tab');q.wait_for_function('()=>!!document.activeElement?.closest("#main-content")')
        entry['steps']=['Ctrl+K focuses actual header search','Avatar opens drawer; Escape dismisses','Keyboard skip link targets main-content']
    case(suite,member,'SHELL-KEYBOARD-FOCUS-DISMISS','X-SHELL','Keyboard shortcuts and dismissal reach correct targets',keyboard,'shell')
    from flows.expanded.performance_probe import run as performance_probe
    performance_probe(suite,config,actors)
