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
zsh verify-quiet.sh
AM_RELEASE_BUILD=1 zsh build.sh
zsh test.sh
zsh verify-quality.sh
zsh verify-planning.sh
zsh verify-schedules.sh
zsh verify-submissions.sh
zsh verify-workflows.sh
zsh verify-peer-workflows.sh
AM_UI_TEST=PeerWorkspaceUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=WorkflowUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=AIEnhancementUsage zsh verify-hybrid-ui.sh
zsh verify-preflight.sh
zsh verify-online-review.sh
zsh verify-review-materials.sh
zsh verify-quick-entry.sh
zsh verify-import.sh
zsh verify-homework.sh
zsh verify-github-cli.sh
zsh verify-forms.sh
zsh verify-course-ui.sh
zsh verify-update.sh
zsh verify-recognition.sh
zsh verify-hybrid-ui.sh
AM_UI_TEST=QuietUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=SkillExchange zsh verify-hybrid-ui.sh
AM_UI_TEST=QualityUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=PlanningUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=ReminderUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=ReminderMigrationUsage zsh verify-hybrid-ui.sh
python3 Tools/test-reminder-identity.py --identity-only
AM_UI_TEST=PreflightUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=OnlineReviewUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=QuickUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=GuideUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=RendererUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=AppearanceUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=NativeControlsUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=UnifiedUXUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=ToolbarActivityUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=SubmissionResponsivenessUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=RepositoryConcurrencyUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=SubmissionSelectionUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=HistoryPollingUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=AuthActivityUsage zsh verify-hybrid-ui.sh
AM_UI_TEST=NativePromotionUsage zsh verify-hybrid-ui.sh
# Foreground tests are an explicit maintainer lane; do not activate windows in routine builds.
if [[ "${AM_FOREGROUND_QA:-0}" == "1" ]]; then
  AM_UI_TEST=ForegroundUsage zsh verify-hybrid-ui.sh
  AM_UI_TEST=PlanningForeground zsh verify-hybrid-ui.sh
  AM_UI_TEST=QuickForeground zsh verify-hybrid-ui.sh
  AM_UI_TEST=PreflightForeground zsh verify-hybrid-ui.sh
  AM_UI_TEST=TaskCheckForeground zsh verify-hybrid-ui.sh
  AM_UI_TEST=SubmissionMouseUsage zsh verify-hybrid-ui.sh
fi
python3 Tests/SecurityAuditTests.py
product_name=$(python3 -c 'import plistlib; print(plistlib.load(open("Info.plist", "rb"))["CFBundleName"])')
archive_name=$(python3 -c 'import plistlib; print(plistlib.load(open("Info.plist", "rb"))["DDLArchiveName"])')
app="build/$product_name.app"
codesign --verify --deep --strict "$app"
[[ "$(lipo -archs "$app/Contents/MacOS/DDLManager")" == "arm64" ]]
# QA application fixtures include local paths; only synthetic screenshots are release review artifacts.
screenshots=(build/qa/*.png(N))
python3 Tools/security-audit.py --history --artifacts "$app" "${screenshots[@]}" --ocr build/tests/privacy-ocr --report build/security-audit.json
mkdir -p build/releases
stage='build/releases/package'
# Update ZIP contains only the app; public guidance is a separate attachment.
rm -rf "$stage"
mkdir -p "$stage"
/usr/bin/ditto "$app" "$stage/$product_name.app"
version=$(python3 -c 'import plistlib; print(plistlib.load(open("Info.plist", "rb"))["CFBundleShortVersionString"])')
suffix=''
[[ "$mode" == "--candidate" ]] && suffix='-candidate'
archive="build/releases/${archive_name}-${version}-macOS-arm64${suffix}.zip"
/usr/bin/ditto -c -k --sequesterRsrc "$stage" "$archive"
python3 Tools/installation-guide.py "$version"
python3 Tools/security-audit.py --artifacts "$archive" "build/releases/${archive_name}-${version}-installation-guide.txt" --ocr build/tests/privacy-ocr --report build/release-audit.json
/usr/bin/shasum -a 256 "$archive" > "${archive}.sha256"
print -r -- "已生成本机安装包：$archive"
