from flows.expanded.common import snapshot_module
from flows.expanded.admin_deep import run as admin

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    suite.api(actors['admin'],'put','/admin/users/'+actors['target']['identity']['userId']+'/role',data={'roleCode':'user','reason':'Restore owned fixture after incomplete previous role test'})
    admin(suite,{**config,'only_rbac':True},actors)
    from flows.expanded.appeal_retest import run as appeal
    from flows.expanded.strike_retest import run as strike
    appeal(suite,config,actors)
    strike(suite,config,actors)
