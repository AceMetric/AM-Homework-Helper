#!/usr/bin/env python3
"""Build the macOS 13 SwiftUI bridge with the existing Command Line Tools."""
import hashlib
import pathlib
import subprocess

root = pathlib.Path(__file__).resolve().parents[1]
source = root / 'Sources/AMWorkspace.swift'
output = root / 'build/swiftui'
output.mkdir(parents=True, exist_ok=True)
compiler = subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip()
sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
version = subprocess.check_output([compiler, '--version'])
fingerprint = hashlib.sha256(source.read_bytes() + version).hexdigest()
marker = output / '.source-hash'
library = output / 'libAMUI.dylib'
header = output / 'AMUI-Swift.h'
if not (library.exists() and header.exists() and marker.exists() and marker.read_text() == fingerprint):
    subprocess.run([compiler, '-emit-library', '-emit-objc-header', '-emit-objc-header-path', str(header),
                    '-module-name', 'AMUI', '-target', 'arm64-apple-macosx13.0', '-sdk', sdk, '-O',
                    '-module-cache-path', str(root / 'build/module-cache'),
                    '-Xlinker', '-install_name', '-Xlinker', '@rpath/libAMUI.dylib',
                    str(source), '-o', str(library)], check=True)
    subprocess.run(['codesign', '--force', '--sign', '-', str(library)], check=True)
    marker.write_text(fingerprint)
print(output)
