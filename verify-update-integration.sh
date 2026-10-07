#!/bin/zsh
set -euo pipefail
TASK_DIR="${0:A:h}"
cd "$TASK_DIR"
mkdir -p build/tests
SPARKLE_DIR=$(python3 Tools/prepare-sparkle.py)
SWIFTUI_DIR=$(python3 Tools/prepare-swiftui.py)
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
clang -DDDL_TESTING -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 \
  -I"$SWIFTUI_DIR" -L"$SWIFTUI_DIR" -lAMUI -framework Cocoa -framework UserNotifications -framework Vision -framework UniformTypeIdentifiers -framework Security \
  -F"$SPARKLE_DIR" -framework Sparkle -Wl,-rpath,@executable_path/../Frameworks \
  Tests/UpdateIntegration.m Sources/DDLCore.m Sources/DDLImport.m Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m \
  Sources/SSGitHub.m Sources/SSGit.m Sources/SSSecurity.m Sources/DDLUI.m \
  Sources/SSUpdateController.m Sources/SSExitCoordinator.m -o build/tests/update-integration
python3 Tools/test-update-integration.py
