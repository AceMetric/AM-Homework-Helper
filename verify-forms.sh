#!/bin/zsh
set -euo pipefail
TASK_DIR="${0:A:h}"
cd "$TASK_DIR"
mkdir -p build/tests build/qa
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
zsh test.sh
for test in UIRegression FormRegression; do
  clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 -framework Cocoa -framework UserNotifications -framework Vision -framework UniformTypeIdentifiers -framework Security "Tests/$test.m" Sources/DDLCore.m Sources/DDLImport.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSGitHub.m Sources/SSGit.m Sources/SSSecurity.m Sources/SSCourseWindow.m -o "build/tests/$test"
  ui_result=$("build/tests/$test" --preview 2>&1)
  print -r -- "$ui_result"
  [[ "$ui_result" == *"PASS:"* ]]
done
