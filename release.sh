#!/bin/zsh
# Builds a local ZIP only. Uploading to GitHub Releases is a separate maintainer action.
set -euo pipefail
TASK_DIR="${0:A:h}"
cd "$TASK_DIR"
mode="${1:-}"
if [[ -n "$mode" && "$mode" != "--candidate" ]]; then
  print -u2 -- '用法：zsh release.sh [--candidate]'
  exit 2
fi
if [[ "$mode" != "--candidate" ]]; then
  python3 - <<'PY'
import plistlib
from pathlib import Path
config = plistlib.loads(Path('Config/GitHubApp.plist').read_bytes())
if not config.get('clientID') or not config.get('installationURL'):
    raise SystemExit('正式包需要公开 GitHub App 配置，请按 docs/GITHUB_APP_SETUP.md 注册。')
PY
fi
zsh build.sh
zsh verify-import.sh
zsh verify-homework.sh
zsh verify-forms.sh
zsh verify-course-ui.sh
python3 Tests/SecurityAuditTests.py
app='build/SS 作业管理器.app'
codesign --verify --deep --strict "$app"
[[ "$(lipo -archs "$app/Contents/MacOS/SSHomeworkManager")" == "arm64" ]]
python3 Tools/security-audit.py --history --artifacts "$app" build/qa --ocr build/tests/privacy-ocr --report build/security-audit.json
mkdir -p build/releases/package
stage='build/releases/package'
# Only explicit deliverables are copied; no task database, token store or repository metadata.
rm -rf "$stage/SS 作业管理器.app"
cp -R "$app" "$stage/SS 作业管理器.app"
cp docs/ATTRIBUTION.md docs/GITHUB_APP_SETUP.md docs/SECURITY.md "$stage/"
python3 - <<'PY'
from pathlib import Path
Path('build/releases/package/安装说明.txt').write_text('''SS 作业管理器 1.0 · macOS 13+ · Apple 芯片

此包使用临时签名，未经 Apple 公证。解压后拖入“应用程序”。首次打开若被阻止，在系统设置 → 隐私与安全性中按系统提示选择“仍要打开”。

GitHub 课程窗口可安装 App、设备码登录、关联个人 fork 和本地克隆。未预置公开 Client ID 的候选包需先按 GITHUB_APP_SETUP.md 完成配置。

只从老师默认分支扫描作业；识别项须审核。所有推送只到已核验属于当前用户的个人 fork。提交前逐项选文件；冲突时使用引导。

旧版 DDL Manager 先导出任务备份，再在本应用导入。登录令牌只存于本机钥匙串，不在备份或此包中。

提醒需要系统通知权限。关闭窗口后仍在菜单栏运行；退出应用、关机或休眠时无法定时扫描。更多安全限制见 SECURITY.md。
''')
PY
suffix=''
[[ "$mode" == "--candidate" ]] && suffix='-candidate'
archive="build/releases/SS-Homework-Manager-1.0-macOS-arm64${suffix}.zip"
/usr/bin/ditto -c -k --sequesterRsrc "$stage" "$archive"
python3 Tools/security-audit.py --artifacts "$archive" --ocr build/tests/privacy-ocr --report build/release-audit.json
/usr/bin/shasum -a 256 "$archive" > "${archive}.sha256"
print -r -- "已生成本机安装包：$archive"
