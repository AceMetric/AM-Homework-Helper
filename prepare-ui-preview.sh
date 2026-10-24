#!/bin/zsh
# Local, isolated visual review only. Never package this application as an update.
set -euo pipefail
TASK_DIR="${0:A:h}"
cd "$TASK_DIR"
SPARKLE_DIR=$(python3 Tools/prepare-sparkle.py)
SWIFTUI_DIR=$(python3 Tools/prepare-swiftui.py)
SDK_VERSION=$(xcrun --show-sdk-version)
if (( ${SDK_VERSION%%.*} < 26 )); then print -u2 -- "Native preview requires SDK 26 or newer."; exit 1; fi
PREVIEW_ROOT=$(python3 - "$TASK_DIR/build/qa/previews" <<'PYROOT'
from pathlib import Path
import sys
base=Path(sys.argv[1]);base.mkdir(parents=True,exist_ok=True)
for number in range(1,10000):
    root=base / f'R{number:03d}'
    try: root.mkdir()
    except FileExistsError: continue
    print(root);break
else: raise SystemExit('No preview revision available')
PYROOT
)
PREVIEW_REVISION="${PREVIEW_ROOT:t}"
PREVIEW_APP="$PREVIEW_ROOT/AM Helper Preview $PREVIEW_REVISION.app"
mkdir -p "$PREVIEW_APP/Contents" "$PREVIEW_ROOT/data"
AM_BUILD_OUTPUT_DIR="$PREVIEW_ROOT/.base" zsh build.sh
/usr/bin/ditto "$PREVIEW_ROOT/.base/AM's Homework Helper.app/Contents" "$PREVIEW_APP/Contents"
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 \
 -I"$SWIFTUI_DIR" -L"$SWIFTUI_DIR" -lAMUI -Wl,-rpath,@executable_path/../Frameworks \
 -framework Cocoa -framework PDFKit -framework WebKit -framework UserNotifications -framework Vision -framework UniformTypeIdentifiers -framework Security -F"$SPARKLE_DIR" -framework Sparkle \
 Tests/NativeChromePreview.m Sources/DDLCore.m Sources/DDLImport.m Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSGitHub.m Sources/SSGit.m Sources/SSSecurity.m Sources/DDLUI.m Sources/SSUpdateController.m Sources/SSExitCoordinator.m \
 -o "$PREVIEW_APP/Contents/MacOS/DDLManager"
python3 - "$PREVIEW_APP/Contents/Info.plist" "$PREVIEW_ROOT/data" "$PREVIEW_REVISION" "$SDK_VERSION" <<'PY'
import plistlib,sys
from pathlib import Path
path=Path(sys.argv[1]);info=plistlib.loads(path.read_bytes())
info.update(CFBundleIdentifier='io.github.acemetric.sshomeworkmanager.ui-preview.'+sys.argv[3].lower(),CFBundleName='AM Helper Preview '+sys.argv[3],CFBundleDisplayName='AM Helper 界面预览 '+sys.argv[3],AMPreviewRevision=sys.argv[3],AMPreviewTargetVersion=info['CFBundleShortVersionString'],AMPreviewStatus='visual-review-pending',AMBuildSDK=sys.argv[4],DDLTestDataDirectory=sys.argv[2],DDLTestKeychainService='io.github.acemetric.ui-preview.no-credentials.'+sys.argv[3].lower())
path.write_bytes(plistlib.dumps(info,sort_keys=False))
PY
python3 - "$PREVIEW_ROOT" "$PREVIEW_REVISION" "$SDK_VERSION" <<'PYMANIFEST'
import hashlib,json,plistlib,subprocess,sys
from pathlib import Path
paths=sorted(Path('Sources').rglob('*'))+[Path('Tests/NativeChromePreview.m'),Path('Tests/NativeControlGallery.inc')]
digest=hashlib.sha256()
for path in paths:
    if path.is_file(): digest.update(str(path).encode()+b'\0'+path.read_bytes())
record={'revision':sys.argv[2],'sdk':sys.argv[3],'source_sha256':digest.hexdigest(),'base_commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'target_version':plistlib.loads(Path('Info.plist').read_bytes())['CFBundleShortVersionString'],'visual_acceptance':'pending user screenshots','data':'isolated synthetic data'}
(Path(sys.argv[1])/'manifest.json').write_text(json.dumps(record,indent=2)+'\n')
PYMANIFEST
codesign --force --sign - "$PREVIEW_APP"
codesign --verify --deep --strict "$PREVIEW_APP"
print -r -- "$PREVIEW_APP"
