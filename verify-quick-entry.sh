#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/tests
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unused-function -O2 -mmacosx-version-min=13.0 -framework Cocoa -framework Vision -framework Security Sources/DDLCore.m Sources/DDLImport.m Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSSecurity.m Sources/SSLocalData.m Tests/QuickEntryTests.m -o build/tests/quick-entry-tests
quick_directory=$(mktemp -d "$PWD/build/tests/quick.XXXXXX")
AM_TEST_DATA="$quick_directory" build/tests/quick-entry-tests
