"""Probe a newly installed broker across a container restart without touching application queues."""
import argparse
import base64
import json
import subprocess
import time
import uuid
from pathlib import Path
from urllib.request import Request, urlopen


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--env-file', type=Path, required=True)
    parser.add_argument('--container', default='dalitu-rabbitmq')
    args = parser.parse_args()
    values = dict(line.split('=', 1) for line in args.env_file.read_text().splitlines() if '=' in line)
    user, password = values['RABBITMQ_DEFAULT_USER'], values['RABBITMQ_DEFAULT_PASS']
    auth = base64.b64encode(f'{user}:{password}'.encode()).decode()
    queue = 'dalitu.install.probe.' + uuid.uuid4().hex

    def request(method, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        req = Request('http://127.0.0.1:15672/api/' + path, data=data, method=method,
                      headers={'Authorization': 'Basic ' + auth, 'Content-Type': 'application/json'})
        with urlopen(req, timeout=10) as response:
            payload = response.read()
        return json.loads(payload) if payload else None

    request('PUT', 'queues/dalitu/' + queue,
            {'durable': True, 'auto_delete': False, 'arguments': {'x-queue-type': 'quorum'}})
    try:
        result = request('POST', 'exchanges/dalitu/amq.default/publish', {
            'properties': {'delivery_mode': 2}, 'routing_key': queue,
            'payload': 'dalitu-broker-persistence-probe', 'payload_encoding': 'string'})
        assert result['routed'], 'Probe was not routed'
        subprocess.run(['sudo', '-n', 'docker', 'restart', args.container], check=True, stdout=subprocess.DEVNULL)
        deadline = time.monotonic() + 120
        while True:
            try:
                result = request('POST', 'queues/dalitu/' + queue + '/get', {
                    'count': 1, 'ackmode': 'ack_requeue_false', 'encoding': 'auto'})
                assert len(result) == 1 and result[0]['payload'] == 'dalitu-broker-persistence-probe'
                break
            except Exception:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(2)
        print(json.dumps({'durable_queue_survived_restart': True, 'persistent_message_survived_restart': True}))
    finally:
        request('DELETE', 'queues/dalitu/' + queue)


if __name__ == '__main__':
    main()
