import importlib.util
import json
import plistlib
import unittest
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('prepare_update', ROOT / 'Tools/prepare-update.py')
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)


class UpdateConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.info = plistlib.loads((ROOT / 'Info.plist').read_bytes())

    def test_only_signed_updates(self):
        self.assertTrue(self.info['SUVerifyUpdateBeforeExtraction'])
        self.assertTrue(self.info['SURequireSignedFeed'])
        self.assertEqual(self.info['SUSignedFeedFailureExpirationInterval'], 0)
        self.assertEqual(len(__import__('base64').b64decode(self.info['SUPublicEDKey'])), 32)

    def test_manual_install_and_no_telemetry(self):
        self.assertFalse(self.info['SUAutomaticallyUpdate'])
        self.assertFalse(self.info['SUAllowsAutomaticUpdates'])
        self.assertFalse(self.info['SUEnableSystemProfiling'])
        self.assertFalse(self.info['SUEnableJavaScript'])
        self.assertTrue(self.info['SUEnableAutomaticChecks'])
        self.assertEqual(self.info['SUScheduledCheckInterval'], 86400)

    def test_identity_and_compatibility(self):
        self.assertEqual(self.info['CFBundleIdentifier'], 'io.github.acemetric.sshomeworkmanager')
        self.assertEqual(self.info['LSMinimumSystemVersion'], '13.0')
        self.assertEqual(self.info['SUFeedURL'], 'https://acemetric.github.io/DDL-Manager/updates/appcast.xml')
        self.assertGreaterEqual(int(self.info['CFBundleVersion']), 2)

    def test_binary_dependency_is_pinned(self):
        lock = json.loads((ROOT / 'Config/Sparkle.json').read_text())
        self.assertEqual(lock['version'], '2.10.0')
        self.assertEqual(lock['sha256'], 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c')

    def test_reject_wrong_version_or_test_app(self):
        for change in ({'CFBundleVersion': '1'}, {'SUPublicEDKey': 'different'}, {'DDLTestRoot': '/synthetic'}, {'SURequireSignedFeed': False}):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory) / 'test.zip'
                with zipfile.ZipFile(archive, 'w') as package:
                    package.writestr('DDL-Manager.app/Contents/Info.plist', plistlib.dumps(self.info | change))
                with self.assertRaises(ValueError):
                    update.validate_archive(archive, self.info)

    def test_reject_extra_files_and_path_traversal(self):
        for extra in ('private-data.plist', '../secret', '/absolute'):
            with self.subTest(extra=extra), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory) / 'test.zip'
                with zipfile.ZipFile(archive, 'w') as package:
                    package.writestr('DDL-Manager.app/Contents/Info.plist', plistlib.dumps(self.info))
                    package.writestr(extra, 'synthetic')
                with self.assertRaises(ValueError):
                    update.validate_archive(archive, self.info)


if __name__ == '__main__':
    unittest.main()
