#!/bin/zsh
set -euo pipefail
TASK_DIR="${0:A:h}"
cd "$TASK_DIR"
mkdir -p build/tests build/qa
SPARKLE_DIR=$(python3 Tools/prepare-sparkle.py)
SWIFTUI_DIR=$(python3 Tools/prepare-swiftui.py)
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
zsh test.sh
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -O2 -mmacosx-version-min=13.0 -framework Foundation Sources/DDLCore.m Tests/PerformanceTests.m -o build/tests/performance-tests
build/tests/performance-tests
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 -I"$SWIFTUI_DIR" -L"$SWIFTUI_DIR" -lAMUI -Wl,-rpath,"$SWIFTUI_DIR" -framework Cocoa -framework UserNotifications -framework Vision -framework UniformTypeIdentifiers -framework Security -F"$SPARKLE_DIR" -framework Sparkle -Wl,-rpath,"$SPARKLE_DIR" Tests/UIRegression.m Sources/DDLCore.m Sources/DDLImport.m Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSGitHub.m Sources/SSGit.m Sources/SSSecurity.m Sources/DDLUI.m Sources/SSExitCoordinator.m Sources/SSUpdateController.m Sources/SSCourseWindow.m -o build/tests/ui-regression
build/tests/ui-regression --preview
