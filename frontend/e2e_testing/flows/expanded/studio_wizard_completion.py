"""Targeted, non-publishing checks for the remaining upload-wizard clauses."""
import shutil
import subprocess
import re

from playwright.sync_api import expect

from flows.expanded.common import case, snapshot_module


def _fixture(suite):
    path = suite.run_dir / 'wizard-completion-fixture.mp4'
    subprocess.run([
        shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-t', '12',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(path),
    ], check=True, timeout=60)
    return path


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    owner = actors['owner']
    page = owner['page']
    channel_id = suite.fixtures['channel']['channelId']
    fixture = _fixture(suite)

    def wizard_metadata_frames(entry):
        # The draft belongs only to this isolated actor/channel.  Start clean and
        # remove it afterwards so this evidence does not alter a later suite.
        draft_key = 'hutube.upload.draft.' + owner['identity']['userId'] + '.' + channel_id
        page.evaluate('(key) => localStorage.removeItem(key)', draft_key)
        before = suite.api(owner, 'get', '/videos/manage', params={
            'channelId': channel_id, 'page': 1, 'pageSize': 100,
        }).json()
        before_ids = {item['videoId'] for item in before['items']}
        categories = suite.api(owner, 'get', '/categories').json()
        created_category_id = ''
        if not categories:
            # This is fixture setup through the real Admin UI, rather than a
            # seeded database row.  The subject of this case remains the User
            # wizard's consumption of the resulting live catalog entry.
            admin = actors['admin']
            admin_page = admin['page']
            suffix = suite.run_id[-10:].lower()
            suite.go(admin, '/topics', 'app-admin-topics-page')
            admin_page.locator('.heading-actions .btn-primary').click()
            admin_page.locator('[name=topicName]').fill('QC Wizard Category ' + suffix)
            admin_page.locator('[name=topicSlug]').fill('qc-wizard-category-' + suffix)
            admin_page.locator('[name=topicDescription]').fill('Temporary category for the isolated upload wizard check.')
            with admin_page.expect_response(lambda response: response.request.method == 'POST' and response.url.endswith('/api/v1/admin/topics'), timeout=30000) as pending:
                admin_page.locator('[role=dialog] button[type=submit]').click()
            assert pending.value.status == 201
            created_category_id = pending.value.json()['categoryId']
            categories = suite.api(owner, 'get', '/categories').json()
        assert categories, 'The User category endpoint did not expose the active Admin-created category'
        category_id = str(categories[0]['categoryId'])

        try:
            suite.go(owner, '/studio/upload?channelId=' + channel_id, 'app-video-upload-wizard')
            page.locator('#videoFile').set_input_files(str(fixture))
            expect(page.locator('.btn-wizard-next')).to_be_enabled(timeout=45000)
            page.locator('.btn-wizard-next').click()
            expect(page.locator('.step-2')).to_be_visible()

            thumbnails = page.locator('.thumb-card')
            expect(thumbnails).to_have_count(3)
            assert thumbnails.locator('img').evaluate_all('(items) => items.every(i => i.currentSrc.startsWith("blob:"))')
            thumbnails.nth(1).click()
            expect(thumbnails.nth(1)).to_have_class(re.compile(r'(^| )is-selected( |$)'))

            title = 'QC wizard completion ' + suite.run_id
            page.locator('#videoTitle').fill(title)
            page.locator('#videoDesc').fill('Frame, metadata and chapter boundaries are retained while navigating back.')
            page.locator('#videoCategory').select_option(category_id)
            page.locator('#videoLang').select_option('ja')
            tag = 'qc-wizard-' + suite.run_id[-6:].lower()
            page.locator('#newTag').fill(tag)
            page.locator('#newTag').press('Enter')
            page.locator('#newTag').fill(tag)
            page.locator('#newTag').press('Enter')
            expect(page.locator('.tag-chip')).to_have_count(1)
            expect(page.locator('.tag-chip')).to_contain_text(tag)

            page.locator('.btn-wizard-next').click()
            expect(page.locator('.step-3')).to_be_visible()
            preview = page.locator('video.player-video')
            page.wait_for_function('() => document.querySelector("video.player-video")?.readyState >= 1')
            track = page.locator('.scrubber-track')
            box = track.bounding_box()
            assert box and box['width'] > 20
            page.mouse.click(box['x'] + box['width'] * 0.65, box['y'] + box['height'] / 2)
            page.wait_for_function('() => Number(document.querySelector(".scrubber-track")?.getAttribute("aria-valuenow")) >= 6')
            assert preview.evaluate('(video) => video.currentTime >= 6')

            title_input = page.locator('.add-chapter-row input').first
            time_input = page.locator('.add-chapter-row .time-input')
            add = page.locator('.btn-add-ch').first
            title_input.fill('Opening')
            time_input.fill('0:01')
            add.click()
            title_input.fill('Middle')
            time_input.fill('0:04')
            add.click()
            expect(page.locator('.chapters-table tbody tr')).to_have_count(2)
            expect(page.locator('.chapter-time-edit').nth(0)).to_have_value('0:01')
            expect(page.locator('.chapter-time-edit').nth(1)).to_have_value('0:04')
            title_input.fill('Duplicate time')
            time_input.fill('0:04')
            add.click()
            expect(page.locator('[role=alert]')).to_be_visible()
            expect(page.locator('.chapters-table tbody tr')).to_have_count(2)

            page.locator('.btn-wizard-back').click()
            expect(page.locator('.step-2')).to_be_visible()
            expect(page.locator('#videoTitle')).to_have_value(title)
            expect(page.locator('#videoCategory')).to_have_value(category_id)
            expect(page.locator('#videoLang')).to_have_value('ja')
            expect(page.locator('.tag-chip')).to_contain_text(tag)
            expect(page.locator('.thumb-card').nth(1)).to_have_class(re.compile(r'(^| )is-selected( |$)'))
            page.locator('.btn-wizard-next').click()
            expect(page.locator('.step-3')).to_be_visible()
            page.locator('.btn-wizard-next').click()
            expect(page.locator('.step-4')).to_be_visible()
            expect(page.locator('.checks-list .check-item.is-passed')).to_have_count(6)
            expect(page.locator('.issues-card .btn-fix-step')).to_have_count(2)
            entry['resource_ids'] = [channel_id]
            entry['steps'] = [
                'Select a real 12-second MP4; browser reads metadata and captures three blob-backed frame thumbnails',
                'Choose a generated frame, real category and Japanese language; duplicate tag stays a single normalized value',
                'Use the actual scrubber to seek preview, add ordered chapters, then reject an equal-time chapter',
                'Navigate Back and forward: selected thumbnail, category, language, tag and chapter data remain intact',
                'Reach the real preflight review step; six checks and two edit links render without creating a video',
            ]
        finally:
            page.evaluate('(key) => localStorage.removeItem(key)', draft_key)
            after = suite.api(owner, 'get', '/videos/manage', params={
                'channelId': channel_id, 'page': 1, 'pageSize': 100,
            }).json()
            assert {item['videoId'] for item in after['items']} == before_ids, 'Non-publishing wizard flow created or removed a video'
            if created_category_id:
                suite.api(actors['admin'], 'post', '/admin/topics/' + created_category_id + '/archive', expected=(200, 204))
                entry.setdefault('cleanup', []).append({'categoryId': created_category_id, 'action': 'archive temporary UI-created category'})

    case(suite, owner, 'UPLOAD-WIZARD-FRAMES-METADATA-BACK', 'U-STUDIO.02',
         'Wizard retains real frame, metadata and chapter state through Back and review',
         wizard_metadata_frames, 'studio')
