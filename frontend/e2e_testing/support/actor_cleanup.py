"""Release completed temporary journeys while retaining the six main actors."""


def close_finished_auth_tabs(suite):
    from flows.expanded.common import snapshot_module
    snapshot_module(suite,__file__)
    prefixes=('register-','guest-','wrong-password-','session-check-','auth-fault-')
    names={'registration-guest','auth-boundaries','member-admin-denial','home-guest'}
    closed=[]
    for name,actor in list(suite.actors.items()):
        if actor.get('released') or not (name.startswith(prefixes) or name in names):
            continue
        suite.release_actor(actor)
        closed.append(name)
    if closed:
        suite.report['cleanup'].append({'resource':'completed temporary browser tabs',
            'status':'closed','actors':closed,'retained':'Main owner/admin/member/target/reviewer contexts required by remaining flows'})
        suite.flush()
