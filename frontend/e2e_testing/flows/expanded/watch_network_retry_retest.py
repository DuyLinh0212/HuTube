"""Retest only the previously failed playback-request recovery branch."""
from flows.expanded.watch_rendition_recovery import run as run_recovery


def run(suite, config, actors):
    run_recovery(suite, {**config, 'watch_network_only': True}, actors)
