#!/usr/bin/env python3
"""Exercise real macOS deny-write + keychain IPC with a disposable synthetic item."""
import os
import subprocess
import tempfile
import uuid
from pathlib import Path

keychains=str(Path.home() / 'Library/Keychains').replace('\\', '\\\\').replace('"', '\\"')
profile = '(version 1)(allow default)(deny file-write*)(allow file-write* (literal "/dev/null") (subpath "'+keychains+'"))'
service = 'io.github.acemetric.sshomeworkmanager.qa.cli.' + str(uuid.uuid4())
with tempfile.TemporaryDirectory(prefix='am-cli-security-') as folder:
    denied = Path(folder) / 'hosts.yml'
    result = subprocess.run(['/usr/bin/sandbox-exec', '-p', profile, '/bin/sh', '-c', 'echo synthetic-credential > "$1"', 'fixture', str(denied)], capture_output=True)
    if result.returncode == 0 or denied.exists():
        raise SystemExit('FAIL: credential-file fallback was not denied')
    # The official library writes via security -i stdin, never token process args.
    command = f'add-generic-password -U -s {service} -a fixture -w go-keyring-base64:c3ludGhldGlj\n'
    try:
        result = subprocess.run(['/usr/bin/sandbox-exec', '-p', profile, '/usr/bin/security', '-i'], input=command.encode(), capture_output=True, timeout=30)
        read = subprocess.run(['/usr/bin/security', 'find-generic-password', '-s', service, '-a', 'fixture', '-w'], capture_output=True, timeout=30)
        if result.returncode != 0 or read.returncode != 0 or read.stdout.strip() != b'go-keyring-base64:c3ludGhldGlj':
            print('storage exit',result.returncode,'lookup exit',read.returncode);print(result.stderr.decode());print(read.stderr.decode());raise SystemExit('FAIL: keychain IPC under write protection unavailable; login must fail closed')
        if list(Path(folder).iterdir()):
            raise SystemExit('FAIL: filesystem credential created')
    finally:
        subprocess.run(['/usr/bin/security', 'delete-generic-password', '-s', service, '-a', 'fixture'], capture_output=True)
print('PASS: macOS denies plaintext fallback while allowing official keychain stdin storage; disposable item removed')
