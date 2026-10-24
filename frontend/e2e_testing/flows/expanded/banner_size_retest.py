from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module

def run(suite,config,actors):
    snapshot_module(suite,__file__);owner=actors['owner'];channel=suite.api(owner,'get','/channels/me').json();cid=channel['channelId'];p=owner['page']
    def oversized(entry):
        before=suite.api(owner,'get','/channels/me').json();suite.go(owner,'/channel/'+channel['handle']+'/customize','app-channel-settings-page');p.locator('.settings-tabs-nav .tab-btn').nth(1).click()
        payload={'name':'qc-oversized.png','mimeType':'image/png','buffer':b'0'*(10*1024*1024+1)}
        p.locator('.branding-tab-pane input[type=file]').nth(1).set_input_files(payload);expect(p.locator('app-result-notice[tone=error]')).to_be_visible()
        try:suite.api(owner,'post','/channels/'+cid+'/banner',multipart={'file':payload},expected=(400,413,415,422))
        except RuntimeError as error:
            if 'ECONNRESET' not in str(error):raise
            entry['backend_transport_observation']='Kestrel refused oversized multipart by connection reset; no success response'
        after=suite.api(owner,'get','/channels/me').json();assert all(after[k]==before[k] for k in ('avatarUrl','bannerUrl','watermarkUrl'))
        p.reload();expect(p.locator('#chName')).to_have_value(before['name'])
        entry['input_data']={'bytes':len(payload['buffer']),'maximum_bytes':10*1024*1024};entry['resource_ids']=[cid]
        entry['steps']=['Actual browser banner input exceeds 10MiB','Visible error and no false success','Actual backend denies oversized multipart by 4xx or documented Kestrel reset','API remains reachable and all stored branding URLs unchanged','Reload preserves original channel']
    case(suite,owner,'FOUNDATION-LIVE-CHANNEL-BANNER-INVALID-SIZE','U-CHANNEL.02','Oversized banner cannot mutate branding',oversized,'channel')
