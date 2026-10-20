from flows.expanded.discovery_focus_scroll import run as run_scroll


def run(suite, config, actors):
    run_scroll(suite, config, actors, only_creator=True)
