"""Retest the failed partial-upload branch without rerunning prior PASS cases."""
from flows.expanded.channel_clause_completion import run as run_clauses


def run(suite, config, actors):
    run_clauses(suite, config, actors, only_failed=True)
