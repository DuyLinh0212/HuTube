from flows.expanded.discovery_populated_category import run as run_clauses


def run(suite, config, actors):
    run_clauses(suite, config, actors, only_failed=True)
