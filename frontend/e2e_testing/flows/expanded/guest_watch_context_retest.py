from flows.expanded.guest_watch_actions import run as run_actions


def run(suite, config, actors):
    run_actions(suite, config, actors, only_failed=True)
