#!/bin/zsh
set -euo pipefail
TASK_DIR="${0:A:h}"
cd "$TASK_DIR"
mkdir -p build/tests build/qa
SPARKLE_DIR=$(python3 Tools/prepare-sparkle.py)
SPARKLE_DIR=$(python3 Tools/prepare-sparkle.py)
SWIFTUI_DIR=$(python3 Tools/prepare-swiftui.py)
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 \
 -I"$SWIFTUI_DIR" -L"$SWIFTUI_DIR" -lAMUI -Wl,-rpath,"$SWIFTUI_DIR" -framework Cocoa -framework UserNotifications -framework Vision -framework UniformTypeIdentifiers -framework Security -F"$SPARKLE_DIR" -framework Sparkle -Wl,-rpath,"$SPARKLE_DIR" \
 Tests/HomeworkUI.m Sources/DDLCore.m Sources/DDLImport.m Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSGitHub.m Sources/SSGit.m Sources/SSSecurity.m Sources/DDLUI.m Sources/SSUpdateController.m Sources/SSExitCoordinator.m -o build/tests/homework-ui
clang -fobjc-arc -Wall -Wextra -Werror -mmacosx-version-min=13.0 -framework Foundation -framework Vision Tools/PrivacyOCR.m -o build/tests/privacy-ocr
ui_result=$(build/tests/homework-ui --preview 2>&1) || { print -r -- "$ui_result"; exit 1; }
print -r -- "$ui_result"
[[ "$ui_result" == *"homework AppKit assertions"* ]]
