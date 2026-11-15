#!/bin/zsh
# Manual, real-account quality lane. Routine CI never starts a model request.
set -euo pipefail
cd "${0:A:h}"
if [[ "${AM_LIVE_MODEL_QA:-0}" != 1 ]]; then
  print -u2 -- '真实模型验收需要明确启用：AM_LIVE_MODEL_QA=1 zsh verify-live-models.sh。窗口打开后仍需登录并点击运行。'
  exit 2
fi
TASK_DIR="$PWD"
mkdir -p build/tests
python3 Tools/prepare-renderer.py >/dev/null
SPARKLE_DIR=$(python3 Tools/prepare-sparkle.py)
SWIFTUI_DIR=$(python3 Tools/prepare-swiftui.py)
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 \
 -I"$SWIFTUI_DIR" -L"$SWIFTUI_DIR" -lAMUI -Wl,-rpath,"$SWIFTUI_DIR" \
 -framework Cocoa -framework PDFKit -framework WebKit -framework UserNotifications -framework Vision -framework UniformTypeIdentifiers -framework CFNetwork -framework Security -lz -F"$SPARKLE_DIR" -framework Sparkle -Wl,-rpath,"$SPARKLE_DIR" \
 Tests/LiveModelAcceptance.m Sources/DDLCore.m Sources/DDLImport.m Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSGitHub.m Sources/SSGit.m Sources/SSSecurity.m Sources/DDLUI.m Sources/SSUpdateController.m Sources/SSExitCoordinator.m -o build/tests/LiveModelAcceptance

python3 - <<'PYBUNDLE'
import json,plistlib,subprocess
from pathlib import Path
root=Path.cwd();folder=root/'build/tests/live-model-acceptance';app=folder/'AM Model Acceptance.app';mac=app/'Contents/MacOS';res=app/'Contents/Resources';mac.mkdir(parents=True,exist_ok=True);res.mkdir(exist_ok=True);data=folder/'data';data.mkdir(exist_ok=True)
read=lambda name:json.loads((root/'Tests/Fixtures'/name).read_text())
gold=read('semantic-requirements-gold.json');plan=[]
for group,items in [('gold',gold),('reserved-v2',read('semantic-requirements-holdout-v2.json'))]:
 for item in items:plan.append(dict(item,mode='recognition',set=group))
for item in gold:
 if item['id'] in ('grid','skip','naming','png'):plan.append(dict(item,id='fields-'+item['id'],mode='fields',set='field-proposals'))
for item in read('model-review-live.json'):plan.append(dict(item,mode='review',set='answer-checks'))
assert len(plan)==24
(res/'acceptance-plan.json').write_text(json.dumps(plan,ensure_ascii=False))
subprocess.run(['ditto','build/tests/LiveModelAcceptance',str(mac/'LiveModelAcceptance')],check=True)
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'io.github.ddl-manager.model-acceptance','CFBundleExecutable':'LiveModelAcceptance','CFBundleName':'AM Model Acceptance','CFBundlePackageType':'APPL','CFBundleVersion':'52','NSPrincipalClass':'NSApplication','DDLTestDataDirectory':str(data),'DDLTestKeychainService':'io.github.ddl-manager.model-acceptance-120'}))
subprocess.run(['codesign','--force','--sign','-','--requirements','=designated => identifier "io.github.ddl-manager.model-acceptance"',str(app)],check=True)
subprocess.run(['codesign','--verify','--strict',str(app)],check=True)
subprocess.run(['open','-n',str(app)],check=True)
print('已打开隔离验收窗口；只使用合成样例，点击运行前不会发送请求。')
PYBUNDLE
