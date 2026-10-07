"""Real-socket regression for consecutive Auth and Web runners on Linux."""
import os
from pathlib import Path
import socket
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from run_local import assert_port_available


class RunnerPortsTests(unittest.TestCase):
    def listener(self):
        listener = socket.socket()
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(('127.0.0.1', 0))
        listener.listen()
        self.addCleanup(listener.close)
        return listener, listener.getsockname()[1]

    def test_rejects_running_listener(self):
        listener, port = self.listener()
        with self.assertRaisesRegex(RuntimeError, str(port)):
            assert_port_available(port)
        # The refused check must leave the existing service intact.
        with socket.create_connection(('127.0.0.1', port), timeout=2) as client:
            connection, _ = listener.accept()
            connection.close()

    def test_accepts_unused_port(self):
        listener, port = self.listener()
        listener.close()
        assert_port_available(port)

    @unittest.skipIf(os.name == 'nt', 'POSIX TIME_WAIT regression')
    def test_accepts_time_wait_after_previous_server_stops(self):
        listener, port = self.listener()
        with socket.create_connection(('127.0.0.1', port), timeout=2) as client:
            connection, _ = listener.accept()
            with connection:
                connection.shutdown(socket.SHUT_WR)
                self.assertEqual(client.recv(1), b'')
        listener.close()
        # Reproduce the old preflight failure before exercising the fix.
        with socket.socket() as old_probe:
            with self.assertRaises(OSError):
                old_probe.bind(('127.0.0.1', port))
        assert_port_available(port)


if __name__ == '__main__':
    unittest.main()
