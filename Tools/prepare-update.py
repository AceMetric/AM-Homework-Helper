#!/usr/bin/env python3
"""Prepare signed public update metadata locally. Never uploads or exports a private key."""
import argparse
import hashlib
import plistlib
import shutil
import subprocess
import xml.etree.ElementTree as ET
import zipfile
from pathlib import Path
from distribution import update_locations

ROOT = Path(__file__).resolve().parents[1]
ACCOUNT = 'io.github.acemetric.sshomeworkmanager.updates'
SPARKLE_NS = '{http://www.andymatuschak.org/xml-namespaces/sparkle}'


def validate_archive(archive, expected):
    app_name = expected['CFBundleName'] + '.app'
    with zipfile.ZipFile(archive) as package:
        for name in package.namelist():
            parts = Path(name).parts
            if '..' in parts or name.startswith('/') or (parts and parts[0] not in (app_name, '__MACOSX')):
                raise ValueError('更新 ZIP 只能包含配置指定的应用及其归档元数据。')
        bundled = plistlib.loads(package.read(f'{app_name}/Contents/Info.plist'))
        for key in ('CFBundleIdentifier', 'CFBundleName', 'CFBundleVersion', 'CFBundleShortVersionString', 'SUPublicEDKey', 'SUFeedURL', 'DDLRepositoryURL'):
            if bundled.get(key) != expected.get(key):
                raise ValueError(f'更新包与当前配置不一致：{key}')
        if not bundled.get('SURequireSignedFeed') or not bundled.get('SUVerifyUpdateBeforeExtraction'):
            raise ValueError('更新包必须保留完整签名验证。')
        if any(key.startswith('DDLTest') for key in bundled):
            raise ValueError('测试应用不能进入正式更新源。')


def prepare(notes, previous_feed=None):
    notes_bytes = notes.read_bytes()
    previous_bytes = previous_feed.read_bytes() if previous_feed else None
    info = plistlib.loads((ROOT / 'Info.plist').read_bytes())
    _, download_prefix, notes_prefix = update_locations(info)
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    archive = ROOT / f'build/releases/{info["DDLArchiveName"]}-{version}-macOS-arm64.zip'
    if not archive.is_file():
        raise SystemExit('先运行 zsh release.sh，生成通过检查的正式更新包。')
    validate_archive(archive, info)
    distribution = Path(subprocess.check_output(['python3', str(ROOT / 'Tools/prepare-sparkle.py')], text=True).strip())
    public = subprocess.check_output([str(distribution / 'bin/generate_keys'), '--account', ACCOUNT, '-p'], text=True).strip()
    if public != info['SUPublicEDKey']:
        raise SystemExit('钥匙串公钥与应用配置不匹配；不会生成或替换私钥。')
    if previous_feed:
        # Authenticate the previous feed before trusting its version or preserving entries.
        subprocess.run([str(distribution / 'bin/sign_update'), '--account', ACCOUNT, '--verify', str(previous_feed)], check=True)
        entries = ET.parse(previous_feed).findall('./channel/item')
        if any(int(item.findtext(SPARKLE_NS + 'version', '0')) >= int(build) for item in entries):
            raise SystemExit('构建号必须高于之前发布的所有构建号。')
    output = ROOT / 'build/releases/update'
    if output.exists():
        shutil.rmtree(output)
    output.mkdir()
    copied = output / archive.name
    shutil.copy2(archive, copied)
    copied.with_suffix('.md').write_bytes(notes_bytes)
    if previous_feed:
        (output / 'appcast.xml').write_bytes(previous_bytes)
    subprocess.run([str(distribution / 'bin/generate_appcast'), '--account', ACCOUNT,
                    '--maximum-deltas', '0', '--versions', str(build),
                    '--download-url-prefix', download_prefix,
                    '--release-notes-url-prefix', notes_prefix,
                    '-o', str(output / 'appcast.xml'), str(output)], check=True)
    subprocess.run([str(distribution / 'bin/sign_update'), '--account', ACCOUNT, '--verify', str(output / 'appcast.xml')], check=True)
    feed = ET.parse(output / 'appcast.xml')
    item = next(i for i in feed.findall('./channel/item') if i.findtext(SPARKLE_NS + 'version') == build)
    enclosure = item.find('enclosure')
    subprocess.run([str(distribution / 'bin/sign_update'), '--account', ACCOUNT, '--verify', str(copied), enclosure.attrib[SPARKLE_NS + 'edSignature']], check=True)
    note = item.find(SPARKLE_NS + 'releaseNotesLink')
    if note is None or SPARKLE_NS + 'edSignature' not in note.attrib:
        raise SystemExit('更新说明必须单独签名。')
    subprocess.run([str(distribution / 'bin/sign_update'), '--account', ACCOUNT, '--verify', str(copied.with_suffix('.md')), note.attrib[SPARKLE_NS + 'edSignature']], check=True)
    copied.with_suffix('.zip.sha256').write_text(hashlib.sha256(copied.read_bytes()).hexdigest() + '  ' + copied.name + '\n')
    subprocess.run(['python3', str(ROOT / 'Tools/security-audit.py'), '--artifacts', str(output),
                    '--ocr', str(ROOT / 'build/tests/privacy-ocr'), '--report', str(ROOT / 'build/update-audit.json')], cwd=ROOT, check=True)
    print(f'已准备本机签名更新：{output}。尚未上传。')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--notes', required=True, type=Path, help='公开 Markdown 更新说明')
    parser.add_argument('--previous-feed', type=Path, help='前一版已发布的签名清单')
    args = parser.parse_args()
    prepare(args.notes, args.previous_feed)
