#!/usr/bin/env python3
"""Exercise the real Sparkle engine against loopback fixtures and isolated full AppKit apps."""
import datetime
import argparse
import functools
import http.server
import json
import plistlib
import os
import signal
import socket
import shutil
import subprocess
import threading
import time
import uuid
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ACCOUNT = 'io.github.acemetric.sshomeworkmanager.updates'
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', NS)
sparkle = ROOT / 'build/dependencies/Sparkle-2.10.0'
qa = ROOT / 'build/qa/update-integration'
qa.mkdir(parents=True, exist_ok=True)


class Handler(http.server.SimpleHTTPRequestHandler):
    scenario = ''
    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path.endswith('/appcast.xml') and self.scenario == 'disconnected':
            self.connection.close()
            return
        if self.path.endswith('/appcast.xml') and self.scenario == 'timeout':
            # Sparkle's appcast request must actually time out, not just receive HTTP 408.
            time.sleep(80)
            return
        if self.path.endswith('/update.zip') and self.scenario == 'interrupted-download':
            payload = Path(self.translate_path(self.path)).read_bytes()
            self.send_response(200)
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload[:4096])
            self.wfile.flush()
            self.connection.shutdown(socket.SHUT_RDWR)
            self.connection.close()
            return
        super().do_GET()


def run(*args):
    return subprocess.check_output([str(a) for a in args], stderr=subprocess.STDOUT, text=True).strip()


def sign(file):
    return run(sparkle / 'bin/sign_update', '--account', ACCOUNT, '-p', file)


def stop_test_processes(folder):
    """Only reap executables in this run's isolated app, including Sparkle helpers."""
    prefix = str(folder.resolve()) + '/DDLUpdateTest.app/Contents/'
    for sig in (signal.SIGTERM, signal.SIGKILL):
        listing = run('/bin/ps', '-axo', 'pid=,comm=')
        for line in listing.splitlines():
            pid, executable = line.strip().split(None, 1)
            if executable.startswith(prefix):
                try:
                    os.kill(int(pid), sig)
                except ProcessLookupError:
                    pass
        time.sleep(.3)


def fixture(name, base_url, scenario):
    folder = qa / (name + '-' + uuid.uuid4().hex[:8])
    folder.mkdir()
    data = folder / 'data'
    data.mkdir()
    bundle_id = 'io.github.ddl-manager.update-test.' + uuid.uuid4().hex
    keychain_service = bundle_id + '.github'
    info = plistlib.loads((ROOT / 'Info.plist').read_bytes())
    info.update(CFBundleIdentifier=bundle_id, CFBundleExecutable='DDLUpdateTest',
                CFBundleName="AM's Homework Helper 升级测试", CFBundleDisplayName="AM's Homework Helper 升级测试",
                DDLTestRoot=str(folder), DDLTestDataDirectory=str(data), DDLTestKeychainService=keychain_service,
                SUEnableAutomaticChecks=False, SUFeedURL=base_url + '/' + folder.name + '/appcast.xml',
                NSAppTransportSecurity={'NSAllowsLocalNetworking': True})
    task = {'id': 'synthetic-task', 'title': '升级保留模拟作业', 'subject': '模拟课程',
            'due': datetime.datetime(2026, 12, 20, 21), 'announcedDue': datetime.datetime(2026, 12, 21, 21),
            'leadDays': 1, 'reminderOffsets': [1440, 60, 0], 'priority': 1, 'completed': False, 'archived': False}
    course = {'fork': 'student/synthetic-course', 'upstream': 'teacher/synthetic-course', 'branch': 'main', 'enabled': False}
    for filename, value in [('tasks.plist', [task]), ('courses.plist', [course])]:
        (data / filename).write_bytes(plistlib.dumps(value))
    host = folder / 'DDLUpdateTest.app'
    for build, destination in [('2', host), ('3', folder / 'new/DDLUpdateTest.app')]:
        contents = destination / 'Contents'
        (contents / 'MacOS').mkdir(parents=True)
        (contents / 'Frameworks').mkdir()
        shutil.copy2(ROOT / 'build/tests/update-integration', contents / 'MacOS/DDLUpdateTest')
        run('/usr/bin/ditto', sparkle / 'Sparkle.framework', contents / 'Frameworks/Sparkle.framework')
        info['CFBundleVersion'] = build
        info['CFBundleShortVersionString'] = '1.1' if build == '2' else '1.2'
        (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
        run('/usr/bin/codesign', '--force', '--sign', '-', destination)
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', destination)
    run('/usr/bin/ditto', host, folder / 'baseline/DDLUpdateTest.app')
    archive = folder / 'update.zip'
    run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', folder / 'new/DDLUpdateTest.app', archive)
    signature = sign(archive)
    notes = folder / 'notes.md'
    notes.write_text('# 模拟更新\n\n用于验证自动更新，不是公开发布。\n')
    notes_signature = sign(notes)
    rss = ET.Element('rss', version='2.0')
    channel = ET.SubElement(rss, 'channel')
    ET.SubElement(channel, 'title').text = 'DDL local update QA'
    item = ET.SubElement(channel, 'item')
    ET.SubElement(item, 'title').text = 'Synthetic update'
    ET.SubElement(item, '{' + NS + '}version').text = '1' if scenario == 'older' else '3'
    ET.SubElement(item, '{' + NS + '}shortVersionString').text = '1.2'
    ET.SubElement(item, '{' + NS + '}minimumSystemVersion').text = '999.0' if scenario == 'incompatible' else '13.0'
    note = ET.SubElement(item, '{' + NS + '}releaseNotesLink', {'{' + NS + '}edSignature': notes_signature, 'length': str(notes.stat().st_size)})
    note.text = base_url + '/' + folder.name + '/notes.md'
    ET.SubElement(item, 'enclosure', {'url': base_url + '/' + folder.name + '/update.zip',
                                   'length': str(archive.stat().st_size), 'type': 'application/octet-stream',
                                   '{' + NS + '}edSignature': signature if scenario != 'wrong-signature' else 'A' * 86 + '=='})
    feed = folder / 'appcast.xml'
    feed.write_bytes(ET.tostring(rss, encoding='utf-8', xml_declaration=True))
    sign(feed)
    if scenario == 'tampered-feed':
        feed.write_bytes(feed.read_bytes().replace(b'Synthetic update', b'Modified update'))
    elif scenario == 'damaged-zip':
        payload = bytearray(archive.read_bytes()); payload[len(payload) // 2] ^= 1; archive.write_bytes(payload)
    elif scenario == 'offline':
        feed.unlink()
    return folder, host, keychain_service, bundle_id, task, course


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--scenarios', nargs='+', choices=['normal', 'wrong-signature', 'tampered-feed', 'damaged-zip', 'older', 'incompatible', 'offline', 'disconnected', 'timeout', 'interrupted-download'])
    args = parser.parse_args()
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(Handler, directory=str(qa)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    base_url = f'http://localhost:{server.server_port}'
    outcomes = []
    try:
        # Reuse one isolated application identity and signed archive. Only changed feeds need re-signing.
        folder, host, service, bundle, task, course = fixture('suite', base_url, 'normal')
        archive = folder / 'update.zip'
        feed = folder / 'appcast.xml'
        original_archive, original_feed = archive.read_bytes(), feed.read_bytes()
        for scenario in args.scenarios or ['normal', 'wrong-signature', 'tampered-feed', 'damaged-zip', 'older', 'incompatible', 'offline', 'disconnected', 'timeout', 'interrupted-download']:
            Handler.scenario = scenario
            if host.exists():
                shutil.rmtree(host)
            run('/usr/bin/ditto', folder / 'baseline/DDLUpdateTest.app', host)
            for marker in folder.glob('*.plist'):
                marker.unlink()
            archive.write_bytes(original_archive)
            feed.write_bytes(original_feed)
            if scenario in ('wrong-signature', 'older', 'incompatible'):
                rss = ET.fromstring(original_feed)
                item = rss.find('./channel/item')
                if scenario == 'wrong-signature':
                    item.find('enclosure').set('{' + NS + '}edSignature', 'A' * 86 + '==')
                elif scenario == 'older':
                    item.find('{' + NS + '}version').text = '1'
                else:
                    item.find('{' + NS + '}minimumSystemVersion').text = '999.0'
                feed.write_bytes(ET.tostring(rss, encoding='utf-8', xml_declaration=True))
                sign(feed)
            elif scenario == 'tampered-feed':
                feed.write_bytes(original_feed.replace(b'Synthetic update', b'Modified update'))
            elif scenario == 'damaged-zip':
                payload = bytearray(original_archive); payload[len(payload) // 2] ^= 1; archive.write_bytes(payload)
            elif scenario == 'offline':
                feed.unlink()
            log = open(folder / 'process.log', 'w')
            process = subprocess.Popen(['/usr/bin/open', '-n', '-W', str(host)], stdout=log, stderr=log)
            try:
                deadline = time.monotonic() + (90 if scenario == 'timeout' else 50)
                terminal = None
                while time.monotonic() < deadline:
                    terminal = next((p for p in [folder / 'relaunched.plist', folder / 'error.plist', folder / 'no-update.plist'] if p.exists()), None)
                    if terminal:
                        break
                    time.sleep(.15)
                if not terminal:
                    raise AssertionError(f'{scenario}: no terminal result; inspect {folder}')
                result = plistlib.loads(terminal.read_bytes())
                if scenario == 'normal':
                    assert terminal.name == 'relaunched.plist', result
                    assert result['version'] == '3' and result['tasks'] == 1
                    assert result['keychainPreserved'] and result['preferencePreserved']
                    assert result['task']['title'] == task['title'] and result['task']['announcedDue'] == task['announcedDue']
                    assert result['task']['reminderOffsets'] == task['reminderOffsets'] and result['courses'] == [course]
                    assert plistlib.loads((folder / 'waited.plist').read_bytes()) == {'paused': True, 'pending': True}
                    assert (folder / 'notes.plist').exists()
                elif scenario in ('older', 'incompatible'):
                    assert terminal.name == 'no-update.plist', result
                    assert not (folder / 'download.plist').exists()
                else:
                    assert terminal.name == 'error.plist', result
                    assert not (folder / 'relaunched.plist').exists()
                    assert plistlib.loads((host / 'Contents/Info.plist').read_bytes())['CFBundleVersion'] == '2'
                    assert not (folder / 'ready.plist').exists(), 'unverified archive became installable'
                    assert not (folder / 'extraction-progress.plist').exists(), 'unverified archive was extracted'
                    if scenario in ('wrong-signature', 'damaged-zip'):
                        assert any(code in result.get('codes', []) for code in (3001, 3002)), result
                    if scenario == 'timeout':
                        assert -1001 in result.get('codes', []), 'expected a real URL request timeout'
                    if scenario in ('disconnected', 'interrupted-download'):
                        assert -1005 in result.get('codes', []), 'expected connection loss'
                outcomes.append({'scenario': scenario, 'result': 'PASS', 'details': result if scenario != 'normal' else {'version': '3', 'dataPreserved': True, 'waitedForOperation': True}})
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    # The old process can exit before Sparkle launches the new copy.
                    process.terminate()
                print(f'PASS: real Sparkle {scenario}', flush=True)
            finally:
                stop_test_processes(folder)
                if process.poll() is None:
                    process.terminate()
                process.wait(timeout=5)
                log.close()
                subprocess.run(['/usr/bin/defaults', 'delete', bundle], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    finally:
        server.shutdown()
        if 'folder' in locals():
            stop_test_processes(folder)
        if 'service' in locals():
            subprocess.run(['/usr/bin/security', 'delete-generic-password', '-s', service, '-a', 'qa-preservation'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        report = folder / 'results.json' if 'folder' in locals() else qa / 'results.json'
        report.write_text(json.dumps(outcomes, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
