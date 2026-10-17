"""Retest the single category case after correcting the harness endpoint."""
from flows.expanded.delta_admin_videos import run as videos


def run(suite, config, actors):
    videos(suite, {**config, 'delta_admin_category_only': True}, actors)
