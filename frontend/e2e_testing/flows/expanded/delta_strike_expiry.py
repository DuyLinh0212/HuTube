"""Let a real strike cross its deadline; never seed an expired result."""
import time
from email import policy
from email.parser import BytesParser
from email.utils import getaddresses
from pathlib import Path
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from flows.expanded.security_plan_common import identity
from support.local_db import LocalDb


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    identity(suite, config, 'delta_expiry')
    owner = suite.actor('delta-expiry-owner', 'user', 'delta_expiry')
    admin = actors['admin']
    channel = suite.api(owner, 'post', '/channels', data={
        'name': 'Delta natural strike expiry', 'handle': 'delta-expiry-' + suite.run_id[9:15],
    }, expected=201).json()
    cid = channel['channelId']
    db = LocalDb(config)
    strike = {}
    reason = 'Delta natural expiry ' + suite.run_id
    def notices():
        return db.sql("SELECT count(*) FROM notifications WHERE resource_id=:'id'::uuid AND user_id=:'uid'::uuid;", {'id': cid, 'uid': owner['identity']['userId']})
    def audit():
        rows = suite.api(admin, 'get', '/admin/operations/audit-logs', params={'page': 1, 'pageSize': 100, 'search': reason}).json()['items']
        return {(r['action'], str(r.get('resourceId'))) for r in rows}
    try:
        def expiry(entry):
            before_mail = time.time()
            strike.update(suite.api(admin, 'post', '/admin/strikes', data={
                'channelId': cid, 'severity': 'high', 'reason': reason, 'policyCode': 'DELTA.EXPIRY',
            }, expected=201).json())
            baseline = suite.api(owner, 'get', '/channels/' + cid + '/strikes').json()
            assert baseline['activeStrikesCount'] == 1
            preflight = {'channelId': cid, 'fileSize': 1024, 'duration': 2, 'contentType': 'video/mp4', 'sourceQuality': '360p'}
            suite.api(owner, 'post', '/videos/upload-preflight', data=preflight, expected=(400, 403, 409))
            assert ('strike.create', cid) in audit()
            deadline = time.monotonic() + 15
            received = False
            while time.monotonic() < deadline and not received:
                for file in Path(config['mail_dir']).glob('*.eml'):
                    if file.stat().st_mtime < before_mail:
                        continue
                    message = BytesParser(policy=policy.default).parsebytes(file.read_bytes())
                    recipients = {e.lower() for _, e in getaddresses(message.get_all('to', []))}
                    body = message.get_body(preferencelist=('plain', 'html'))
                    if owner['identity']['email'].lower() in recipients and body and reason in body.get_content():
                        received = True
                        break
                if not received:
                    owner['page'].wait_for_timeout(200)
            assert received, 'Actual recipient-specific strike Pickup mail required'
            old_notices, old_audit = notices(), audit()
            db.sql("UPDATE channel_strikes SET expires_at=now()+interval '3 seconds' WHERE strike_id=:'id'::uuid AND status='active';", {'id': strike['strikeId']})
            owner['page'].wait_for_timeout(3500)
            current = suite.api(owner, 'get', '/channels/' + cid + '/strikes').json()
            exact = next(s for s in current['strikes'] if s['strikeId'] == strike['strikeId'])
            assert exact['status'] == 'expired' and current['activeStrikesCount'] == 0
            suite.api(owner, 'post', '/videos/upload-preflight', data=preflight)
            assert notices() == old_notices and audit() == old_audit
            suite.go(admin, '/moderation/strikes', 'app-admin-strikes-page', '/admin/strikes')
            admin['page'].locator('.status-tabs button').nth(1).click()
            expect(admin['page'].locator('tbody tr').filter(has_text=reason)).to_have_count(1)
            admin['page'].reload()
            admin['page'].locator('.status-tabs button').nth(1).click()
            expect(admin['page'].locator('tbody tr').filter(has_text=reason)).to_have_count(1)
            entry['resource_ids'] = [cid, strike['strikeId']]
            entry['mail_manual'] = 'Pickup notification contract PASS; real mailbox certification separate'
            entry['expiry_contract'] = 'Expiry is computed from the server clock on reads; current product has no expiry-event audit/email publisher. Creation audit/mail persists; expiry reads emit no duplicate events.'
            entry['steps'] = ['Real strike blocks upload; creation audit and recipient Pickup mail verified', 'Shorten only owned expiry deadline and wait actual server time', 'Actual API reports expired/count zero and preflight permits upload', 'No duplicate audit/notification from repeated expiry reads', 'Admin expired tab retains exact strike across reload in three viewports']
        case(suite, admin, 'DELTA-STRIKE-NATURAL-EXPIRY-AUDIT-NOTIFICATION', 'A-MODERATION.05', 'Natural strike expiry restores permission and preserves event evidence', expiry, 'strikes')
    finally:
        if strike:
            suite.api(admin, 'post', '/admin/strikes/' + strike['strikeId'] + '/revoke', data={'reason': 'Cleanup owned expired delta strike'}, expected=(200, 400, 409))
        suite.release_actor(owner)
