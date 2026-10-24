"""Browser regression for PiP, Explore dragging and history time labels.

Run against a local development server. All API calls use isolated fixtures.
Requires Playwright, Chromium (or --browser-path) and ffmpeg.
"""
import argparse
import json
import re
import shutil
import subprocess
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import urlparse

from playwright.sync_api import expect, sync_playwright


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url', default='http://127.0.0.1:4305')
    parser.add_argument('--browser-path')
    parser.add_argument('--artifacts', type=Path, default=Path(tempfile.gettempdir()) / 'dalitu-player-regression')
    args = parser.parse_args()
    args.artifacts.mkdir(parents=True, exist_ok=True)
    media = args.artifacts / 'sample.mp4'
    subprocess.run([shutil.which('ffmpeg') or 'ffmpeg', '-y', '-loglevel', 'error',
                    '-f', 'lavfi', '-i', 'testsrc=size=640x360:rate=24', '-t', '15',
                    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', str(media)], check=True)
    media_bytes = media.read_bytes()
    video_id = '11111111-1111-4111-8111-111111111111'
    channel = {'channelId': 'channel-one', 'name': 'Regression channel', 'handle': 'regression',
               'subscriberCount': 1, 'videoCount': 1, 'avatarUrl': None, 'isOwner': False}
    card = {'videoId': video_id, 'channelId': channel['channelId'], 'channelName': channel['name'],
            'channelHandle': channel['handle'], 'title': 'Regression video', 'thumbnailUrl': None,
            'duration': 4000, 'visibility': 'public', 'publishedAt': None, 'views': 12}
    categories = [{'categoryId': f'category-{i}', 'slug': f'topic-{i}', 'name': f'Topic {i:02d}'} for i in range(20)]
    expires = (datetime.now(timezone.utc) + timedelta(hours=1)).isoformat()
    session = {'accessToken': 'regression-token', 'expiresAt': expires,
               'user': {'userId': 'user-one', 'username': 'regression', 'email': 'test@example.test',
                        'displayName': 'Regression user', 'emailVerified': True, 'isAdmin': False}}
    history = [{**card, 'videoId': f'history-{seconds}', 'title': f'Watched {seconds}',
                'watchedSeconds': seconds, 'progress': 20, 'activityAt': datetime.now(timezone.utc).isoformat()}
               for seconds in [59, 60, 61, 3599, 3600, 3660]]

    def api(route):
        cors = {'Access-Control-Allow-Origin': args.base_url, 'Access-Control-Allow-Credentials': 'true',
                'Access-Control-Allow-Headers': route.request.headers.get('access-control-request-headers', '*'),
                'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS'}
        if route.request.method == 'OPTIONS':
            route.fulfill(status=204, headers=cors)
            return
        path = urlparse(route.request.url).path.split('/api/v1', 1)[-1]
        if path == '/test-media.mp4':
            match = re.match(r'bytes=(\d+)-(\d*)', route.request.headers.get('range', ''))
            start = int(match[1]) if match else 0
            end = min(int(match[2]) if match and match[2] else len(media_bytes) - 1, len(media_bytes) - 1)
            headers = {'Accept-Ranges': 'bytes', 'Cache-Control': 'no-store', 'Access-Control-Allow-Origin': '*'}
            if match:
                headers['Content-Range'] = f'bytes {start}-{end}/{len(media_bytes)}'
            route.fulfill(status=206 if match else 200, content_type='video/mp4', headers=headers, body=media_bytes[start:end + 1])
            return
        data = {'items': [], 'page': 1, 'pageSize': 20, 'total': 0}
        if path == '/auth/refresh':
            data = session
        elif path == '/plans/my-plan':
            data = {'features': {'pip': True, 'background_play': True}, 'subscription': None}
        elif path == '/categories':
            data = categories
        elif path == '/feed/explore-hub':
            data = {'topVideos': [card], 'rankings': [], 'creators': [], 'trending': [card]}
        elif path == '/library/history':
            data = {'items': history, 'page': 1, 'pageSize': 20, 'total': len(history)}
        elif path == f'/videos/{video_id}':
            data = {**card, 'description': 'Video regression', 'videoUrl': '', 'fileSize': 0,
                    'status': 'published', 'moderationStatus': 'approved', 'categoryId': None,
                    'languageCode': 'vi', 'ageRestricted': False, 'createdAt': expires,
                    'tags': [], 'chapters': [], 'stats': {'views': 12, 'likes': 0, 'dislikes': 0,
                    'comments': 0, 'averageRating': None, 'ratingCount': 0, 'shares': 0}, 'viewerState': None}
        elif path == f'/videos/{video_id}/playback':
            data = {'videoId': video_id, 'title': card['title'], 'visibility': 'public', 'duration': 15,
                    'resumeAtSeconds': 0, 'progress': 0, 'renditions': [{'quality': '720p', 'width': 640,
                    'height': 360, 'fileSize': len(media_bytes), 'url': 'https://api.dalitu.app/api/v1/test-media.mp4'}]}
        elif path.startswith('/channels/'):
            data = {'status': 'inactive', 'notificationsEnabled': False} if path.endswith('/subscribe-status') else channel
        elif path in ['/violation-types', '/notifications', '/subscriptions']:
            data = []
        route.fulfill(status=200, content_type='application/json', headers=cors, body=json.dumps(data))

    with sync_playwright() as playwright:
        browser = playwright.chromium.launch(headless=True, executable_path=args.browser_path,
                    args=['--autoplay-policy=no-user-gesture-required'])
        context = browser.new_context(viewport={'width': 1440, 'height': 1000}, locale='vi-VN')
        context.route('**/api/v1/**', api)
        page = context.new_page()
        page.goto(args.base_url + '/explore')
        page.wait_for_load_state('networkidle')
        track = page.locator('.category-tabs-track')
        expect(track.locator('button')).to_have_count(21)
        assert page.locator('.view-all-link').count() == 0
        box = track.bounding_box()
        initial_tab = track.locator('.is-active').inner_text()
        page.mouse.move(box['x'] + box['width'] - 40, box['y'] + box['height'] / 2)
        page.mouse.down()
        page.mouse.move(box['x'] + 40, box['y'] + box['height'] / 2, steps=12)
        page.mouse.up()
        assert track.evaluate('(element) => element.scrollLeft') > 100
        assert track.locator('.is-active').inner_text() == initial_tab
        track.get_by_role('button', name='Topic 19', exact=True).click()
        expect(track.get_by_role('button', name='Topic 19', exact=True)).to_have_class(re.compile('is-active'))
        page.screenshot(path=str(args.artifacts / 'explore-desktop.png'))

        page.goto(args.base_url + '/history')
        page.wait_for_load_state('networkidle')
        for seconds, label in [(59, '0:59'), (60, '1:00'), (61, '1:01'), (3599, '59:59'), (3600, '1:00:00'), (3660, '1:01:00')]:
            row = page.locator('.library-card').filter(has=page.get_by_role('heading', name=f'Watched {seconds}', exact=True))
            expect(row.locator('.library-meta').get_by_text(label, exact=True)).to_be_visible()
        page.screenshot(path=str(args.artifacts / 'history-desktop.png'))

        page.goto(args.base_url + '/watch/' + video_id)
        page.wait_for_load_state('networkidle')
        player = page.locator('video.video-player')
        expect(player).to_be_visible()
        page.wait_for_function('document.querySelector("video.video-player").readyState >= 2')
        player.evaluate('(video) => video.play()')
        page.locator('.player-stage').hover()
        page.locator('.player-pip-button').click()
        expect(page.locator('.player-pip-placeholder')).to_be_visible()
        assert player.evaluate('(video) => video.paused')
        assert page.evaluate('document.pictureInPictureElement === document.querySelector(".global-picture-in-picture-video")')
        page.wait_for_function('!document.querySelector(".global-picture-in-picture-video").paused')
        assert page.locator('.player-controls').count() == 0
        page.keyboard.press('Space')
        assert player.evaluate('(video) => video.paused')
        page.locator('.player-stage').scroll_into_view_if_needed()
        page.screenshot(path=str(args.artifacts / 'pip-placeholder.png'))
        page.locator('.player-pip-placeholder button').click()
        expect(page.locator('.player-pip-placeholder')).to_have_count(0)
        page.wait_for_function('!document.querySelector("video.video-player").paused')
        assert page.evaluate('document.pictureInPictureElement === null')
        page.set_viewport_size({'width': 375, 'height': 812})
        page.goto(args.base_url + '/explore')
        page.wait_for_load_state('networkidle')
        assert page.evaluate('document.documentElement.scrollWidth <= innerWidth')
        page.screenshot(path=str(args.artifacts / 'explore-narrow.png'))
        context.close()
        browser.close()
    print('PASS: native PiP on first click, exclusive playback/return, category drag/click, history duration and narrow layout')


if __name__ == '__main__':
    main()
