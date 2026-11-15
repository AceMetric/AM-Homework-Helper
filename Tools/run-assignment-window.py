#!/usr/bin/env python3
"""Package the visible fixture with its real renderer; never use personal storage."""
import argparse
from pathlib import Path
import plistlib
import subprocess
import time

root = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--keep-open', action='store_true')
args = parser.parse_args()
folder = root / 'build.noindex/120/assignment-window'
app = folder / 'AM Layout Review.app'
contents = app / 'Contents'
(contents / 'MacOS').mkdir(parents=True, exist_ok=True)
data = folder / 'data'
data.mkdir(exist_ok=True)
log = folder / 'result.log'
log.unlink(missing_ok=True)
subprocess.run(['ditto', str(root / 'build/tests/AssignmentWorkspaceUsage'),
                str(contents / 'MacOS/WorkspaceVisualReview')], check=True)
# Launch Services doesn't preserve the repository working directory. The visible
# package must carry the same rendering assets as the release application.
subprocess.run(['ditto', str(root / 'build/deps/renderer/public'),
                str(contents / 'Resources/Renderer')], check=True)
info = {
    'CFBundleIdentifier': 'io.github.ddl-manager.layout-review-120',
    'CFBundleExecutable': 'WorkspaceVisualReview', 'CFBundleName': 'AM Layout Review',
    'CFBundlePackageType': 'APPL', 'CFBundleVersion': '52',
    'NSPrincipalClass': 'NSApplication', 'LSUIElement': False,
    'DDLTestDataDirectory': str(data), 'AMFixtureLog': str(log),
}
(contents / 'Info.plist').write_bytes(plistlib.dumps(info))
subprocess.run(['codesign', '--force', '--sign', '-', str(app)], check=True)
command = ['open', '-n']
if not args.keep_open:
    command.append('-W')
subprocess.run([*command, str(app), '--args', '--preview', '--quiet-test'], check=True)
deadline = time.monotonic() + 35
while time.monotonic() < deadline:
    result = log.read_text() if log.exists() else ''
    if 'FAIL:' in result:
        raise SystemExit(result)
    if 'PASS:' in result:
        print(result)
        break
    time.sleep(.2)
else:
    raise SystemExit('Visible assignment fixture did not finish; see its result.log')
