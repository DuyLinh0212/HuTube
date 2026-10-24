from flows.expanded.plan_status_denial import run as run_status


def run(suite, config, actors):
    run_status(suite, config, actors, statuses=('archived',))
