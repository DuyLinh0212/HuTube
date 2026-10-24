from flows.expanded.common import snapshot_module
from flows.expanded.fix17_retest import run_policy_and_player

def run(suite, config, actors):
    snapshot_module(suite, __file__)
    run_policy_and_player(suite, config, actors)
