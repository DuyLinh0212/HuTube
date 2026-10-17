"""Targeted regression for discarding a saved upload draft."""
import shutil
import subprocess

from playwright.sync_api import expect

from flows.expanded.common import case, snapshot_module


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    owner = actors['owner']
    page = owner['page']
    channel_id = suite.fixtures['channel']['channelId']
    fixture = suite.run_dir / 'draft-discard-fixture.mp4'
    subprocess.run([
        shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=24', '-t', '8',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', str(fixture),
    ], check=True, timeout=60)

    def discard(entry):
        draft_key = 'hutube.upload.draft.' + owner['identity']['userId'] + '.' + channel_id
        page.evaluate('(key) => localStorage.removeItem(key)', draft_key)
        try:
            suite.go(owner, '/studio/upload?channelId=' + channel_id, 'app-video-upload-wizard')
            page.locator('#videoFile').set_input_files(str(fixture))
            expect(page.locator('.btn-wizard-next')).to_be_enabled(timeout=45000)
            page.locator('.btn-wizard-next').click()
            expect(page.locator('.step-2')).to_be_visible()
            title = 'QC discard draft ' + suite.run_id
            page.locator('#videoTitle').fill(title)
            page.locator('#videoDesc').fill('This owned local draft must not survive discard.')
            page.locator('#videoLang').select_option('en')
            page.locator('#newTag').fill('discard-check')
            page.locator('#newTag').press('Enter')
            page.locator('.btn-wizard-draft').click()
            expect(page.locator('[role=status]')).to_be_visible()
            assert page.evaluate('(key) => !!localStorage.getItem(key)', draft_key)

            page.locator('.btn-wizard-discard-draft').click()
            expect(page.locator('.step-1')).to_be_visible()
            expect(page.locator('.file-name')).to_have_count(0)
            expect(page.locator('[role=status]')).to_contain_text('nháp')
            assert not page.evaluate('(key) => localStorage.getItem(key)', draft_key)

            # A route reload proves the reset was not merely a transient DOM state.
            page.reload()
            expect(page.locator('.step-1')).to_be_visible()
            expect(page.locator('.file-name')).to_have_count(0)
            page.locator('#videoFile').set_input_files(str(fixture))
            expect(page.locator('.btn-wizard-next')).to_be_enabled(timeout=45000)
            page.locator('.btn-wizard-next').click()
            expect(page.locator('#videoTitle')).not_to_have_value(title)
            expect(page.locator('#videoLang')).to_have_value('vi')
            expect(page.locator('.tag-chip')).to_have_count(0)
            entry['resource_ids'] = [channel_id]
            entry['steps'] = [
                'Save a real local metadata draft from the actual wizard',
                'Use the explicit Discard changes control; form returns to step 1 and local draft key is removed',
                'Reload, reselect the real MP4 and prove old title/language/tag values do not restore',
            ]
        finally:
            page.evaluate('(key) => localStorage.removeItem(key)', draft_key)

    case(suite, owner, 'UPLOAD-DRAFT-DISCARD-RESET-PERSISTENCE', 'U-STUDIO.03',
         'Discarding an upload draft clears local metadata and stays cleared after reload', discard, 'studio')
