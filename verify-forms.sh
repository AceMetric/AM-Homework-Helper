#!/bin/zsh
set -euo pipefail
TASK_DIR="${0:A:h}"
cd "$TASK_DIR"
mkdir -p build/tests QA
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
zsh test.sh
for test in UIRegression FormRegression; do
  clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 -framework Cocoa -framework UserNotifications -framework Vision -framework UniformTypeIdentifiers "Tests/$test.m" Sources/DDLCore.m Sources/DDLImport.m -o "build/tests/$test"
  "build/tests/$test" --preview
done
