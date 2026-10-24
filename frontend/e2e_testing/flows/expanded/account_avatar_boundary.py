"""Preserve the file limit after allowing multipart transport overhead."""
from playwright.sync_api import expect
from flows.expanded.common import case, snapshot_module
from flows.expanded.branding_boundaries import exact_png


def run(suite, config, actors):
    snapshot_module(suite, __file__)
    owner=actors['owner'];p=owner['page']
    def reject(entry):
        before=suite.go(owner,'/account','app-account-page','/account/profile')
        size=5*1024*1024+1
        payload={'name':'qc-avatar-limit-plus-one.png','mimeType':'image/png','buffer':exact_png(size)}
        p.locator('.channel-avatar-box input[type=file]').set_input_files(payload)
        expect(p.locator('.yt-alert-error')).to_be_visible()
        response=suite.api(owner,'post','/account/avatar',multipart={'file':payload},expected=400)
        assert response.json()['code']=='FILE_TOO_LARGE'
        assert suite.api(owner,'get','/account/profile').json()['avatarUrl']==before['avatarUrl']
        suite.response(owner,'/account/profile',p.reload)
        assert suite.api(owner,'get','/account/profile').json()['avatarUrl']==before['avatarUrl']
        entry['input_bytes']=size
        entry['resource_ids']=[owner['identity']['userId']]
        entry['steps']=['Valid PNG exactly 5MiB + 1 byte through actual file input; visible size error',
            'Actual multipart API rejects with 400 FILE_TOO_LARGE despite transport overhead allowance',
            'Profile read-back and browser reload retain original avatar URL']
    case(suite,owner,'ACCOUNT-AVATAR-MAX-PLUS-ONE','U-ACCOUNT.01','Account avatar file limit remains enforced',reject,'account')
