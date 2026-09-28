#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_DIR="$SCRIPT_DIR/build/DDL Manager.app"
CONTENTS="$APP_DIR/Contents"
export CLANG_MODULE_CACHE_PATH="$SCRIPT_DIR/build/module-cache"

mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
mkdir -p "$SCRIPT_DIR/build/DDL.iconset"

clang -fobjc-arc -mmacosx-version-min=13.0 -framework Cocoa "$SCRIPT_DIR/Tools/Icon.m" -o "$SCRIPT_DIR/build/render-icon"
"$SCRIPT_DIR/build/render-icon" "$SCRIPT_DIR/build/DDL.iconset"
iconutil -c icns "$SCRIPT_DIR/build/DDL.iconset" -o "$CONTENTS/Resources/AppIcon.icns"

clang \
  -fobjc-arc \
  -fblocks \
  -Wall -Wextra -Werror -Wno-unused-parameter \
  -mmacosx-version-min=13.0 \
  -O2 \
  -framework Cocoa \
  -framework UserNotifications \
  "$SCRIPT_DIR/Sources/App.m" \
  "$SCRIPT_DIR/Sources/DDLCore.m" \
  -o "$CONTENTS/MacOS/DDLManager"

cp "$SCRIPT_DIR/Info.plist" "$CONTENTS/Info.plist"
chmod +x "$CONTENTS/MacOS/DDLManager"
codesign --force --deep --sign - "$APP_DIR"

echo "$APP_DIR"
