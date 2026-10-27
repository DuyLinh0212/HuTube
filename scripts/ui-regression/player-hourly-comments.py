"""Exercise player menu, embedded playback, hourly charts and comment ownership with isolated APIs."""
import argparse
import functools
import json
import sys
import threading
from datetime import datetime, timedelta, timezone
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

from playwright.sync_api import expect, sync_playwright

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'frontend' / 'e2e_testing'))
from support.comment_actions import click_comment_delete, click_comment_edit, comment_menu
from support.ui_confirmation import app_confirm

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--root', type=Path, required=True)
parser.add_argument('--video', type=Path, required=True)
parser.add_argument('--artifacts', type=Path, required=True)
parser.add_argument('--browser-path')
args = parser.parse_args()
args.artifacts.mkdir(parents=True, exist_ok=True)
now = datetime.now(timezone.utc)
video_id = '11111111-1111-4111-8111-111111111111'
channel_id = '22222222-2222-4222-8222-222222222222'
user = dict(userId='viewer', username='viewer', email='viewer@example.test', displayName='Viewer', emailVerified=True, isAdmin=False)
channel = dict(channelId=channel_id, ownerUserId='viewer', name='Test', handle='test', description='', settings='{}',
               avatarUrl=None, bannerUrl=None, subscriberCount=1, videoCount=1, isOwner=True,
               permissions=['analytics.view', 'video.view', 'channel.view_dashboard'], status='active', createdAt=now.isoformat())
video = dict(videoId=video_id, channelId=channel_id, channelName='Test', channelHandle='test', title='Video test',
             description='', videoUrl='', thumbnailUrl=None, fileSize=0, duration=60, visibility='public',
             status='published', moderationStatus='approved', languageCode='vi', createdAt=now.isoformat(),
             publishedAt=now.isoformat(), ageRestricted=False, categoryId=None, tags=[], chapters=[],
             stats=dict(views=3, likes=1, dislikes=0, comments=2, watchSeconds=40, averageRating=None, ratingCount=0, shares=0),
             viewerState=None)

class Handler(SimpleHTTPRequestHandler):
    def do_GET(self):
        if not Path(self.translate_path(self.path)).is_file() and '.' not in urlparse(self.path).path.split('/')[-1]:
            self.path = '/index.html'
        super().do_GET()
    def log_message(self, *_): pass

server = ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(args.root.resolve())))
base = f'http://127.0.0.1:{server.server_port}'
threading.Thread(target=server.serve_forever, daemon=True).start()
media = args.video.read_bytes()
deleted, errors, requests = [], [], []
state = {'visibility': 'public'}

def comment(identifier, user_id):
    return dict(commentId=identifier, videoId=video_id, userId=user_id, displayName=user_id,
                parentCommentId=None, content=f'Comment {identifier}', status='visible',
                createdAt=now.isoformat(), updatedAt=now.isoformat(), likes=0, dislikes=0, myReaction=None, replyCount=0)

def api(route):
    request = route.request
    parsed = urlparse(request.url)
    if parsed.path == '/fixture.mp4':
        route.fulfill(status=200, content_type='video/mp4', body=media)
        return
    if '/api/v1/' not in parsed.path:
        if request.url.startswith(base): route.continue_()
        else: route.abort()
        return
    cors = {'Access-Control-Allow-Origin': base, 'Access-Control-Allow-Credentials': 'true',
            'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS'}
    if request.method == 'OPTIONS': route.fulfill(status=204, headers=cors); return
    path = parsed.path.split('/api/v1', 1)[1]
    data, status = dict(items=[], page=1, pageSize=20, total=0), 200
    if path == '/auth/refresh': data = dict(accessToken='fixture', expiresAt=(now + timedelta(hours=1)).isoformat(), user=user)
    elif path == '/auth/me': data = user
    elif path == '/auth/session/player-preferences': data = dict(volume=1, muted=False)
    elif path == '/plans/my-plan': data = dict(features={}, subscription=None)
    elif path == '/channels/accessible': data = [channel]
    elif path == '/channels/me': data = channel
    elif path == f'/videos/{video_id}': data = video
    elif path == f'/videos/{video_id}/playback':
        data = dict(videoId=video_id, title=video['title'], visibility=state['visibility'], duration=60, resumeAtSeconds=0, progress=0,
                    renditions=[dict(quality='720p', width=1280, height=720, fileSize=len(media), url=base+'/fixture.mp4')])
    elif path == f'/videos/{video_id}/comments':
        items = [comment('own', 'viewer'), comment('other', 'someone-else')]
        data = dict(items=[item for item in items if item['commentId'] not in deleted], page=1, pageSize=20, total=2-len(deleted))
    elif path == '/comments/own' and request.method == 'DELETE': deleted.append('own'); data = {}
    elif path.endswith('/metrics'): data = [video]
    elif path.endswith('/hourly-analytics'):
        requests.append(parse_qs(parsed.query))
        hours = [dict(hour=i, views=2 if i == 13 else 0, likes=1 if i == 13 else 0,
                      watchSeconds=60 if i == 13 else 0, subscribers=1 if i == 13 else 0) for i in range(24)]
        data = dict(hours=hours, utcOffsetMinutes=420, **{'from': now.isoformat(), 'to':now.isoformat()})
    elif path.endswith('/subscribe-status'): data = dict(status='inactive', notificationsEnabled=False)
    elif path.startswith('/channels/'): data = channel
    elif path in ['/categories', '/violation-types', '/subscriptions', '/channels/invitations']: data = []
    route.fulfill(status=status, headers=cors, content_type='application/json', body=json.dumps(data))

try:
    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, **({'executable_path': args.browser_path} if args.browser_path else {}))
        for width in [1440, 440]:
            context = browser.new_context(viewport=dict(width=width, height=900), locale='vi-VN',
                                          permissions=['clipboard-read', 'clipboard-write'])
            context.add_init_script("localStorage.setItem('hutube_lang','vi'); localStorage.setItem('hutube_theme','light'); HTMLMediaElement.prototype.play = () => Promise.resolve()")
            context.route('**/*', api)
            page = context.new_page()
            page.on('pageerror', lambda error: errors.append(str(error)))
            page.goto(base + '/watch/' + video_id)
            player = page.locator('video.video-player')
            expect(player).to_be_visible()
            page.wait_for_function("document.querySelector('video.video-player').readyState >= 1")
            stage = page.locator('.player-stage')
            stage.click(button='right', position={'x': 30, 'y': 30})
            menu = page.locator('app-player-context-menu .menu')
            expect(menu).to_be_visible()
            expect(menu.get_by_text('Sao chép thông tin gỡ lỗi')).to_have_count(0)
            menu.get_by_text('Vòng lặp').click()
            assert player.evaluate('(video) => video.loop')
            stage.click(button='right', position={'x': 30, 'y': 30})
            menu.get_by_text('Thống kê chi tiết').click()
            expect(page.locator('app-player-context-menu .stats')).to_contain_text(video_id)
            page.locator('.stats-close').click()
            player.evaluate('(video) => { video.currentTime = 1.5; }')
            page.wait_for_function("document.querySelector('video.video-player').currentTime >= 1")
            stage.click(button='right', position={'x': 30, 'y': 30})
            menu.get_by_text('Sao chép URL tại thời điểm hiện tại').click()
            copied = page.evaluate('navigator.clipboard.readText()')
            assert copied == base + '/watch/' + video_id + '?t=1', copied
            stage.click(button='right', position={'x': 30, 'y': 30})
            menu.get_by_text('Sao chép mã nhúng').click()
            copied = page.evaluate('navigator.clipboard.readText()')
            assert '/embed/' + video_id in copied and '<iframe' in copied, copied
            page.goto(base + '/watch/' + video_id + '?t=1')
            page.wait_for_function("document.querySelector('video.video-player')?.currentTime >= 0.9")
            own, other = page.locator('[data-comment-id="own"]'), page.locator('[data-comment-id="other"]')
            expect(own.locator('.comment-menu summary')).to_be_visible()
            expect(other.locator('.comment-menu')).to_have_count(0)
            click_comment_edit(own)
            expect(own.locator('.comment-edit-form')).to_be_visible()
            own.locator('.comment-edit-form button').last.click()
            expect(comment_menu(own).locator('summary')).to_be_visible()
            if width == 1440:
                app_confirm(page, lambda: click_comment_delete(own), accept=False)
                expect(own).to_have_count(1)
                app_confirm(page, lambda: click_comment_delete(own), accept=True)
                expect(own).to_have_count(0)
                assert deleted == ['own']
            page.goto(base + '/embed/' + video_id)
            expect(page.locator('video[controls]')).to_be_visible()
            expect(page.locator('.app-shell')).to_have_count(0)
            assert page.locator('video[controls]').evaluate('(video) => video.disablePictureInPicture')
            state['visibility'] = 'private'
            page.reload()
            page.wait_for_load_state('networkidle')
            expect(page.locator('video[controls]')).to_have_count(0)
            state['visibility'] = 'public'
            page.goto(base + '/studio/analytics')
            expect(page.locator('app-hourly-analytics')).to_contain_text('Hoạt động theo khung giờ')
            expect(page.locator('app-hourly-analytics .bars')).to_have_count(4)
            expect(page.locator('app-hourly-analytics .bars').first.locator('[role=listitem]')).to_have_count(24)
            with page.expect_response(lambda response: 'hourly-analytics' in response.url and f'videoId={video_id}' in response.url):
                page.locator('.video-picker select').select_option(video_id)
            with page.expect_response(lambda response: 'hourly-analytics' in response.url and 'days=30' in response.url):
                page.locator('app-hourly-analytics select').select_option('30')
            page.wait_for_function("document.querySelector('app-hourly-analytics .bars')")
            assert any(q.get('days') == ['30'] and q.get('videoId') == [video_id] for q in requests), requests
            page.screenshot(path=str(args.artifacts / f'hourly-{width}.png'))
            assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
            context.close()
            deleted.clear()
        assert not errors, errors
        browser.close()
    print('PASS: player context menu, stats, clipboard, embed, own-comment deletion and hourly charts on desktop/mobile widths')
finally:
    server.shutdown()
    server.server_close()
