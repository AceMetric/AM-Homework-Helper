#!/usr/bin/env python3
"""Install the actual public Release with Sparkle; never open production user data."""
import argparse
import json
import os
import plistlib
import shutil
import subprocess
import time
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def run(*args):
    return subprocess.check_output([str(a) for a in args], stderr=subprocess.STDOUT, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path, help='Extracted, verified public application')
    parser.add_argument('--baseline-app', type=Path, help='Optional verified older public application for a real-version upgrade')
    args = parser.parse_args()
    info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
    assert int(info['CFBundleVersion']) > 1
    expected_build = info['CFBundleVersion']
    baseline_info = plistlib.loads((args.baseline_app / 'Contents/Info.plist').read_bytes()) if args.baseline_app else None
    if baseline_info:
        assert int(baseline_info['CFBundleVersion']) < int(expected_build)
        for key in ['CFBundleIdentifier', 'SUFeedURL', 'SUPublicEDKey']:
            assert baseline_info[key] == info[key]
    assert info['SUFeedURL'] == 'https://acemetric.github.io/AM-Homework-Helper/updates/appcast.xml'
    sparkle = ROOT / 'build/dependencies/Sparkle-2.10.0'
    qa = ROOT / 'build/qa/public-update' / uuid.uuid4().hex[:8]
    qa.mkdir(parents=True)
    binary = qa / 'driver'
    run('/usr/bin/clang', '-fobjc-arc', '-fblocks', '-Wall', '-Wextra', '-Werror', '-Wno-unused-parameter',
        '-mmacosx-version-min=13.0', '-framework', 'Cocoa', '-F' + str(sparkle), '-framework', 'Sparkle',
        '-Wl,-rpath,@executable_path/../Frameworks', ROOT / 'Tests/PublicUpdateIntegration.m', '-o', binary)
    results = []
    for mode, baseline in [('latest', expected_build), ('upgrade', baseline_info['CFBundleVersion'] if baseline_info else str(int(expected_build)-1))]:
        folder = qa / mode
        host = folder / "host/AM's Homework Helper.app"
        host.parent.mkdir(parents=True)
        run('/usr/bin/ditto', args.baseline_app if mode == 'upgrade' and args.baseline_app else args.app, host)
        host_info = (baseline_info if mode == 'upgrade' and baseline_info else info) | {'CFBundleVersion': baseline, 'SUEnableAutomaticChecks': False}
        (host / 'Contents/Info.plist').write_bytes(plistlib.dumps(host_info))
        run('/usr/bin/codesign', '--force', '--sign', '-', host)
        driver = folder / 'PublicUpdateTest.app'
        contents = driver / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'Frameworks').mkdir()
        shutil.copy2(binary, contents / 'MacOS/PublicUpdateTest')
        run('/usr/bin/ditto', sparkle / 'Sparkle.framework', contents / 'Frameworks/Sparkle.framework')
        bundle = 'io.github.ddl-manager.public-update-test.' + uuid.uuid4().hex
        (contents / 'Info.plist').write_bytes(plistlib.dumps({
            'CFBundleIdentifier': bundle, 'CFBundleExecutable': 'PublicUpdateTest', 'CFBundlePackageType': 'APPL',
            'CFBundleName': 'Public Update Test', 'CFBundleVersion': '1', 'LSUIElement': True,
            'DDLPublicTestRoot': str(folder), 'DDLPublicTestMode': mode, 'DDLPublicExpectedBuild': expected_build}))
        run('/usr/bin/codesign', '--force', '--sign', '-', driver)
        # Sparkle settings use the host domain. Preserve only its updater preference keys;
        # no task/account preferences or credentials are read or copied.
        preferences = folder / 'updater-preferences.plist'
        run(contents / 'MacOS/PublicUpdateTest', '--save-preferences', info['CFBundleIdentifier'], preferences)
        with (folder / 'process.log').open('w') as log:
            proc = subprocess.Popen(['/usr/bin/open', '-n', '-W', str(driver)], stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + 150
                while time.monotonic() < deadline and not (folder / 'result.plist').exists() and not (folder / 'error.plist').exists():
                    time.sleep(.2)
                error = folder / 'error.plist'
                if error.exists():
                    raise AssertionError(plistlib.loads(error.read_bytes()))
                result = plistlib.loads((folder / 'result.plist').read_bytes())
                assert result['version'] == expected_build, result
                if mode == 'latest':
                    assert result['noUpdate'] and not (folder / 'download.plist').exists()
                else:
                    assert result['reopened'] and (folder / 'notes.plist').exists()
                    assert (folder / 'ready.plist').exists()
                    assert (host / 'Contents/MacOS/DDLManager').read_bytes() == (args.app / 'Contents/MacOS/DDLManager').read_bytes()
                    assert plistlib.loads((host / 'Contents/Info.plist').read_bytes()) == info
                    run('/usr/bin/codesign', '--verify', '--deep', '--strict', host)
                results.append({'scenario': mode, 'result': 'PASS', 'details': result})
                print('PASS: public HTTPS Sparkle ' + mode, flush=True)
            finally:
                if proc.poll() is None:
                    proc.terminate()
                listing = run('/bin/ps', '-axo', 'pid=,comm=')
                for line in listing.splitlines():
                    pid, executable = line.strip().split(None, 1)
                    if executable.startswith(str(folder) + '/'):
                        try:
                            os.kill(int(pid), 15)
                        except ProcessLookupError:
                            pass
                run(contents / 'MacOS/PublicUpdateTest', '--restore-preferences', info['CFBundleIdentifier'], preferences)
                subprocess.run(['/usr/bin/defaults', 'delete', bundle], capture_output=True)
        (qa / 'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
