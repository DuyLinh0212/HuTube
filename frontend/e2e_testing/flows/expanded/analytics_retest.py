from flows.expanded.common import snapshot_module
from flows.user.live_analytics import run as analytics

def run(suite,config,actors):
    snapshot_module(suite,__file__);original=suite.case
    from flows.expanded.resume_retest import run as resume
    resume(suite,config,actors)
    actors['member']['page'].goto('about:blank')
    def fresh(actor,id,*args,**kwargs):return original(actor,'FULL-FOUNDATION-'+id,*args,**kwargs)
    suite.case=fresh
    try:analytics(suite,actors['owner'])
    finally:suite.case=original
