"""The implemented subtitle page is a read-only inventory, not an upload/editor."""
import hashlib
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.actor_readiness import ensure_actor_pages


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    ensure_actor_pages(suite, actors, ['owner'])
    owner = actors['owner']; p = owner['page']; cid = suite.fixtures['channel']['channelId']
    def inventory(entry):
        videos = []; page = 1
        while True:
            response = suite.api(owner, 'get', '/videos/manage', params={'channelId': cid, 'page': page, 'pageSize': 50}).json()
            videos.extend(response['items'])
            if page * response['pageSize'] >= response['total']: break
            page += 1
        suite.go(owner, '/studio/subtitles?channelId=' + cid, 'app-studio-subtitles-page')
        rows = p.locator('app-studio-subtitles-page article')
        expect(rows).to_have_count(len(videos))
        expect(rows.locator('strong')).to_have_text([video['title'] for video in videos])
        for index in range(len(videos)): expect(rows.nth(index).locator(':scope > span')).to_contain_text('Chưa có phụ đề')
        expect(p.locator('app-studio-subtitles-page button,app-studio-subtitles-page input,app-studio-subtitles-page select')).to_have_count(0)
        root = Path(__file__).resolve().parents[4]
        paths = ['frontend/user-web/src/app/features/studio/pages/studio-subtitles-page.html', 'frontend/user-web/src/app/features/studio/pages/studio-subtitles-page.ts']
        entry['source_review'] = [{'path': path, 'sha256': hashlib.sha256((root/path).read_bytes()).hexdigest()} for path in paths]
        entry['verified_na'] = ['Current subtitle template/component has no add/edit/upload/generate button or mutation API. All subtitle actions are N/A; visible inventory must honestly say no subtitles.']
        entry['resource_ids'] = [video['videoId'] for video in videos]
        entry['steps'] = ['Read every managed-video page for exact selected channel', 'Subtitle inventory contains exact real titles and honest no-subtitles state', 'Source and actual DOM agree that no subtitle operation is offered; no fake save/upload success']
    case(suite, owner, 'STUDIO-SUBTITLES-ACTUAL-READONLY-CONTRACT', 'U-STUDIO.09', 'Subtitle page shows honest real inventory without unsupported actions', inventory, 'studio')
