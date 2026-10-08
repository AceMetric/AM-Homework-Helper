#!/bin/zsh
set -euo pipefail
TASK_ROOT="${0:A:h}"
cd "$TASK_ROOT"
mkdir -p build/tests
export CLANG_MODULE_CACHE_PATH="$TASK_ROOT/build/module-cache"
clang -arch arm64 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=13.0 -framework Foundation -framework Security -DDDL_TESTING Tests/GitHubCLITests.m Sources/SSLocalData.m Sources/SSSecurity.m -o build/tests/github-cli-tests
build/tests/github-cli-tests
