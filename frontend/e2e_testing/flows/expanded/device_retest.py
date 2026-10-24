"""Fresh device retest after adapting desktop assumptions to responsive controls."""
from playwright.sync_api import expect
from flows.expanded.common import case,snapshot_module
from support.oversized_upload import reject_oversized


def run(suite,config,actors):
    snapshot_module(suite,__file__)
    from flows.expanded.branding_boundaries import run as branding_boundaries
    if not any(c['id'].startswith('FULL-CHANNEL-') and '-EXACT-MAX-SIZE' in c['id'] for c in suite.report['cases']):
        branding_boundaries(suite,config,actors)
    from flows.user import live_policy
    snapshot_module(suite,live_policy.__file__)
    original=suite.case
    def policy_case(actor,id,*args,**kwargs):return original(actor,'FULL-FOUNDATION-'+id,*args,**kwargs)
    suite.case=policy_case
    try:live_policy.run(suite,actors['member'])
    finally:suite.case=original
    from flows.expanded.user_pagination import run as user_pagination
    user_pagination(suite,config,actors)
    from flows.admin import live_catalog,live_videos
    snapshot_module(suite,live_catalog.__file__);snapshot_module(suite,live_videos.__file__)
    original=suite.case
    def foundation_case(actor,id,*args,**kwargs):return original(actor,'FULL-FOUNDATION-'+id,*args,**kwargs)
    suite.case=foundation_case
    try:
        live_catalog.run(suite,actors['admin'],actors['owner'],['taxonomy','rbac'])
        live_videos.run(suite,actors['admin'])
        from flows.expanded import playlist_deep
        playlist_deep.run(suite,config,actors)
    finally:suite.case=original
    if suite.input_device=='mobile':
        from flows.expanded import media_deep
        media_deep.run(suite,config,actors)
    from flows.admin import live_admin_upload
    snapshot_module(suite,live_admin_upload.__file__)
    original=suite.case
    def fresh(actor,id,*args,**kwargs):return original(actor,'FULL-FOUNDATION-'+id,*args,**kwargs)
    suite.case=fresh
    try:live_admin_upload.run(suite,actors['admin'],actors['member'])
    finally:suite.case=original
    owner=actors['owner'];p=owner['page'];channel=suite.api(owner,'get','/channels/me').json()
    cid=channel['channelId']
    for index,(kind,maximum) in enumerate([('avatar',5),('banner',10),('watermark',2)]):
        def oversized(entry,index=index,kind=kind,maximum=maximum):
            before=suite.api(owner,'get','/channels/me').json()
            suite.go(owner,'/channel/'+channel['handle']+'/customize','app-channel-settings-page')
            p.locator('.settings-tabs-nav .tab-btn').nth(1).click()
            payload={'name':'qc-oversized.png','mimeType':'image/png','buffer':b'0'*(maximum*1024*1024+1)}
            p.locator('.branding-tab-pane input[type=file]').nth(index).set_input_files(payload)
            expect(p.locator('app-result-notice[tone=error]')).to_be_visible()
            reject_oversized(suite,owner,'/channels/'+cid+'/'+kind,payload,entry)
            after=suite.api(owner,'get','/channels/me').json()
            fields=('name','handle','description','settings','avatarUrl','bannerUrl','watermarkUrl')
            assert all(after[k]==before[k] for k in fields)
            p.reload();expect(p.locator('#chName')).to_have_value(before['name'])
            persisted=suite.api(owner,'get','/channels/me').json()
            assert all(persisted[k]==before[k] for k in fields)
            entry['resource_ids']=[cid]
            entry['steps']=['Actual browser file input exceeds '+str(maximum)+'MiB; visible error, no success',
                'Read actual backend 4xx; if writer reset, independently read early size rejection (413 or explicit request-size 400)',
                'Exact metadata and branding URLs unchanged through API','Reload and repeated API read retain the original resource']
        case(suite,owner,'FOUNDATION-LIVE-CHANNEL-'+kind.upper()+'-INVALID-SIZE','U-CHANNEL.02','Reject oversized '+kind+' without mutation',oversized,'channel')
    from flows.expanded.branding_boundaries import run_account
    run_account(suite,config,actors)
