"""Exercise the playlist library and account drawer using isolated browser API fixtures."""
import argparse
from datetime import datetime, timedelta, timezone
import json
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import expect, sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', default='http://127.0.0.1:4317')
    parser.add_argument('--browser-path')
    parser.add_argument('--artifacts', type=Path, required=True)
    args = parser.parse_args()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    root = Path(__file__).resolve().parents[2]
    pictures = list((root / 'assets/auth').glob('card_*.jpg'))
    assert pictures, 'Repository photo fixtures are required'
    expires = (datetime.now(timezone.utc) + timedelta(hours=2)).isoformat()
    user = {'userId':'viewer-one','username':'dalitu-viewer','email':'viewer@example.test',
            'displayName':'Duy Linh Nguyễn','emailVerified':True,'isAdmin':False}
    channel = {'channelId':'channel-one','name':'FanLiverpool','handle':'lynwa',
               'ownerUserId':user['userId'],'description':'','avatarUrl':'https://fixture.invalid/cover/0',
               'settings':'{}','status':'active','isOwner':True,'permissions':[]}
    names = ['Nhạc không lời','Piano','Lập trình Flutter','Khám phá thế giới',
             'Một chút bình yên','Những bài học hay','Giai điệu yêu thích','Âm nhạc khi làm việc']
    visibilities = ['private','private','private','public','private','public','unlisted','public']
    counts = [22,6,162,12,7,28,23,19]
    lists = [{'playlistId':f'list-{i}','userId':user['userId'],'name':name,'description':'',
              'coverUrl':f'https://fixture.invalid/cover/{i}' if i != 6 else None,
              'visibility':visibilities[i],'itemCount':counts[i],
              'updatedAt':f'2026-10-{26-i:02d}T09:00:00Z','previewItems':[]}
             for i,name in enumerate(names)]
    writes = []
    theme = 'light'

    def api(route):
        path = urlparse(route.request.url).path.split('/api/v1',1)[-1]
        method = route.request.method
        headers = {'Access-Control-Allow-Origin':args.base_url,'Access-Control-Allow-Credentials':'true',
                   'Access-Control-Allow-Headers':'*','Access-Control-Allow-Methods':'GET,POST,PATCH,DELETE,OPTIONS'}
        if method == 'OPTIONS':
            route.fulfill(status=204,headers=headers)
            return
        data = {'items':[],'total':0,'page':1,'pageSize':20}
        status = 200
        if path == '/auth/refresh':
            data = {'accessToken':'isolated-ui-fixture','expiresAt':expires,'user':user}
        elif path == '/auth/me': data = user
        elif path == '/account/profile': data = {**user,'avatarUrl':'https://fixture.invalid/cover/0','bio':''}
        elif path == '/account/settings': data = {'language':'vi','theme':theme}
        elif path == '/channels/me': data = channel
        elif path.startswith('/channels/handle/'): data = channel
        elif path == '/channels/accessible': data = [channel]
        elif path == '/playlists' or path.endswith('/playlists/mine'): data = lists
        elif path.startswith('/playlists/list-'):
            playlist_id = path.split('/')[2]
            item = next((item for item in lists if item['playlistId']==playlist_id),None)
            if method == 'DELETE':
                writes.append(('DELETE',playlist_id))
                lists[:] = [item for item in lists if item['playlistId']!=playlist_id]
                route.fulfill(status=204,headers=headers)
                return
            data = {**item,'createdAt':item['updatedAt'],'items':[]} if item else {}
        elif any(name in path for name in ['/categories','/invitations','/subscribed','/subscriptions','/policies']): data = []
        elif path == '/library/liked': data = {'items':[],'total':18}
        elif path == '/plans/my-plan': data = {'features':{},'subscription':None}
        elif path.endswith('/negotiate'): data = {'negotiateVersion':1,'connectionId':'fixture','connectionToken':'fixture','availableTransports':[]}
        route.fulfill(status=status,headers=headers,content_type='application/json',body=json.dumps(data))

    def dispatch(route):
        url = route.request.url
        if url.startswith('https://fixture.invalid/cover/'):
            i = int(url.rsplit('/',1)[-1])
            route.fulfill(content_type='image/jpeg',body=pictures[i % len(pictures)].read_bytes())
        elif '/api/v1/' in url: api(route)
        elif url.startswith(args.base_url): route.continue_()
        else: route.abort()

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True,**({'executable_path':args.browser_path} if args.browser_path else {}))
        context = browser.new_context(viewport={'width':1680,'height':1050},locale='vi-VN',reduced_motion='reduce')
        context.route('**/*',dispatch)
        context.add_init_script("localStorage.setItem('hutube_lang','vi'); localStorage.setItem('hutube_theme','light');")
        page = context.new_page()
        page_errors = []
        page.on('pageerror',lambda error:page_errors.append(str(error)))
        def load(path='/playlists'):
            page.goto(args.base_url+path)
            page.wait_for_load_state('networkidle')
            expect(page.locator('app-playlists-page .loading-state')).to_have_count(0)
        load()
        expect(page.locator('.playlist-card')).to_have_count(8)
        expect(page.locator('.playlist-card h3').first).to_have_text(names[0])
        columns = page.locator('.playlist-grid').evaluate('(el)=>getComputedStyle(el).gridTemplateColumns.split(" ").length')
        assert columns==4,columns
        page.screenshot(path=str(args.artifacts/'playlists-desktop.png'))
        page.get_by_role('button',name='Riêng tư',exact=True).click()
        expect(page.locator('.playlist-card')).to_have_count(4)
        page.get_by_role('button',name='Tất cả',exact=True).click()
        page.locator('#playlist-sort').select_option('videos')
        expect(page.locator('.playlist-card h3').first).to_have_text('Lập trình Flutter')
        page.locator('#playlist-sort').select_option('name')
        expect(page.locator('.playlist-card h3').first).to_have_text('Âm nhạc khi làm việc')
        page.locator('#playlist-query').fill('lap trinh')
        expect(page.locator('.playlist-card')).to_have_count(1)
        page.reload(); page.wait_for_load_state('networkidle')
        expect(page.locator('#playlist-query')).to_have_value('lap trinh')
        expect(page.locator('.playlist-card')).to_have_count(1)
        page.locator('#playlist-query').fill('khong-co-playlist-nao')
        expect(page.locator('.playlist-card')).to_have_count(0)
        expect(page.locator('.create-card')).to_be_visible()
        load()
        page.locator('.card-options summary').first.click()
        expect(page.locator('.card-options[open]')).to_have_count(1)
        page.keyboard.press('Escape')
        expect(page.locator('.card-options[open]')).to_have_count(0)
        page.locator('.card-options summary').first.click()
        page.locator('.card-options[open] a').click()
        expect(page.locator('.playlist-modal--edit')).to_be_visible()
        page.keyboard.press('Escape')
        expect(page.locator('.playlist-modal--edit')).to_have_count(0)
        assert 'edit=' not in page.url
        load()
        page.get_by_role('button',name='Tạo danh sách phát',exact=True).first.click()
        expect(page.locator('#playlist-name')).to_be_focused()
        page.locator('#playlist-name').fill('   ')
        expect(page.locator('.create-card .full-button')).to_be_disabled()
        page.locator('#playlist-name').fill('Danh sách mới')
        expect(page.locator('.create-card .full-button')).to_be_enabled()
        widths = []
        for width in [1280,768,680,600,430,390,360,320]:
            page.set_viewport_size({'width':width,'height':900})
            load()
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth'),('page overflow',width)
            if width in [768,390]:page.screenshot(path=str(args.artifacts/f'playlists-{width}.png'))
            page.locator('.top-avatar').click()
            drawer = page.locator('#account-drawer')
            expect(drawer).to_be_visible()
            page.wait_for_timeout(550)
            metrics = drawer.evaluate('(el)=>({width:el.getBoundingClientRect().width,left:el.getBoundingClientRect().left,right:el.getBoundingClientRect().right,scroll:el.scrollWidth,client:el.clientWidth})')
            if width<=680:
                assert abs(metrics['width']-width*.75)<1,(width,metrics)
            assert abs(metrics['right']-width)<1,(width,metrics)
            assert metrics['scroll']<=metrics['client']+1,('drawer overflow',width,metrics)
            widths.append({'viewport':width,**metrics})
            if width in [390,320]:page.screenshot(path=str(args.artifacts/f'drawer-{width}.png'))
            page.mouse.click(5,450)
            expect(drawer).to_have_count(0)
        theme = 'dark'
        page.set_viewport_size({'width':1680,'height':1050})
        load()
        expect(page.locator('html')).to_have_attribute('data-theme','dark')
        page.screenshot(path=str(args.artifacts/'playlists-dark.png'))
        load('/playlists?visibility=private&q=Piano&sort=name')
        expect(page.locator('.playlist-card')).to_have_count(1)
        page.locator('.card-options summary').click()
        page.locator('.card-options-menu button').click()
        expect(page.locator('.dalitu-confirm-dialog')).to_be_visible()
        page.locator('.confirm-cancel').click()
        expect(page.locator('.playlist-card')).to_have_count(1)
        assert not writes,writes
        if page.locator('.card-options[open]').count() == 0:
            page.locator('.card-options summary').click()
        page.locator('.card-options-menu button').click()
        page.locator('.confirm-submit').click()
        expect(page.locator('.playlist-card')).to_have_count(0)
        assert writes==[('DELETE','list-1')],writes
        load()
        expect(page.locator('.playlist-card')).to_have_count(7)
        assert not page_errors,page_errors
        result = {'checks':'playlist filters, sorting, URL persistence, empty search, edit menu, Escape, create validation, responsive grid, drawer sizing/dismissal, dark theme, delete cancellation/confirmation','drawer_widths':widths,'page_errors':page_errors,'writes':writes}
        (args.artifacts/'results.json').write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
        print(json.dumps(result,ensure_ascii=False))
        browser.close()


if __name__=='__main__':main()
