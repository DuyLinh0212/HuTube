from pathlib import Path
import sys
from tempfile import TemporaryDirectory
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from prepare_e2e_apt import configure_apt


class AptSourceTests(unittest.TestCase):
    def test_current_runner_mirrorlist_is_bypassed_for_packages_and_indexes(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            sources = root / "sources.list.d"
            sources.mkdir()
            ubuntu = sources / "ubuntu.sources"
            ubuntu.write_text("Types: deb\nURIs: mirror+file:/etc/apt/apt-mirrors.txt\n"
                              "Suites: noble noble-updates noble-backports noble-security\n"
                              "Components: main restricted universe multiverse\n"
                              "Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n")
            # Reproduce the runner layout that caused the ten-minute timeout.
            (root / "apt-mirrors.txt").write_text(
                "http://azure.archive.ubuntu.com/ubuntu/\tpriority:1\n"
                "https://archive.ubuntu.com/ubuntu/\tpriority:2\n")
            pgdg = sources / "pgdg.sources"
            pgdg_text = "Types: deb\nURIs: https://apt.postgresql.org/pub/repos/apt\nSuites: noble-pgdg\n"
            pgdg.write_text(pgdg_text)
            self.assertEqual(["ubuntu.sources"], configure_apt(root))
            actual = ubuntu.read_text()
            self.assertIn("URIs: https://archive.ubuntu.com/ubuntu/\n", actual)
            self.assertNotIn("mirror+file", actual)
            self.assertIn("noble-security", actual)
            self.assertIn("Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg", actual)
            self.assertEqual(pgdg_text, pgdg.read_text())
            self.assertEqual([], configure_apt(root), "Repeated setup must be idempotent")

    def test_legacy_lists_and_deb822_direct_mirrors_are_supported(self):
        with TemporaryDirectory() as directory:
            root = Path(directory)
            (root / "sources.list.d").mkdir()
            files = {root / "sources.list": "deb http://azure.archive.ubuntu.com/ubuntu/ noble main\n",
                     root / "sources.list.d/ubuntu.sources": "URIs: https://azure.archive.ubuntu.com/ubuntu\n",
                     root / "sources.list.d/extra.list": "deb mirror+file:/etc/apt/apt-mirrors.txt noble-updates universe\n"}
            for path, content in files.items():
                path.write_text(content)
            configure_apt(root)
            for path in files:
                self.assertIn("https://archive.ubuntu.com/ubuntu/", path.read_text())
                self.assertNotIn("azure.archive", path.read_text())
            config = (root / "apt.conf.d/99-hutube-ci").read_text()
            self.assertIn('APT::Install-Recommends "false";', config)
            self.assertIn('Acquire::https::Timeout "30";', config)


if __name__ == "__main__":
    unittest.main()
