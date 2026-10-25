#!/bin/zsh
set -euo pipefail
TASK_DIR="${0:A:h}"
cd "$TASK_DIR"
mkdir -p build/tests build/qa
python3 Tools/prepare-renderer.py >/dev/null
SPARKLE_DIR=$(python3 Tools/prepare-sparkle.py)
SWIFTUI_DIR=$(python3 Tools/prepare-swiftui.py)
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 \
 -I"$SWIFTUI_DIR" -L"$SWIFTUI_DIR" -lAMUI -Wl,-rpath,"$SWIFTUI_DIR" \
 -framework Cocoa -framework PDFKit -framework WebKit -framework UserNotifications -framework Vision -framework UniformTypeIdentifiers -framework Security -lz -F"$SPARKLE_DIR" -framework Sparkle -Wl,-rpath,"$SPARKLE_DIR" \
 "Tests/${AM_UI_TEST:-HybridUI}.m" Sources/DDLCore.m Sources/DDLImport.m Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSGitHub.m Sources/SSGit.m Sources/SSSecurity.m Sources/DDLUI.m Sources/SSUpdateController.m Sources/SSExitCoordinator.m -o "build/tests/${AM_UI_TEST:-HybridUI}"
ui_result=$(python3 Tools/run-quiet-test.py "build/tests/${AM_UI_TEST:-HybridUI}" --preview 2>&1) || { print -r -- "$ui_result"; exit 1; }
print -r -- "$ui_result"
[[ "$ui_result" == *"PASS:"* ]]
