"""Exercise the real unsubscribe dialog with an isolated channel API fixture."""
import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
from urllib.parse import urlparse
from playwright.sync_api import expect, sync_playwright


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url',default='http://127.0.0.1:4317')
    parser.add_argument('--browser-path')
    parser.add_argument('--artifacts',type=Path,required=True)
    args=parser.parse_args();args.artifacts.mkdir(parents=True,exist_ok=True)
    user={'userId':'viewer','username':'viewer','email':'viewer@example.test','displayName':'Viewer','emailVerified':True,'isAdmin':False}
    channel={'channelId':'creator','ownerUserId':'other','name':'Kênh âm nhạc','handle':'creator',
             'description':'','avatarUrl':None,'bannerUrl':None,'contactEmail':None,'watermarkUrl':None,
             'settings':'{}','status':'active','subscriberCount':6,'videoCount':0,'isOwner':False,'permissions':[]}
    subscribed=True
    writes=[]
    errors=[]
    expires=(datetime.now(timezone.utc)+timedelta(hours=1)).isoformat()
    def route(request):
        nonlocal subscribed
        url=request.request.url
        if '/api/v1/' not in url:
            request.continue_() if url.startswith(args.base_url) else request.abort()
            return
        path=urlparse(url).path.split('/api/v1/',1)[1];method=request.request.method
        headers={'Access-Control-Allow-Origin':args.base_url,'Access-Control-Allow-Credentials':'true',
                 'Access-Control-Allow-Headers':'*','Access-Control-Allow-Methods':'GET,POST,DELETE,OPTIONS'}
        if method=='OPTIONS':request.fulfill(status=204,headers=headers);return
        data,status={'items':[],'total':0,'page':1,'pageSize':20},200
        if path=='auth/refresh':data={'accessToken':'fixture','expiresAt':expires,'user':user}
        elif path=='auth/me':data=user
        elif path=='account/profile':data={**user,'avatarUrl':None}
        elif path=='account/settings':data={'language':'vi','theme':'light'}
        elif path=='channels/me':data,status={'code':'CHANNEL_NOT_FOUND'},404
        elif path=='channels/accessible':data=[]
        elif path.startswith('channels/handle/'):data=channel
        elif path=='channels/creator/subscribe-status':data={'isSubscribed':subscribed,'status':'active' if subscribed else 'inactive','notificationsEnabled':subscribed}
        elif path=='channels/creator/subscribe' and method in ['POST','DELETE']:
            subscribed=method=='POST';writes.append(method)
            data={'isSubscribed':subscribed,'status':'active' if subscribed else 'inactive','notificationsEnabled':subscribed}
            if method=='DELETE':request.fulfill(status=204,headers=headers);return
        elif path.startswith('playlists') or any(name in path for name in ['categories','invitations','policies','/live','/featured']):data=[]
        elif path.endswith('/negotiate'):data={'negotiateVersion':1,'connectionId':'fixture','connectionToken':'fixture','availableTransports':[]}
        request.fulfill(status=status,headers=headers,content_type='application/json',body=json.dumps(data))
    with sync_playwright() as p:
        browser=p.chromium.launch(headless=True,**({'executable_path':args.browser_path} if args.browser_path else {}))
        context=browser.new_context(viewport={'width':1440,'height':1000},locale='vi-VN')
        context.route('**/*',route)
        context.add_init_script("localStorage.setItem('hutube_lang','vi');localStorage.setItem('hutube_theme','light');")
        page=context.new_page();page.on('pageerror',lambda e:errors.append(str(e)))
        console_errors=[]
        page.on('console',lambda msg:console_errors.append(msg.text) if msg.type=='error' else None)
        page.goto(args.base_url+'/channel/creator');page.wait_for_load_state('networkidle')
        button=page.locator('.btn-subscribe')
        expect(button).to_be_enabled()
        expect(button).to_have_class(__import__('re').compile('is-subscribed'))
        button.click();expect(page.locator('dialog:modal')).to_be_visible()
        assert writes==[]
        page.screenshot(path=str(args.artifacts/'unsubscribe-desktop.png'))
        page.locator('.confirm-cancel').click()
        expect(button).to_have_class(__import__('re').compile('is-subscribed'));assert writes==[]
        button.click();page.locator('.confirm-submit').click()
        expect(button).not_to_have_class(__import__('re').compile('is-subscribed'));assert writes==['DELETE']
        button.click()
        expect(button).to_have_class(__import__('re').compile('is-subscribed'));assert writes==['DELETE','POST']
        expect(page.locator('dialog:modal')).to_have_count(0)
        page.set_viewport_size({'width':390,'height':844})
        button.click();expect(page.locator('dialog:modal')).to_be_visible()
        page.screenshot(path=str(args.artifacts/'unsubscribe-mobile.png'))
        assert page.locator('dialog:modal').evaluate('el=>el.scrollWidth<=el.clientWidth')
        page.keyboard.press('Escape');assert writes==['DELETE','POST']
        assert not errors,errors
        assert not [message for message in console_errors if message.startswith('ERROR')],console_errors
        result={'checks':'cancel keeps subscription, confirm sends one DELETE, subscribe sends POST without confirmation, mobile dialog, Escape','writes':writes,'page_errors':errors}
        (args.artifacts/'results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(result,ensure_ascii=False));browser.close()


if __name__=='__main__':main()
