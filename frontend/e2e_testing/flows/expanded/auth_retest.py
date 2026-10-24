from flows.expanded.common import snapshot_module
from flows.expanded.auth_boundaries import run as auth

def run(suite,config,actors):
    snapshot_module(suite,__file__);original=suite.case
    def fresh(actor,id,*args,**kwargs):return original(actor,'FULL-FOUNDATION-'+id,*args,**kwargs)
    suite.case=fresh
    try:auth(suite,config,actors)
    finally:suite.case=original
