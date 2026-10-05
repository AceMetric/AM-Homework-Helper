#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_DIR="$SCRIPT_DIR/build/DDL-Manager.app"
CONTENTS="$APP_DIR/Contents"
export CLANG_MODULE_CACHE_PATH="$SCRIPT_DIR/build/module-cache"

SPARKLE_DIR=$(python3 "$SCRIPT_DIR/Tools/prepare-sparkle.py")
mkdir -p "$CONTENTS/Frameworks"
/usr/bin/ditto "$SPARKLE_DIR/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
mkdir -p "$SCRIPT_DIR/build/DDL.iconset"

clang -arch arm64 -fobjc-arc -mmacosx-version-min=13.0 -framework Cocoa "$SCRIPT_DIR/Tools/Icon.m" -o "$SCRIPT_DIR/build/render-icon"
"$SCRIPT_DIR/build/render-icon" "$SCRIPT_DIR/build/DDL.iconset" "$CONTENTS/Resources/AppIcon.icns"

clang \
  -arch arm64 \
  -fobjc-arc \
  -fblocks \
  -Wall -Wextra -Werror -Wno-unused-parameter \
  -mmacosx-version-min=13.0 \
  -O2 \
  -framework Cocoa \
  -framework UserNotifications \
  -framework Vision \
  -framework UniformTypeIdentifiers \
  -framework Security \
  -F"$SPARKLE_DIR" -framework Sparkle \
  -Wl,-rpath,@executable_path/../Frameworks \
  "$SCRIPT_DIR/Sources/App.m" \
  "$SCRIPT_DIR/Sources/DDLCore.m" \
  "$SCRIPT_DIR/Sources/DDLImport.m" \
  "$SCRIPT_DIR/Sources/SSAssignments.m" \
  "$SCRIPT_DIR/Sources/SSLocalData.m" \
  "$SCRIPT_DIR/Sources/SSGitHub.m" \
  "$SCRIPT_DIR/Sources/SSGit.m" \
  "$SCRIPT_DIR/Sources/DDLUI.m" \
  "$SCRIPT_DIR/Sources/SSExitCoordinator.m" \
  "$SCRIPT_DIR/Sources/SSUpdateController.m" \
  "$SCRIPT_DIR/Sources/SSSecurity.m" \
  "$SCRIPT_DIR/Sources/SSCourseWindow.m" \
  -o "$CONTENTS/MacOS/DDLManager"

cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"
python3 "$SCRIPT_DIR/Tools/configure-bundle.py" "$SCRIPT_DIR/Config/GitHubApp.plist" "$CONTENTS/Info.plist"
cp "$SCRIPT_DIR/Tools/SSAskPass.sh" "$CONTENTS/Resources/SSAskPass.sh"
chmod 700 "$CONTENTS/Resources/SSAskPass.sh"
chmod +x "$CONTENTS/MacOS/DDLManager"
cp "$SPARKLE_DIR/LICENSE" "$CONTENTS/Resources/Sparkle-LICENSE.txt"
cp "$SCRIPT_DIR/LICENSE" "$CONTENTS/Resources/DDL-Manager-LICENSE.txt"
cp "$SCRIPT_DIR/docs/ATTRIBUTION.md" "$CONTENTS/Resources/ATTRIBUTION.md"
# Preserve upstream framework/helper signatures; sign the host only.
codesign --force --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
