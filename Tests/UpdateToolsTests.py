import importlib.util
import json
import plistlib
import unittest
import sys
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'Tools'))
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
        self.assertEqual(self.info['SUFeedURL'], 'https://acemetric.github.io/AM-Homework-Helper/updates/appcast.xml')
        self.assertGreaterEqual(int(self.info['CFBundleVersion']), 2)

    def test_binary_dependency_is_pinned(self):
        lock = json.loads((ROOT / 'Config/Sparkle.json').read_text())
        self.assertEqual(lock['version'], '2.10.0')
        self.assertEqual(lock['sha256'], 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c')

    def test_distribution_addresses_share_one_configuration(self):
        repository, download, notes = update.update_locations(self.info)
        self.assertEqual(download, repository + '/releases/download/v' + self.info['CFBundleShortVersionString'] + '/')
        self.assertEqual(notes + 'appcast.xml', self.info['SUFeedURL'])

    def test_reject_mismatched_or_credential_distribution(self):
        for change in ({'SUFeedURL': 'https://acemetric.github.io/DDL-Manager/updates/appcast.xml'},
                       {'DDLRepositoryURL': 'https://' + 'user:password' + '@github.com/AceMetric/AM-Homework-Helper'},
                       {'DDLRepositoryURL': 'https://github.com/AceMetric/AM-Homework-Helper?token=synthetic'},
                       {'DDLRepositoryURL': 'https://github.com/AceMetric/../AM-Homework-Helper'},
                       {'DDLRepositoryURL': 'http://github.com/AceMetric/AM-Homework-Helper'}):
            with self.subTest(change=change), self.assertRaises(ValueError):
                update.update_locations(self.info | change)

    def test_reject_wrong_version_or_test_app(self):
        for change in ({'CFBundleVersion': '1'}, {'CFBundleName': 'Wrong App'}, {'SUPublicEDKey': 'different'}, {'DDLTestRoot': '/synthetic'}, {'SURequireSignedFeed': False}):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory) / 'test.zip'
                with zipfile.ZipFile(archive, 'w') as package:
                    package.writestr(self.info['CFBundleName'] + '.app/Contents/Info.plist', plistlib.dumps(self.info | change))
                with self.assertRaises(ValueError):
                    update.validate_archive(archive, self.info)

    def test_reject_extra_files_and_path_traversal(self):
        for extra in ('private-data.plist', '../secret', '/absolute'):
            with self.subTest(extra=extra), tempfile.TemporaryDirectory() as directory:
                archive = Path(directory) / 'test.zip'
                with zipfile.ZipFile(archive, 'w') as package:
                    package.writestr(self.info['CFBundleName'] + '.app/Contents/Info.plist', plistlib.dumps(self.info))
                    package.writestr(extra, 'synthetic')
                with self.assertRaises(ValueError):
                    update.validate_archive(archive, self.info)

    def test_accept_renamed_application(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'test.zip'
            with zipfile.ZipFile(archive, 'w') as package:
                package.writestr(self.info['CFBundleName'] + '.app/Contents/Info.plist', plistlib.dumps(self.info))
            update.validate_archive(archive, self.info)


class AuthenticationPackagingTests(unittest.TestCase):
    def test_public_auth_configuration(self):
        import tempfile, subprocess
        with tempfile.TemporaryDirectory() as directory:
            bundle = Path(directory) / 'Info.plist'
            bundle.write_bytes((ROOT / 'Info.plist').read_bytes())
            subprocess.run(['python3', str(ROOT / 'Tools/configure-bundle.py'), str(ROOT / 'Config/GitHubApp.plist'), str(bundle)], check=True)
            configured = plistlib.loads(bundle.read_bytes())
            self.assertTrue(configured['SSOAuthClientID'].startswith('Ov'))
            self.assertTrue(configured['SSGitHubClientID'].startswith('Iv'))
            self.assertFalse(any('secret' in key.lower() for key in configured))

    def test_askpass_bound_repository(self):
        import os, subprocess
        env = os.environ | {'SS_GIT_REPOSITORY':'github.com/student/course', 'SS_GIT_TOKEN':'fixture'}
        helper = str(ROOT / 'Tools/SSAskPass.sh')
        valid = subprocess.run(['/bin/sh', helper, "Password for 'https://" + "x-access-token@" + "github.com/Student/Course.git':"], env=env, capture_output=True, text=True)
        self.assertEqual((valid.returncode, valid.stdout.strip()), (0,'fixture'))
        for prompt in ["Password for 'https://github.com/teacher/course.git':", "Password for 'https://example.invalid/student/course.git':", "Password for 'https://github.com':"]:
            result = subprocess.run(['/bin/sh', helper, prompt], env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(result.stdout, '')


if __name__ == '__main__':
    unittest.main()
