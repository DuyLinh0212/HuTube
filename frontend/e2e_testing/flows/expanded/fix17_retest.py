import re
from urllib.parse import urlsplit, parse_qs
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.live_adapter import FunctionalAdapter
from support.live_suite import PrerequisiteMissing

def run(suite, config, actors):
    snapshot_module(suite, __file__)
    from flows.expanded import catalog, media_deep, comments_deep, moderation_deep, downloads_deep, shell_deep, upload_recovery
    # Resolve retained owned appeals through the actual UI. Failed old attempts
    # may have left an automatic strike; resolving them restores fixture access.
    from flows.expanded import appeal_retest
    owned = suite.api(actors['owner'], 'get', '/appeals/my').json()
    owned = owned if isinstance(owned, list) else owned['items']
    pending = [a for a in owned if a['targetType'] == 'video' and a['status'] in ('pending', 'reviewing')
        and (not a.get('reviewerId') or a['reviewerId'] == actors['reviewer2']['identity']['userId'])]
    for _ in pending:
        appeal_retest.run(suite, config, actors)
    for name, execute in [
        ('catalog', lambda: catalog.run(suite, config, actors)),
        ('draft', lambda: media_deep.run(suite, {**config, 'fix17_draft_only': True}, actors)),
        ('comments', lambda: comments_deep.run(suite, config, actors)),
        ('moderation', lambda: moderation_deep.run(suite, config, actors)),
        ('downloads', lambda: downloads_deep.run(suite, config, actors)),
        ('shell', lambda: shell_deep.run(suite, config, actors)),
        ('upload-recovery', lambda: upload_recovery.run(suite, config, actors)),
        ('policy-player', lambda: run_policy_and_player(suite, config, actors))
    ]:
        try:
            execute()
        except Exception as error:
            def missing(entry, error=error):
                raise PrerequisiteMissing(name+' prerequisite incomplete: '+type(error).__name__)
            case(suite, actors['owner'], 'FIX17-PREREQUISITE-'+name.upper(), 'RUN-PREREQUISITE', 'Incomplete '+name+' prerequisite', missing, 'runner')

def run_policy_and_player(suite, config, actors):
    snapshot_module(suite, __file__)
    owner, member = actors['owner'], actors['member']
    from flows.user import live_policy
    snapshot_module(suite, live_policy.__file__)
    original = suite.case
    def policy_case(actor, id, *args, **kwargs):
        return original(actor, 'FULL-FOUNDATION-'+id, *args, **kwargs)
    suite.case = policy_case
    try:
        live_policy.run(suite, owner)
    finally:
        suite.case = original

    videos = [v for v in suite.fixtures['videos'] if v['status'] == 'published' and v['moderationStatus'] == 'approved' and v['visibility'] == 'public']
    ids = list(dict.fromkeys(v['videoId'] for v in videos))[:3]
    assert len(ids) == 3, 'Three real approved videos required for manual playlist navigation'
    playlist = suite.api(owner, 'post', '/playlists', data={'name': 'QC fix17 queue '+suite.run_id, 'visibility': 'public'}, expected=(200,201)).json()
    pid = playlist['playlistId']
    for vid in ids:
        suite.api(owner, 'post', '/playlists/'+pid+'/videos', data={'videoId': vid}, expected=(200,201))
    try:
        def navigate(entry):
            suite.go(member, '/watch/'+ids[0]+'?playlist='+pid+'&index=0', 'app-watch-page')
            p = member['page']
            expect(p.locator('.playlist-previous')).to_be_disabled()
            expect(p.locator('.playlist-next')).to_be_enabled()
            def verify(index):
                p.wait_for_url('**/watch/'+ids[index]+'?**')
                p.wait_for_function('()=>document.querySelector("video.video-player")?.readyState>=1')
                assert parse_qs(urlsplit(p.url).query)['playlist'] == [pid]
                assert parse_qs(urlsplit(p.url).query)['index'] == [str(index)]
                playback = suite.api(member, 'get', '/videos/'+ids[index]+'/playback').json()
                source = p.locator('video.video-player').evaluate('(v)=>v.currentSrc')
                assert any(urlsplit(r['url']).path == urlsplit(source).path for r in playback['renditions'])
            p.locator('.playlist-next').click(); verify(1)
            p.locator('.playlist-previous').click(); verify(0)
            p.locator('.playlist-next').click(); verify(1)
            p.locator('.playlist-next').click(); verify(2)
            expect(p.locator('.playlist-next')).to_be_disabled()
            p.reload(); expect(p.locator('.playlist-next')).to_be_disabled()
            expect(p.locator('.playlist-previous')).to_be_enabled()
            entry['resource_ids'] = [pid]+ids
            entry['steps'] = ['First item disables Previous', 'Mouse Next changes exact video, playlist and stream', 'Previous returns to exact first video', 'Last item disables Next', 'Reload preserves endpoint and navigation boundaries']
        case(suite, member, 'FOUNDATION-FULL-PLAYLIST-MANUAL-NEXT-PREVIOUS-UI', 'U-PLAYLIST.03', 'Manual playlist navigation persists correct video streams', navigate, 'playlists')
    finally:
        suite.api(owner, 'delete', '/playlists/'+pid, expected=(200,204))

    vid = suite.fixtures['video']['videoId']
    def denied(entry):
        plan = suite.api(member, 'get', '/plans/my-plan').json()
        assert not plan['features'].get('pip')
        suite.go(member, '/watch/'+vid, 'app-watch-page')
        p = member['page']; p.bring_to_front()
        if not p.evaluate('()=>document.pictureInPictureEnabled'):
            raise PrerequisiteMissing('Browser does not support native PiP')
        p.wait_for_function('()=>document.querySelector("video.video-player")?.readyState>=1')
        expect(p.locator('.player-pip-button')).to_be_disabled()
        assert p.locator('video.video-player').evaluate('(v)=>v.disablePictureInPicture')
        assert p.evaluate('()=>!document.pictureInPictureElement')
        p.reload(); expect(p.locator('.player-pip-button')).to_be_disabled()
        entry['resource_ids'] = [vid, member['identity']['userId']]
        entry['steps'] = ['Real Member plan pip=false', 'Native PiP supported', 'Control denied and native video PiP disabled', 'No native PiP session', 'Reload retains entitlement denial']
    case(suite, member, 'WATCH-PIP-ENTITLEMENT-DENIAL', 'U-WATCH.01', 'Native PiP denied for plan without entitlement', denied, 'watch')
    def allowed(entry):
        assert suite.api(owner, 'get', '/plans/my-plan').json()['features']['pip']
        suite.go(owner, '/watch/'+vid, 'app-watch-page')
        p = owner['page']; p.bring_to_front()
        if not p.evaluate('()=>document.pictureInPictureEnabled'):
            raise PrerequisiteMissing('Browser does not support native PiP')
        p.wait_for_function('()=>document.querySelector(".global-picture-in-picture-video")?.readyState>=1')
        expect(p.locator('.player-pip-button')).to_be_enabled()
        p.locator('video.video-player').hover(); p.locator('.player-pip-button').click()
        p.wait_for_function('()=>!!document.pictureInPictureElement')
        p.locator('.player-pip-button').click(); p.wait_for_function('()=>!document.pictureInPictureElement')
        entry['resource_ids'] = [vid, owner['identity']['userId']]
        entry['steps'] = ['Real Owner plan pip=true', 'UI enters actual native pictureInPictureElement', 'UI exits native PiP successfully']
    try:
        case(suite, owner, 'WATCH-PIP-ENTITLEMENT-ALLOW-EXIT', 'U-WATCH.01', 'Entitled plan can enter and exit actual native PiP', allowed, 'watch')
    finally:
        p = owner['page']
        if p.evaluate('()=>!!document.pictureInPictureElement'): p.locator('.player-pip-button').click()
