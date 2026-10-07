#!/bin/zsh
set -euo pipefail
TASK_DIR="${0:A:h}"
mkdir -p "$TASK_DIR/build/tests"
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
  -mmacosx-version-min=13.0 -framework Cocoa -framework Vision -framework Security \
  "$TASK_DIR/Sources/DDLCore.m" "$TASK_DIR/Sources/DDLImport.m" \
  "$TASK_DIR/Sources/SSRecognition.m" "$TASK_DIR/Sources/SSAssignments.m" "$TASK_DIR/Sources/SSSecurity.m" \
  "$TASK_DIR/Sources/SSLocalData.m" "$TASK_DIR/Tests/HomeworkTests.m" \
  -o "$TASK_DIR/build/tests/homework-tests"
"$TASK_DIR/build/tests/homework-tests"
