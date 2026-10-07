"""Compatibility launcher; User and Admin suites have separate files/reports."""
import argparse
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--application', choices=['user', 'admin', 'all'], default='all')
    args, remaining = parser.parse_known_args()
    applications = ['user', 'admin'] if args.application == 'all' else [args.application]
    failed = False
    for application in applications:
        options = [item for item in remaining if application == 'user' or item != '--write-profile']
        result = subprocess.run([sys.executable, str(Path(__file__).with_name(application + '_account.py')), *options])
        failed = result.returncode != 0 or failed
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
