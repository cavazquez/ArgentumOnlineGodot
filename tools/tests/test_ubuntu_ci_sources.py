"""Sólo cambian los URI; las suites y la verificación de Ubuntu permanecen."""
import unittest

from ubuntu_ci_sources import official_sources


SOURCE = """Types: deb
URIs: mirror+file:/etc/apt/apt-mirrors.txt
Suites: noble noble-updates noble-backports
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg

Types: deb
URIs: mirror+file:/etc/apt/security-mirrors.txt
Suites: noble-security
Components: main universe
Signed-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg
"""


class UbuntuSourcesTests(unittest.TestCase):
    def test_amd64_uses_https_and_preserves_every_non_uri_line(self):
        result = official_sources(SOURCE, "amd64")
        self.assertIn("URIs: https://archive.ubuntu.com/ubuntu/", result)
        self.assertIn("URIs: https://security.ubuntu.com/ubuntu/", result)
        self.assertEqual([line for line in SOURCE.splitlines() if not line.startswith("URIs:")],
                         [line for line in result.splitlines() if not line.startswith("URIs:")])

    def test_arm64_keeps_all_pockets_on_ubuntu_ports(self):
        result = official_sources(SOURCE, "arm64")
        self.assertEqual(result.count("URIs: https://ports.ubuntu.com/ubuntu-ports/"), 2)
        self.assertIn("Suites: noble-security", result)

    def test_unknown_arch_unsigned_or_unauthenticated_sources_are_rejected(self):
        for source, arch in ((SOURCE, "other"), (SOURCE.replace("Signed-By:", "Other-Key:"), "amd64"),
                             (SOURCE + "Trusted: yes\n", "amd64")):
            with self.subTest(arch=arch, source=source), self.assertRaises(ValueError):
                official_sources(source, arch)
