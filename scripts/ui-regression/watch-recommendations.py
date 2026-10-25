"""Verify watch recommendations against isolated APIs, including the rare first-tag regression."""
import argparse
import importlib.util
import json
from datetime import datetime, timedelta, timezone
from pathlib import Path
from urllib.parse import parse_qs, urlsplit
from playwright.sync_api import expect, sync_playwright

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, required=True)
parser.add_argument('--artifacts', type=Path, required=True)
args = parser.parse_args()
args.artifacts.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location('chunk_server', Path(__file__).with_name('admin-chunk-recovery.py'))
server = importlib.util.module_from_spec(spec)
spec.loader.exec_module(server)
vid = 'a9a387b3-84c2-48f2-8936-8e4fdcfc4868'
now = datetime.now(timezone.utc)
user = dict(userId='viewer', username='viewer', displayName='Viewer', email='viewer@example.test', emailVerified=True, isAdmin=False)
video = dict(videoId=vid, channelId='creator', channelName='Music', channelHandle='music', title='OST china', description='', videoUrl='', thumbnailUrl=None, duration=39, visibility='public', status='published', moderationStatus='approved', languageCode='vi', createdAt=now.isoformat(), publishedAt=now.isoformat(), ageRestricted=False, categoryId='music', tags=['-xh', 'china', 'music'], chapters=[], stats=dict(views=29, likes=20, dislikes=0, comments=0, averageRating=None, ratingCount=0, shares=0), viewerState=dict(rating=None, reaction=None))
def card(id):
    return dict(videoId=id, channelId='creator', channelName='Music', channelHandle='music', title=id, thumbnailUrl=None, duration=39, visibility='public', publishedAt=now.isoformat(), views=29)
def result(items):
    return dict(items=items, total=len(items), page=1, pageSize=20)

results = []
with server.serve(args.root.resolve()) as base, sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    for width, lang in [(1440, 'vi'), (390, 'vi'), (1440, 'en')]:
        context = browser.new_context(viewport=dict(width=width, height=1000))
        context.add_init_script("localStorage.setItem('hutube_lang', '" + lang + "')")
        state = dict(mode='normal', searches=[])
        errors = []
        def api(route):
            request = route.request
            url = urlsplit(request.url)
            path = url.path.split('/api/v1', 1)[-1]
            headers = {'Access-Control-Allow-Origin': request.headers.get('origin', base), 'Access-Control-Allow-Credentials': 'true', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': 'GET,POST,PUT,PATCH,DELETE,OPTIONS'}
            if request.method == 'OPTIONS':
                route.fulfill(status=204, headers=headers)
                return
            data, status = result([]), 200
            if path == '/auth/refresh': data = dict(accessToken='isolated-test', expiresAt=(now + timedelta(hours=1)).isoformat(), user=user)
            elif path == '/auth/me': data = user
            elif path == '/auth/session/player-preferences': data = dict(volume=1, muted=False)
            elif path == '/plans/my-plan': data = dict(features={}, subscription=None)
            elif path == f'/videos/{vid}': data = video
            elif path == f'/videos/{vid}/playback': data = dict(videoId=vid, title=video['title'], visibility='public', duration=39, resumeAtSeconds=0, progress=0, renditions=[])
            elif path == '/videos/search':
                query = parse_qs(url.query)
                state['searches'].append(query)
                if state['mode'] == 'error': data, status = dict(message='offline'), 503
                elif state['mode'] == 'empty': data = result([card(vid)])
                elif 'channelId' in query: data = result([card(vid), card('same-channel')])
                elif 'tag' in query: data = result([card(vid)])
                else: data = result([card(vid), card('category-related')])
            elif path in ('/feed/recommended', '/feed/home', '/feed/resolve'): data = result([card(vid), card('personalized')])
            elif path == '/channels/me': data, status = {}, 404
            elif path.endswith('/subscribe-status'): data = dict(status='inactive', notificationsEnabled=False)
            elif path.startswith('/channels/') and path not in ('/channels/accessible', '/channels/invitations'):
                data = dict(channelId='creator', ownerUserId='owner', name='Music', handle='music', subscriberCount=0, videoCount=20, avatarUrl=None)
            elif path in ('/categories', '/violation-types', '/subscriptions', '/channels/accessible', '/channels/invitations'): data = []
            route.fulfill(status=status, headers=headers, content_type='application/json', body=json.dumps(data))
        context.route('**/api/v1/**', api)
        context.route('https://mcp.figma.com/**', lambda route: route.abort())
        page = context.new_page()
        page.on('pageerror', lambda error: errors.append(str(error)))
        page.goto(base + '/watch/' + vid)
        page.wait_for_load_state('networkidle')
        cards = page.locator('.recommendation-card')
        expect(cards).to_have_count(1)
        expect(cards.first).to_have_attribute('href', '/watch/personalized')
        tabs = page.locator('.recommendation-filters button')
        tabs.nth(1).click()
        expect(cards).to_have_count(1)
        expect(cards.first).to_have_attribute('href', '/watch/category-related')
        assert state['searches'][-2]['tag'] == ['-xh']
        assert 'tag' not in state['searches'][-1] and state['searches'][-1]['categoryId'] == ['music']
        page.locator('.recommendations').screenshot(path=str(args.artifacts / f'related-{width}-{lang}.png'))
        tabs.nth(2).click()
        expect(cards.first).to_have_attribute('href', '/watch/same-channel')
        state['mode'] = 'error'
        tabs.nth(1).click()
        alert = page.locator('.recommendations [role=alert]')
        expect(alert).to_be_visible()
        expect(cards).to_have_count(0)
        state['mode'] = 'normal'
        alert.locator('button').click()
        expect(cards.first).to_have_attribute('href', '/watch/category-related')
        expect(alert).to_have_count(0)
        state['mode'] = 'empty'
        tabs.nth(2).click()
        expect(cards).to_have_count(0)
        expect(page.locator('.recommendations-empty')).to_be_visible()
        expect(alert).to_have_count(0)
        assert not errors, errors
        results.append(dict(width=width, lang=lang, passed=['personalized', 'rare-tag-category-fill', 'channel', 'failure', 'retry', 'empty'], pageErrors=errors))
        context.close()
    browser.close()
(args.artifacts / 'results.json').write_text(json.dumps(results, indent=2), encoding='utf-8')
print(json.dumps(dict(passed=len(results), cases=results)))
