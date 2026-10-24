"""Use Watch playlist picker, then verify ownership and removal in Playlist UI."""
from support.ui_confirmation import app_confirm
from playwright.sync_api import expect


def run(suite, owner, member):
    playlist_id,video_id=suite.state.get('playlist_id'),suite.state.get('video_id')
    if not playlist_id or not video_id:
        suite.blocked(owner,'U-PLAYLIST-ITEM-01','Thêm video vào playlist','Missing playlist/video checkpoint')
        return
    path='/playlists/'+playlist_id
    page=owner['page']

    def add():
        existing=suite.api(owner,'get',path)
        assert existing.status==200
        suite.go(owner,'/watch/'+video_id,'app-watch-page')
        expect(page.locator('.playlist-action-button')).to_be_visible()
        page.locator('.playlist-action-button').click()
        target=page.locator('.playlist-picker__row').filter(has_text=existing.json()['name'])
        expect(target).to_be_visible()
        if any(item['videoId']==video_id for item in existing.json()['items']):
            # Read reused resource via the detail page; no duplicate mutation.
            suite.go(owner,'/playlists/'+playlist_id,'app-playlists-page')
            expect(page.locator('.video-row')).to_have_count(1)
            return 'reused'
        with page.expect_response(lambda response:response.request.method=='POST' and response.url.endswith(path+'/videos')) as pending:
            target.click()
        assert pending.value.status in (200,201)
        expect(page.locator('#playlist-picker-dialog')).to_have_count(0)
        page.locator('.playlist-action-button').click()
        expect(target).to_be_disabled()
        page.locator('#playlist-picker-dialog .share-popover__close').click()
        stored=suite.api(owner,'get',path).json()
        assert sum(item['videoId']==video_id for item in stored['items'])==1
        suite.go(owner,'/playlists/'+playlist_id,'app-playlists-page')
        row=page.locator('.video-row').filter(has=page.locator('a[href="/watch/'+video_id+'"]'))
        expect(row).to_have_count(1)
        ids=[item['videoId'] for item in stored['items']];index=ids.index(video_id)
        up=row.locator('.row-actions button').nth(0);down=row.locator('.row-actions button').nth(1)
        if index==0:expect(up).to_be_disabled()
        else:expect(up).to_be_enabled()
        if index==len(ids)-1:expect(down).to_be_disabled()
        else:expect(down).to_be_enabled()
    suite.case(owner,'U-PLAYLIST-ITEM-01','Thêm video qua Watch picker, reload playlist',add,
               expected='Video ID chỉ xuất hiện một lần; nút thêm disabled; nút reorder đúng vị trí trong playlist một hoặc nhiều item')

    def denied():
        response=suite.api(member,'post',path+'/videos',data={'videoId':video_id})
        assert response.status in (403,404)
        assert sum(item['videoId']==video_id for item in suite.api(owner,'get',path).json()['items'])==1
    suite.case(member,'X-PLAYLIST-EDIT-01','Member không thêm video vào playlist owner',denied,
               module='access',expected='403/404; playlist không thay đổi')

    def remove():
        before=suite.api(owner,'get',path).json()['items']
        remaining=[item['videoId'] for item in before if item['videoId']!=video_id]
        suite.go(owner,'/playlists/'+playlist_id,'app-playlists-page')
        row=page.locator('.video-row').filter(has=page.locator('a[href="/watch/'+video_id+'"]'))
        app_confirm(page, lambda: row.locator('.remove-button').click(), accept=False)
        expect(row).to_have_count(1)
        with page.expect_response(lambda response:response.request.method=='DELETE' and response.url.endswith(path+'/videos/'+video_id)) as pending:
            app_confirm(page, lambda: row.locator('.remove-button').click(), accept=True)
        assert pending.value.status in (200,204)
        suite.go(owner,'/playlists/'+playlist_id,'app-playlists-page')
        if remaining:
            expect(page.locator('.video-row')).to_have_count(len(remaining))
        else:expect(page.locator('.empty-items')).to_be_visible()
        assert [item['videoId'] for item in suite.api(owner,'get',path).json()['items']]==remaining
        assert suite.api(owner,'get','/videos/'+video_id).status==200
    suite.case(owner,'U-PLAYLIST-REMOVE-01','Cancel rồi remove item; giữ video nguồn',remove,
               expected='Cancel giữ item; DELETE chỉ xóa liên kết; video nguồn vẫn tồn tại')
