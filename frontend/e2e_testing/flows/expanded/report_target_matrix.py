"""Close remaining allowed target/decision combinations, with real fixtures."""
from flows.expanded.common import snapshot_module
from flows.expanded.report_channel_actions import run as report_actions


def run(suite,config,actors):
    snapshot_module(suite,__file__)
    report_actions(suite,config,actors,decisions=[('rdismiss','dismiss'),('rwarn','warn'),('rhide','hide'),('rremove','remove'),('rescalate','escalate')])
    report_actions(suite,config,actors,target_kind='video')
