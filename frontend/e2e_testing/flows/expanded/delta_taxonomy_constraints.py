"""Uncovered taxonomy lengths, normalized duplicates and linked-record rules."""
import shutil
import subprocess
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    admin, owner = actors['admin'], actors['owner']
    topic, tag, video = {}, {}, {}
    suffix = suite.run_id[9:15]
    base = {'name': 'Delta taxonomy ' + suffix, 'slug': 'delta-taxonomy-' + suffix, 'description': 'Owned fixture', 'status': 'active'}
    def topics():
        return suite.api(admin, 'get', '/admin/topics').json()
    try:
        topic.update(suite.api(admin, 'post', '/admin/topics', data=base, expected=201).json())
        tag.update(suite.api(admin, 'post', '/admin/tags', data={'name': 'delta-linked-' + suffix}, expected=201).json())
        def validation(entry):
            initial = {v['categoryId'] for v in topics()}
            duplicate = suite.api(admin, 'post', '/admin/topics', data={**base, 'slug': ' ' + base['slug'].upper() + ' '}, expected=409)
            assert duplicate.json()['code'] == 'TOPIC_SLUG_EXISTS'
            for field, value in [('name', 'x'*101), ('slug', 'x'*121), ('description', 'x'*1001)]:
                suite.api(admin, 'post', '/admin/topics', data={**base, 'slug': 'delta-bad-' + suffix, field: value}, expected=400)
                assert {v['categoryId'] for v in topics()} == initial
            suite.api(admin, 'post', '/admin/tags', data={'name': ' #'+tag['name'].upper()+' '}, expected=409)
            suite.api(admin, 'post', '/admin/tags', data={'name': 'x'*81}, expected=400)
            suite.api(admin, 'put', '/admin/topics/' + topic['categoryId'], data={
                **base, 'name': 'x'*100, 'slug': 's'*120, 'description': 'd'*1000,
            })
            actual = next(v for v in topics() if v['categoryId'] == topic['categoryId'])
            assert len(actual['name']) == 100 and len(actual['slug']) == 120 and len(actual['description']) == 1000
            suite.api(admin, 'put', '/admin/topics/' + topic['categoryId'], data=base)
            suite.go(admin, '/topics', 'app-admin-topics-page', '/admin/topics')
            admin['page'].locator('input[type=search]').fill(base['slug'])
            expect(admin['page'].locator('tbody tr').filter(has_text=base['slug'])).to_have_count(1)
            entry['resource_ids'] = [topic['categoryId'], tag['tagId']]
            entry['steps'] = ['Normalized duplicate slug/tag rejects 409', 'Name101/slug121/description1001/tag81 reject 400 without extra records', 'Exact topic maximum lengths persist through actual API', 'Restore readable fixture and reload exact Admin row']
        case(suite, admin, 'DELTA-TAXONOMY-DUPLICATE-LENGTH-BOUNDARIES', 'A-TOPICS.01', 'Taxonomy rejects duplicates and enforces exact field limits', validation, 'topics')

        file = suite.run_dir / 'delta-taxonomy.mp4'
        subprocess.run([shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error', '-f', 'lavfi', '-i',
            'testsrc2=size=320x180:rate=10', '-t', '2', '-c:v', 'libx264', '-preset', 'ultrafast', str(file)], check=True, timeout=60)
        video.update(suite.api(owner, 'post', '/videos', multipart={
            'ChannelId': suite.fixtures['channel']['channelId'], 'Title': 'Delta linked taxonomy ' + suffix,
            'CategoryId': topic['categoryId'], 'Visibility': 'private', 'Duration': '2', 'SourceQuality': '360p',
            'Video': {'name': file.name, 'mimeType': 'video/mp4', 'buffer': file.read_bytes()},
        }, expected=201).json())
        suite.api(owner, 'patch', '/videos/' + video['videoId'], data={'tags': [tag['name']]})
        def linked(entry):
            path = '/videos/' + video['videoId']
            before = suite.api(owner, 'get', path).json()
            assert before['categoryId'] == topic['categoryId'] and tag['name'] in before['tags']
            rejected = suite.api(admin, 'delete', '/admin/tags/' + tag['tagId'], expected=409)
            assert rejected.json()['code'] == 'TAG_IN_USE'
            suite.api(admin, 'post', '/admin/topics/' + topic['categoryId'] + '/archive', data={}, expected=204)
            after = suite.api(owner, 'get', path).json()
            assert after['videoId'] == before['videoId'] and after['categoryId'] == before['categoryId'] and after['tags'] == before['tags']
            assert not any(v['categoryId'] == topic['categoryId'] for v in suite.api(owner, 'get', '/categories').json())
            stored = next(v for v in topics() if v['categoryId'] == topic['categoryId'])
            assert stored['status'] == 'inactive' and stored['videoCount'] == 1
            suite.go(admin, '/topics', 'app-admin-topics-page', '/admin/topics')
            admin['page'].locator('input[type=search]').fill(base['slug'])
            admin['page'].locator('.select-field select').select_option('inactive')
            expect(admin['page'].locator('tbody tr').filter(has_text=base['slug'])).to_have_count(1)
            entry['resource_ids'] = [video['videoId'], topic['categoryId'], tag['tagId']]
            entry['category_delete_contract'] = 'N/A hard-delete category: current API offers archive only. Linked category archival is allowed and preserves references; linked tag deletion is rejected.'
            entry['steps'] = ['Actual video references category/tag through real API', 'Linked tag delete rejects TAG_IN_USE', 'Category archive is allowed without unlinking/deleting video', 'Inactive category absent from new-selection catalog, retained with usage count in Admin', 'Reload inactive row matches exact fixture']
        case(suite, admin, 'DELTA-TAXONOMY-LINKED-ARCHIVE-DELETE', 'A-TOPICS.01', 'Linked taxonomy operations preserve video references', linked, 'topics')
    finally:
        if video:
            suite.api(owner, 'patch', '/videos/' + video['videoId'], data={'tags': [], 'clearCategory': True})
            suite.api(owner, 'delete', '/videos/' + video['videoId'], expected=(204, 404))
        if tag:
            suite.api(admin, 'delete', '/admin/tags/' + tag['tagId'], expected=(204, 404))
        if topic:
            suite.api(admin, 'post', '/admin/topics/' + topic['categoryId'] + '/archive', data={}, expected=204)
        suite.report['cleanup'].append({'resource': 'delta taxonomy video/tag/category', 'status': 'video-tag-deleted-category-archived'})
