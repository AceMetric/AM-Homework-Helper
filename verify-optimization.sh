#!/bin/zsh
set -euo pipefail
TASK_DIR="${0:A:h}"
cd "$TASK_DIR"
mkdir -p build/tests build/qa
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
zsh test.sh
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -O2 -mmacosx-version-min=13.0 -framework Foundation Sources/DDLCore.m Tests/PerformanceTests.m -o build/tests/performance-tests
build/tests/performance-tests
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 -framework Cocoa -framework UserNotifications -framework Vision -framework UniformTypeIdentifiers -framework Security Tests/UIRegression.m Sources/DDLCore.m Sources/DDLImport.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSGitHub.m Sources/SSGit.m Sources/SSSecurity.m Sources/DDLUI.m Sources/SSCourseWindow.m -o build/tests/ui-regression
build/tests/ui-regression --preview
