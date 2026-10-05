#!/usr/bin/env python3
"""Fetch the pinned binary distribution; never download an unpinned latest release."""
import hashlib
import json
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
lock = json.loads((root / 'Config/Sparkle.json').read_text())
cache = root / 'build/dependencies'
cache.mkdir(parents=True, exist_ok=True)
archive = cache / f"Sparkle-{lock['version']}.tar.xz"
if not archive.exists():
    partial = archive.with_suffix('.partial')
    subprocess.run(['/usr/bin/curl', '-fsSL', '--retry', '2', lock['url'], '-o', str(partial)], check=True)
    partial.replace(archive)
if hashlib.sha256(archive.read_bytes()).hexdigest() != lock['sha256']:
    raise SystemExit('Sparkle checksum mismatch; remove the cached archive and retry')
distribution = cache / f"Sparkle-{lock['version']}"
marker = distribution / '.verified'
if not marker.exists() or marker.read_text() != lock['sha256']:
    # Only the authenticated, pinned upstream archive is extracted.
    distribution.mkdir(exist_ok=True)
    subprocess.run(['/usr/bin/tar', '-xJf', str(archive), '-C', str(distribution)], check=True)
    (distribution / '.verified').write_text(lock['sha256'])
print(distribution)
