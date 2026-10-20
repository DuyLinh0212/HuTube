"""Only the missing byte-exact owner/member allocation and renewal assertions."""
import shutil
import subprocess
from urllib.parse import parse_qs, urlsplit
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from flows.expanded.security_plan_common import identity
from tests.full_functional import pickup_link


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    admin = actors['admin']
    owned = []
    videos = []
    plan = {}
    invitation = {}
    try:
        for key in ('delta_quota_owner', 'delta_quota_member'):
            identity(suite, config, key)
            actor = suite.actor(key, 'user', key)
            owned.append(actor)
            actor['fixture_channel'] = suite.api(actor, 'post', '/channels', data={
                'name': 'Delta quota ' + key, 'handle': key.replace('_', '-') + '-' + suite.run_id[9:15],
            }, expected=201).json()
        owner, member = owned
        plan.update(suite.api(admin, 'post', '/admin/plans', data={
            'code': 'qc_delta_quota_' + suite.run_id[9:15], 'name': 'Delta exact byte boundaries',
            'price': 0, 'durationDays': 30, 'storageLimit': 5 * 1024**3,
            'maxUploadSize': 10 * 1024**2, 'maxVideoDuration': 60,
            'maxVideoQuality': '360p', 'maxDownloadQuality': '360p', 'maxMembers': 2,
            'features': '{}', 'isDefaultForNewUsers': False,
        }, expected=201).json())
        suite.api(owner, 'post', '/plans/' + plan['planId'] + '/subscribe', data={})
        sent = __import__('time').time()
        invitation.update(suite.api(owner, 'post', '/plans/members/invite', data={
            'email': member['identity']['email'], 'allocatedStorage': 1024**3,
        }).json())
        link = pickup_link(config, member['identity']['email'], 'plans/accept-invite', sent)
        token = parse_qs(urlsplit(link).query)['token'][0]
        suite.api(member, 'post', '/plans/members/' + invitation['planMemberId'] + '/accept', data={'token': token})
        file = suite.run_dir / 'delta-quota-real.mp4'
        subprocess.run([shutil.which('ffmpeg'), '-hide_banner', '-loglevel', 'error', '-f', 'lavfi',
            '-i', 'testsrc2=size=320x180:rate=10', '-t', '2', '-c:v', 'libx264', '-preset', 'ultrafast',
            '-pix_fmt', 'yuv420p', str(file)], check=True, timeout=60)
        for actor in owned:
            value = suite.api(actor, 'post', '/videos', multipart={
                'ChannelId': actor['fixture_channel']['channelId'], 'Title': 'Delta quota actual bytes',
                'Visibility': 'private', 'Duration': '2', 'SourceQuality': '360p',
                'Video': {'name': file.name, 'mimeType': 'video/mp4', 'buffer': file.read_bytes()},
            }, expected=201).json()
            videos.append((actor, value['videoId']))

        def boundaries(entry):
            observed = []
            for actor, path, field in (
                (owner, '/plans/my-subscription/owner-storage', 'ownerAllocatedStorage'),
                (member, '/plans/members/' + invitation['planMemberId'] + '/storage', 'allocatedStorage'),
            ):
                detail = suite.api(actor, 'get', '/plans/my-plan').json()
                used = detail['usedStorage']
                assert used > 0, 'Actual uploaded bytes required'
                def allocation():
                    current = suite.api(owner, 'get', '/plans/my-plan').json()
                    return current[field] if actor is owner else next(m[field] for m in current['members'] if m['planMemberId'] == invitation['planMemberId'])
                before = allocation()
                rejected = suite.api(owner, 'patch', path, data={'allocatedStorage': used - 1}, expected=400)
                assert rejected.json()['code'] == 'STORAGE_LIMIT_TOO_LOW'
                assert allocation() == before
                for amount in (used, used + 1):
                    suite.api(owner, 'patch', path, data={'allocatedStorage': amount}, expected=204 if actor is owner else 200)
                    assert allocation() == amount
                    actual = suite.api(actor, 'get', '/plans/my-plan').json()
                    assert actual['remainingStorage'] == amount - used
                    suite.go(actor, '/plans', 'app-plans-page', '/plans/my-plan')
                    expect(actor['page'].locator('.quota-numbers .used')).to_be_visible()
                    suite.evidence(actor, entry, ('owner' if actor is owner else 'member') + '-' + str(amount - used) + '-bytes-remaining')
                observed.append({'actor': actor['identity']['userId'], 'used_bytes': used, 'tested': [used - 1, used, used + 1]})
            entry['byte_boundaries'] = observed
            entry['resource_ids'] = [plan['planId'], invitation['planMemberId'], *[v for _, v in videos]]
            entry['steps'] = ['Independent synthetic owner/member with real encoded uploads', 'For both actors: usedBytes-1 rejected and allocation unchanged', 'Exact usedBytes accepted with zero remaining', 'usedBytes+1 accepted with one remaining', 'Real plans reload and three viewport evidence at each accepted boundary']
        case(suite, owner, 'DELTA-PLAN-EXACT-OWNER-MEMBER-USED-BYTES', 'U-PLAN.03', 'Owner and accepted member quota boundaries are byte exact', boundaries, 'plans')

        def renewal(entry):
            before = suite.api(owner, 'get', '/plans/my-plan').json()['subscription']
            suite.go(owner, '/plans', 'app-plans-page', '/plans/my-plan')
            p = owner['page']
            expect(p.locator('.subscription-timing')).to_be_visible()
            # Current User product exposes renewal state only; there is no
            # renew endpoint or renewable CTA. Admin auto-renew is another scope.
            assert p.locator('app-plans-page input[name=autoRenew],app-plans-page button[data-action=renew]').count() == 0
            p.reload()
            expect(p.locator('.subscription-timing')).to_be_visible()
            after = suite.api(owner, 'get', '/plans/my-plan').json()['subscription']
            for field in ('planHistoryId', 'startedAt', 'endedAt', 'autoRenew'):
                assert after[field] == before[field]
            entry['renewal_contract'] = 'User renewal action N/A: PlansController exposes subscribe/invite/quota only; UI displays renewal state. Admin auto-renew endpoint is not User renewal.'
            entry['steps'] = ['Read actual subscription dates/autoRenew', 'Current User UI exposes timing read-only', 'Reload leaves history ID/dates/autoRenew unchanged', 'Source-reviewed absence of User renew API is documented, not a provider success claim']
        case(suite, owner, 'DELTA-PLAN-RENEWAL-CURRENT-PRODUCT-CONTRACT', 'U-PLAN.03', 'Current renewal display preserves subscription on reload', renewal, 'plans')
    finally:
        for actor, vid in videos:
            suite.api(actor, 'delete', '/videos/' + vid, expected=(204, 404))
        if invitation and owned:
            suite.api(owned[0], 'delete', '/plans/members/' + invitation['planMemberId'], expected=(204, 404))
        if plan:
            suite.api(admin, 'post', '/admin/plans/' + plan['planId'] + '/archive', data={}, expected=204)
        for actor in owned:
            suite.report['cleanup'].append({'resource': 'owned delta quota resources', 'actor': actor['name'], 'status': 'videos-deleted-membership-revoked-plan-archived'})
            suite.release_actor(actor)
