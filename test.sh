#!/bin/zsh
set -euo pipefail
TASK_DIR="${0:A:h}"
mkdir -p "$TASK_DIR/build/tests"
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -mmacosx-version-min=13.0 -framework Foundation "$TASK_DIR/Sources/DDLCore.m" "$TASK_DIR/Tests/CoreTests.m" -o "$TASK_DIR/build/tests/core-tests"
"$TASK_DIR/build/tests/core-tests"
