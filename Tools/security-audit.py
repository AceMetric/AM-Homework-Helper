#!/usr/bin/env python3
"""Local, redacted release audit. Never emits matched values or reads the Keychain."""
import argparse
import io
import json
import hashlib
from pathlib import Path
import plistlib
import re
import subprocess
import struct
import zlib
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parent.parent
PATTERNS = {
    'private-key': rb'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----',
    'github-token': rb'(?:gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,})',
    'cloud-token': rb'(?:AKIA|ASIA)[A-Z0-9]{16}|sk-(?:proj-)?[A-Za-z0-9_-]{24,}',
    'secret-value': rb'''(?i)["']?(?:api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|password|aws_secret_access_key)["']?\s*[:=]\s*["'][A-Za-z0-9_./+=-]{12,}["']''',
    'url-credentials': rb'https?://[^\x00\s/<>"\']+:[^\x00\s/<>"\']+@',
    'personal-home-path': rb'/Users/(?!Shared(?:/|$)|USER(?:/|$)|username(?:/|$))[A-Za-z0-9_.-]+/',
    'personal-email': rb'(?i)(?<![A-Z0-9_.+-])(?!(?:git@github\.com|[A-Z0-9_]+@2x\.png)\b)[A-Z0-9_.+-]+@(?![A-Z0-9.-]*(?:example\.(?:com|org)|\.invalid|noreply\.github\.com|users\.noreply\.github\.com)\b)[A-Z0-9.-]+\.[A-Z]{2,}',
}
REGEXES = {k: re.compile(v) for k, v in PATTERNS.items()}
SENSITIVE_NAMES = re.compile(r'(?i)(?:^|/)(?:\.env(?:\.(?!example$|sample$|template$)[^/]+)?|id_rsa|id_ed25519|\.netrc|credentials(?:\.json)?)(?:$|/)|\.(?:pem|p12|pfx|key)$')
findings = set()
counts = {'files': 0, 'history_objects': 0, 'archives': 0, 'images_ocr': 0, 'legacy_commit_email_objects': 0}
seen = set()
# Official, immutable GitHub CLI contains public upstream crypto fixtures and contacts.
# Accept only the exact signed distribution bytes; any modification is scanned normally.
PINNED_PUBLIC_BINARY = {'gh': 'aa97dfb4a82f7c56063cdcbfaa39a738b923c1bdca29bd5a041b8e959ca38e04'}
ocr = None
# Exact upstream attribution text, obtained from the pinned Sparkle 2.10.0 distribution.
# Only its published author email is exempt; any changed byte or credential remains checked.
PUBLIC_ATTRIBUTION = {'Sparkle-LICENSE.txt': '389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe'}


def git(*args):
    return subprocess.check_output(['/usr/bin/git', *args], cwd=ROOT)


def image_metadata(data):
    """Privacy text lives in image metadata/OCR, not compressed pixel bytes."""
    chunks = []
    if data.startswith(b'\x89PNG\r\n\x1a\n'):
        position = 8
        while position + 12 <= len(data):
            size = struct.unpack('>I', data[position:position + 4])[0]
            kind = data[position + 4:position + 8]
            payload = data[position + 8:position + 8 + size]
            if len(payload) != size:
                raise ValueError('truncated PNG')
            if kind == b'tEXt':
                chunks.append(payload)
            elif kind == b'zTXt':
                keyword, rest = payload.split(b'\0', 1)
                chunks.append(keyword + b' ' + zlib.decompress(rest[1:]))
            elif kind == b'iTXt':
                keyword, rest = payload.split(b'\0', 1)
                compressed = rest[0]
                language, translated, text = rest[2:].split(b'\0', 2)
                chunks.append(keyword + b' ' + language + b' ' + translated + b' ' + (zlib.decompress(text) if compressed else text))
            elif kind == b'eXIf':
                chunks.append(payload)
            position += 12 + size
            if kind == b'IEND':
                break
    elif data.startswith(b'\xff\xd8'):
        position = 2
        while position + 4 <= len(data):
            if data[position] != 0xff:
                break
            marker = data[position + 1]
            if marker in (0xda, 0xd9):  # Entropy-coded scan / end of image.
                break
            size = struct.unpack('>H', data[position + 2:position + 4])[0]
            if size < 2 or position + 2 + size > len(data):
                raise ValueError('invalid JPEG segment')
            if 0xe0 <= marker <= 0xef or marker == 0xfe:
                chunks.append(data[position + 4:position + 2 + size])
            position += 2 + size
    return chunks


def inspect(data, label, depth=0, commit=False):
    counts['files'] += 1
    if SENSITIVE_NAMES.search(label):
        findings.add((label, 'credential-file'))
    if PINNED_PUBLIC_BINARY.get(label.rsplit('/', 1)[-1]) == hashlib.sha256(data).hexdigest():
        counts['verified_official_binaries'] = counts.get('verified_official_binaries', 0) + 1
        return
    texts = [data]
    try:
        if data.startswith(b'bplist') or data.startswith(b'<?xml') and b'<plist' in data[:250]:
            texts.append(json.dumps(plistlib.loads(data), default=str, ensure_ascii=False).encode())
        if data.startswith((b'\xff\xfe', b'\xfe\xff')):
            texts.append(data.decode('utf-16').encode())
    except (ValueError, UnicodeError, TypeError, plistlib.InvalidFileException):
        findings.add((label, 'unreadable-structured-file'))
    privacy_texts = texts
    if data.startswith((b'\x89PNG\r\n', b'\xff\xd8\xff')):
        try:
            privacy_texts = image_metadata(data)
        except (ValueError, IndexError, zlib.error):
            findings.add((label, 'unreadable-image-metadata'))
            privacy_texts = []
    elif data.startswith(b'PK\x03\x04'):
        privacy_texts = []  # ZIP entries are scanned after decompression below.
    for category, regex in REGEXES.items():
        if category == 'personal-email' and PUBLIC_ATTRIBUTION.get(label.rsplit('/', 1)[-1]) == hashlib.sha256(data).hexdigest():
            continue
        eligible = privacy_texts if category in ('personal-email', 'personal-home-path') else texts
        if any(regex.search(text) for text in eligible):
            if category == 'personal-email' and commit:
                counts['legacy_commit_email_objects'] += 1
            else:
                findings.add((label, category))
    if data.startswith(b'PK\x03\x04'):
        counts['archives'] += 1
        if depth >= 4:
            findings.add((label, 'archive-depth-limit'))
            return
        try:
            with zipfile.ZipFile(io.BytesIO(data)) as archive:
                if sum(item.file_size for item in archive.infolist()) > 200 * 1024 * 1024:
                    findings.add((label, 'archive-size-limit'))
                    return
                for item in archive.infolist():
                    if not item.is_dir():
                        inspect(archive.read(item), label + '!' + item.filename, depth + 1)
        except (zipfile.BadZipFile, RuntimeError, OSError):
            findings.add((label, 'unreadable-archive'))
    if data.startswith((b'\x89PNG\r\n', b'\xff\xd8\xff')) and ocr:
        with tempfile.NamedTemporaryFile(suffix='.png') as image:
            image.write(data)
            image.flush()
            result = subprocess.run([str(ocr), image.name], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
            counts['images_ocr'] += 1
            if result.returncode:
                findings.add((label, 'ocr-failed'))
            else:
                # Output remains in process memory; inspect only for categories.
                for category, regex in REGEXES.items():
                    if regex.search(result.stdout):
                        findings.add((label, 'image-' + category))


def main():
    global ocr
    parser = argparse.ArgumentParser()
    parser.add_argument('--history', action='store_true')
    parser.add_argument('--artifacts', nargs='*', default=[])
    parser.add_argument('--ocr', type=Path)
    parser.add_argument('--report', type=Path)
    args = parser.parse_args()
    ocr = args.ocr.resolve() if args.ocr else None
    if ocr and not ocr.is_file():
        parser.error('OCR executable not built; run zsh verify-course-ui.sh first')
    names = git('ls-files', '-z', '--cached', '--others', '--exclude-standard').split(b'\0')
    for name in names:
        if not name:
            continue
        path = ROOT / name.decode()
        if path.is_file():
            inspect(path.read_bytes(), path.relative_to(ROOT).as_posix())
    if args.history:
        object_names = git('rev-list', '--objects', '--all').splitlines()
        process = subprocess.Popen(['/usr/bin/git', 'cat-file', '--batch'], cwd=ROOT,
                                   stdin=subprocess.PIPE, stdout=subprocess.PIPE)
        for entry in object_names:
            sha = entry.split(b' ', 1)[0]
            if sha in seen:
                continue
            seen.add(sha)
            process.stdin.write(sha + b'\n')
            process.stdin.flush()
            header = process.stdout.readline().split()
            if len(header) != 3:
                findings.add(('history/' + sha.decode(), 'missing-object'))
                continue
            kind = header[1]
            size = int(header[2])
            data = process.stdout.read(size)
            process.stdout.read(1)
            counts['history_objects'] += 1
            if kind in (b'blob', b'commit', b'tag'):
                name = entry.split(b' ', 1)[1].decode(errors='replace') if b' ' in entry else kind.decode()
                inspect(data, 'history/' + sha[:12].decode() + '/' + name, commit=kind == b'commit')
        process.stdin.close()
        if process.wait() != 0:
            findings.add(('history', 'batch-read-failed'))
    for artifact in args.artifacts:
        path = Path(artifact).resolve()
        if not path.exists():
            findings.add((str(path.name), 'missing-artifact'))
        elif path.is_dir():
            for file in path.rglob('*'):
                if file.is_file():
                    inspect(file.read_bytes(), 'artifact/' + path.name + '/' + file.relative_to(path).as_posix())
        else:
            inspect(path.read_bytes(), 'artifact/' + path.name)
    report = {'counts': counts, 'findings': [{'location': p, 'category': c} for p, c in sorted(findings)],
              'ocr_enabled': bool(ocr), 'status': 'pass' if not findings else 'needs-review'}
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    # File names only; no matching secrets or author emails.
    print(json.dumps(report, ensure_ascii=False))
    return bool(findings)


if __name__ == '__main__':
    raise SystemExit(main())
