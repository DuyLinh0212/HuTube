from flows.expanded.watch_comment_collection import run as run_collection


def run(suite, config, actors):
    run_collection(suite, config, actors, only_pagination=True)
