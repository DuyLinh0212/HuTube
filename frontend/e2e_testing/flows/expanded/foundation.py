"""Execute existing functional assertions afresh against independent fixture actors."""
import importlib
from flows.expanded.common import snapshot_module
from support.actor_cleanup import close_finished_auth_tabs

def run(suite,config,actors):
    snapshot_module(suite,__file__)
    close_finished_auth_tabs(suite)
    owner,member,admin=(actors[k] for k in ['owner','member','admin'])
    original=suite.case
    def fresh(actor,id,*args,**kwargs):
        return original(actor,'FULL-FOUNDATION-'+id,*args,**kwargs)
    suite.case=fresh
    try:
        journeys=[
          ('user.live_auth','run',(owner,admin)),
          ('user.live_auth_extra','run_negative',(owner,admin)),
          ('user.live_auth_extra','run',(owner,admin)),
          ('user.live_sessions','run',(owner,admin)),
          ('user.live_account','run',(owner,)),
          ('user.live_account','run_admin',(admin,)),
          ('user.live_account_extra','run',(owner,)),
          ('user.live_channel_validation','run',(owner,)),
          ('user.live_studio_settings','run',(owner,)),
          ('user.live_analytics','run',(owner,)),
          ('user.live_discovery','run',(member,)),
          ('user.live_library_extra','run',(member,)),
          ('user.live_playlists','run',(owner,member)),
          ('user.live_subscriptions','run',(owner,member)),
          ('user.live_plans','run',(owner,)),
          ('user.live_policy','run',(member,)),
          ('admin.live_catalog','run',(admin,owner,['taxonomy','plans','rbac'])),
          ('admin.live_videos','run',(admin,)),
          ('admin.live_users','run',(admin,owner)),
          ('admin.live_channels','run',(admin,owner)),
          ('admin.live_moderation_lists','run',(admin,)),
          ('admin.live_admin_upload','run',(admin,member)),
        ]
        for module,function,arguments in journeys:
            flow=importlib.import_module('flows.'+module)
            snapshot_module(suite,flow.__file__)
            try:
                getattr(flow,function)(suite,*arguments)
                if module in ('user.live_auth','user.live_auth_extra','user.live_sessions'):
                    close_finished_auth_tabs(suite)
            except Exception as flow_error:
                suite.report.setdefault('journey_errors',[]).append({'module':module,'function':function,'error_type':type(flow_error).__name__})
                def missing(entry,error=flow_error,module=module):
                    raise __import__('support.live_suite',fromlist=['PrerequisiteMissing']).PrerequisiteMissing('Journey '+module+' prerequisite failed: '+type(error).__name__)
                suite.case(owner,'PREREQUISITE-'+module.replace('.','-')+'-'+function,'RUN-PREREQUISITE','Unfinished '+module,'Executable journey prerequisites',missing,module='runner')
        from flows.expanded.discovery_deep import run as discovery_deep
        discovery_deep(suite,config,actors)
        from flows.expanded.auth_boundaries import run as auth_boundaries
        auth_boundaries(suite,config,actors)
        from flows.expanded.playlist_deep import run as playlist_deep
        playlist_deep(suite,config,actors)
        from flows.expanded.permissions_deep import run as permissions_deep
        permissions_deep(suite,config,actors)
        from flows.expanded.exports_deep import run as exports_deep
        exports_deep(suite,config,actors)
    finally:
        suite.case=original
