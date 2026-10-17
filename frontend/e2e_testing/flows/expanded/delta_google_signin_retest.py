"""Only incomplete sign-in persistence; retain successful provider cancellation."""
from flows.expanded.delta_google_checkpoint import run as checkpoint


def run(suite, config, actors):
    checkpoint(suite, {**config, 'google_skip_cancel': True}, actors)
