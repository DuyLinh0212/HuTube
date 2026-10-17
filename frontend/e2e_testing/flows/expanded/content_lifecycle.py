from flows.expanded.common import snapshot_module
from flows.expanded.media_deep import upload_fixture
from flows.user.live_media import edit_video
from flows.cross_app.live_moderation import run as moderation

def run(suite,config,actors):
    snapshot_module(suite,__file__);owner,member,admin=actors['owner'],actors['member'],actors['admin'];original=suite.case
    def fresh(actor,id,*args,**kwargs):return original(actor,'FULL-LIFECYCLE-'+id,*args,**kwargs)
    video=None
    suite.case=fresh
    try:
        video=upload_fixture(suite,owner,member,'LIFECYCLE')
        edit_video(suite,owner,video['videoId'],video['channelId'])
        moderation(suite,owner,member,admin,video['videoId'],video['channelId'])
    finally:
        suite.case=original
        if video:
            suite.api(owner,'delete','/videos/'+video['videoId'],expected=(200,204))
            suite.report['cleanup'].append({'resource':'new metadata/moderation lifecycle video','id':video['videoId'],'status':'deleted-test-fixture'})
