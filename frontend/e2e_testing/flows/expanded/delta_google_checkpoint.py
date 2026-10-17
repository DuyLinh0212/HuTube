"""Human operates genuine Google popup; automation verifies HuTube contracts."""
import json
import time
from urllib.parse import urlsplit
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from support.live_suite import PrerequisiteMissing


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    guest = suite.actor('manual-google-delta', 'user', 'guest')
    guest['api_url'] = config['api_url']
    p = guest['page']
    configured = suite.api(guest, 'get', '/system/config').json()
    if not configured.get('googleClientId'):
        raise PrerequisiteMissing('Real Google client ID is absent in configured isolated environment')
    suite.go(guest, '/login', 'app-auth-page')
    p.bring_to_front()
    result = []
    def response(r):
        if urlsplit(r.url).path == '/api/v1/auth/google' and r.request.method == 'POST':
            result.append({'status': r.status, 'value': r.json()})
    # Google SDK popup/iframe traffic may finish in another page of this same
    # owned context. Observe the context, not only the opener document.
    guest['context'].on('response', response)
    def ready(stage, instructions):
        (suite.run_dir / 'manual-checkpoint.json').write_text(json.dumps({
            'run_id': suite.run_id, 'stage': stage, 'url': p.url, 'instructions': instructions,
        }, ensure_ascii=False, indent=2), encoding='utf-8')
        print('MANUAL_CHECKPOINT ' + stage + ' ' + suite.run_id, flush=True)
    try:
        def cancel(entry):
            opened = []
            p.on('popup', lambda popup: opened.append(popup))
            before = len(result)
            ready('GOOGLE_CANCEL', 'Click real Google button and close the provider popup without selecting an account. Then wait for GOOGLE_SIGNIN.')
            deadline = time.monotonic() + 600
            while time.monotonic() < deadline:
                if opened and not opened[-1].is_closed() and '/oauth/error' in opened[-1].url:
                    raise PrerequisiteMissing('Google rejected the configured JavaScript origin; provider cancellation is not certified')
                if opened and opened[-1].is_closed():
                    break
                p.wait_for_timeout(500)
            else:
                raise PrerequisiteMissing('Recipient has not completed genuine Google popup cancellation within checkpoint window')
            assert len(result) == before
            suite.api(guest, 'get', '/auth/me', expected=401)
            expect(p.locator('app-auth-page')).to_be_visible()
            entry['steps'] = ['User opens genuine Google SDK popup', 'User cancels popup', 'No Google credential POST; /auth/me remains 401; login UI retained']
        if not config.get('google_skip_cancel') and not case(suite, guest, 'DELTA-GOOGLE-HUMAN-PROVIDER-CANCEL', 'AUTH-EXT-05', 'Manual provider cancellation creates no HuTube session', cancel, 'authentication'):
            return
        def login(entry):
            ready('GOOGLE_SIGNIN', 'Click Google again and sign in yourself. Never send password/token to automation. HuTube must reach /home.')
            deadline = time.monotonic() + 600
            while time.monotonic() < deadline and not result:
                p.wait_for_timeout(500)
            if not result:
                raise PrerequisiteMissing('Real provider has not returned a credential to HuTube within checkpoint window')
            actual = result[-1]
            assert actual['status'] == 200, 'Actual Google login HTTP ' + str(actual['status'])
            identity = actual['value']['user']
            guest['identity'] = identity
            guest['headers']['Authorization'] = 'Bearer ' + actual['value']['accessToken']
            value = suite.api(guest, 'get', '/auth/me').json()
            assert value['userId'] == identity['userId'] and value['email'] == identity['email']
            p.wait_for_url('**/home')
            expect(p.locator('app-home-page')).to_be_visible()
            p.reload()
            expect(p.locator('app-home-page')).to_be_visible()
            assert suite.api(guest, 'get', '/auth/me').json()['userId'] == identity['userId']
            entry['resource_ids'] = [identity['userId']]
            entry['steps'] = ['Human signs in through genuine Google provider', 'HuTube POST 200 yields actual Google identity', 'Authenticated /auth/me identity matches and survives reload', 'Expired/unverified/blocked/linking branches remain separate obligations']
        case(suite, guest, 'DELTA-GOOGLE-HUMAN-PROVIDER-SIGNIN', 'AUTH-EXT-05', 'Real provider identity authenticates and survives reload', login, 'authentication')
    finally:
        guest['context'].remove_listener('response', response)
        suite.release_actor(guest)
