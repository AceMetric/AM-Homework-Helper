#!/usr/bin/env python3
"""Extract only the unmodified executable and license from a verified official ZIP."""
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path

root = Path(__file__).resolve().parents[1]
lock = json.loads((root / 'Config/GitHubCLI.json').read_text())
cache = root / 'build/dependencies'
cache.mkdir(parents=True, exist_ok=True)
archive = cache / f"gh-{lock['version']}.zip"
if not archive.exists():
    partial = archive.with_suffix('.partial')
    subprocess.run(['/usr/bin/curl', '-fsSL', '--retry', '2', lock['url'], '-o', str(partial)], check=True)
    partial.replace(archive)
if hashlib.sha256(archive.read_bytes()).hexdigest() != lock['sha256']:
    raise SystemExit('GitHub CLI checksum mismatch; remove the cached ZIP and retry')
destination = cache / f"gh-{lock['version']}"
destination.mkdir(exist_ok=True)
with zipfile.ZipFile(archive) as package:
    for source, name in [('bin/gh', 'gh'), ('LICENSE', 'LICENSE')]:
        data = package.read(f"gh_{lock['version']}_macOS_arm64/{source}")
        target = destination / name
        if not target.exists() or target.read_bytes() != data:
            target.write_bytes(data)
    (destination / 'gh').chmod(0o755)
print(destination)
