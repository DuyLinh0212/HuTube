"""Retest only the three guest CTAs that previously lost their return URL."""
from flows.expanded.guest_watch_actions import run as run_guest_actions


def run(suite, config, actors):
    run_guest_actions(suite, config, actors, only_failed=True)
