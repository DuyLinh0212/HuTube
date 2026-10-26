#!/usr/bin/env python3
"""Configure the disposable Ubuntu E2E runner's APT downloads."""
import argparse
from pathlib import Path
import re


UBUNTU_MIRROR = re.compile(
    r"(?:mirror\+file:/etc/apt/apt-mirrors\.txt|https?://azure\.archive\.ubuntu\.com/ubuntu)/?"
)


def configure_apt(root):
    # Current runner images use mirror+file, whose priority:1 entry is Azure.
    # Rewrite the active source URI so APT cannot select that slow mirror again.
    sources = [root / "sources.list", *(root / "sources.list.d").glob("*.list"),
               *(root / "sources.list.d").glob("*.sources")]
    changed = []
    for path in sources:
        if not path.is_file():
            continue
        original = path.read_text(encoding="utf-8")
        updated = UBUNTU_MIRROR.sub("https://archive.ubuntu.com/ubuntu/", original)
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed.append(path.name)
    config = root / "apt.conf.d" / "99-hutube-ci"
    config.parent.mkdir(parents=True, exist_ok=True)
    config.write_text('Acquire::Retries "3";\n'
                      'Acquire::http::Timeout "30";\n'
                      'Acquire::https::Timeout "30";\n'
                      'APT::Install-Recommends "false";\n', encoding="utf-8")
    return changed


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apt-root", type=Path, default=Path("/etc/apt"))
    args = parser.parse_args()
    print("Configured E2E APT; updated source files:", configure_apt(args.apt_root))
