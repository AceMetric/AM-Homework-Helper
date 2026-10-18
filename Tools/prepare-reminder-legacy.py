#!/usr/bin/env python3
"""Preserve verified original notification identities; deduplicate their sealed files.

Only pinned public releases of this app are accepted. Original host signatures
are retained, never rewritten. Nothing here launches a historical application.
"""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import plistlib
import stat
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PINS = ROOT / 'Config/ReminderLegacy.json'
CACHE = ROOT / 'build/dependencies/reminder-legacy'

def digest(data):
    return hashlib.sha256(data).hexdigest()

def prepare():
    config = json.loads(PINS.read_text())
    assert config['format'] == 1 and config['bundleID'] == 'io.github.acemetric.sshomeworkmanager'
    CACHE.mkdir(parents=True, exist_ok=True)
    capsule = CACHE / 'identities.zip'
    key = digest(PINS.read_bytes() + Path(__file__).read_bytes())
    if (CACHE / 'complete.json').exists() and capsule.exists():
        state = json.loads((CACHE / 'complete.json').read_text())
        if state.get('pins') == key and state.get('capsule') == digest(capsule.read_bytes()):
            return capsule

    def archive(row):
        url = row['url']
        if not url.startswith('https://github.com/AceMetric/AM-Homework-Helper/releases/download/v' + row['version'] + '/') or len(row['sha256']) != 64:
            raise ValueError('Untrusted notification migration release')
        destination = CACHE / Path(url).name
        local = ROOT / 'build/releases' / Path(url).name
        for candidate in (destination, local):
            if candidate.exists() and digest(candidate.read_bytes()) == row['sha256']:
                return row, candidate
        with urllib.request.urlopen(url, timeout=90) as response:
            payload = response.read()
        if digest(payload) != row['sha256']:
            raise ValueError('Historical release hash mismatch: ' + row['version'])
        temporary = destination.with_suffix('.tmp')
        temporary.write_bytes(payload)
        temporary.replace(destination)
        return row, destination

    blobs = {}; hosts = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        archives = list(pool.map(archive, config['releases']))
    for row, path in archives:
        files = []
        with zipfile.ZipFile(path) as package:
            names = [n for n in package.namelist() if n.endswith('.app/Contents/Info.plist') and not n.startswith('__MACOSX') and '/Frameworks/' not in n]
            if len(names) != 1:
                raise ValueError('Unexpected application archive')
            info = plistlib.loads(package.read(names[0]))
            if info['CFBundleIdentifier'] != config['bundleID'] or info['CFBundleShortVersionString'] != row['version']:
                raise ValueError('Historical application identity mismatch')
            prefix = names[0][:-len('Contents/Info.plist')]
            for item in package.infolist():
                if not item.filename.startswith(prefix) or item.is_dir():
                    continue
                relative = item.filename[len(prefix):]
                parts = PurePosixPath(relative)
                if parts.is_absolute() or '..' in parts.parts or not relative.startswith('Contents/'):
                    raise ValueError('Unsafe historical archive path')
                data = package.read(item); sha = digest(data)
                mode = (item.external_attr >> 16) or (stat.S_IFREG | 0o644)
                if stat.S_ISLNK(mode):
                    target = data.decode()
                    normalized = os.path.normpath(str(parts.parent / target))
                    if target.startswith('/') or normalized.startswith('../'):
                        raise ValueError('Unsafe historical archive symlink')
                elif not stat.S_ISREG(mode):
                    raise ValueError('Unsupported historical archive entry')
                blobs.setdefault(sha, data)
                files.append({'path':relative,'blob':sha,'mode':mode & 0o777,'link':stat.S_ISLNK(mode)})
            hosts.append({'version':row['version'],'executable':info['CFBundleExecutable'],'files':files})
    temporary = capsule.with_suffix('.tmp')
    with zipfile.ZipFile(temporary, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=9) as package:
        def member(name, data):
            item = zipfile.ZipInfo(name, (2020,1,1,0,0,0))
            item.compress_type = zipfile.ZIP_DEFLATED
            item.external_attr = (stat.S_IFREG | 0o644) << 16
            package.writestr(item, data, compresslevel=9)
        member('manifest.json', json.dumps({'format':1,'bundleID':config['bundleID'],'hosts':hosts}, separators=(',',':')))
        for sha, data in sorted(blobs.items()):
            member('blobs/' + sha, data)
    temporary.replace(capsule)
    (CACHE / 'complete.json').write_text(json.dumps({'pins':key,'capsule':digest(capsule.read_bytes())}))
    return capsule

if __name__ == '__main__':
    print(prepare())
