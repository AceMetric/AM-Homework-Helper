"""Compressed pixels must not create privacy false positives; metadata remains inspected."""
import runpy
from pathlib import Path
import struct
import unittest
import zlib

AUDIT = runpy.run_path(str(Path(__file__).resolve().parent.parent / 'Tools/security-audit.py'))
SCAN = AUDIT['inspect']
GLOBALS = SCAN.__globals__


def chunk(kind, payload):
    return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload))


def png(kind, payload):
    return b'\x89PNG\r\n\x1a\n' + chunk(kind, payload) + chunk(b'IEND', b'')


class AuditTests(unittest.TestCase):
    def setUp(self):
        GLOBALS['findings'].clear()
        GLOBALS['ocr'] = None
        self.address = b'student@' + b'private.test'

    def test_compressed_pixel_bytes_do_not_count_as_privacy_text(self):
        SCAN(png(b'IDAT', self.address), 'preview.png')
        self.assertEqual(GLOBALS['findings'], set())

    def test_plain_metadata_is_still_checked(self):
        SCAN(png(b'tEXt', b'Author\0' + self.address), 'preview.png')
        self.assertIn(('preview.png', 'personal-email'), GLOBALS['findings'])

    def test_compressed_metadata_is_still_checked(self):
        SCAN(png(b'zTXt', b'Author\0\0' + zlib.compress(self.address)), 'preview.png')
        self.assertIn(('preview.png', 'personal-email'), GLOBALS['findings'])

    def test_credentials_are_checked_even_in_binary_payloads(self):
        fake = b'gh' + b'p_' + b'Z' * 40
        SCAN(png(b'IDAT', fake), 'preview.png')
        self.assertIn(('preview.png', 'github-token'), GLOBALS['findings'])

    def test_binary_url_detection_stops_at_string_boundary(self):
        SCAN(b'http://localhost:11434' + b'\0public-string@', 'app-binary')
        self.assertNotIn(('app-binary', 'url-credentials'), GLOBALS['findings'])
        credentials = b'https://' + b'synthetic-user' + b':' + b'fixture-only' + b'@example.invalid' + b'\0'
        SCAN(credentials, 'app-binary')
        self.assertIn(('app-binary', 'url-credentials'), GLOBALS['findings'])

    def test_jpeg_metadata_is_checked(self):
        payload = self.address
        data = b'\xff\xd8\xff\xfe' + struct.pack('>H', len(payload) + 2) + payload + b'\xff\xd9'
        SCAN(data, 'preview.jpg')
        self.assertIn(('preview.jpg', 'personal-email'), GLOBALS['findings'])

    def test_upstream_attribution_exemption_requires_exact_bytes(self):
        root = Path(__file__).resolve().parent.parent
        name = __import__("plistlib").loads((root / "Info.plist").read_bytes())["CFBundleName"]
        path = root / "build" / (name + ".app") / "Contents/Resources/Sparkle-LICENSE.txt"
        if not path.exists():
            self.skipTest('build the pinned dependency first')
        data = path.read_bytes()
        SCAN(data, 'artifact/Sparkle-LICENSE.txt')
        self.assertEqual(GLOBALS['findings'], set())
        SCAN(data + b'\n' + self.address, 'artifact/Sparkle-LICENSE.txt')
        self.assertIn(('artifact/Sparkle-LICENSE.txt', 'personal-email'), GLOBALS['findings'])


if __name__ == '__main__':
    unittest.main()
