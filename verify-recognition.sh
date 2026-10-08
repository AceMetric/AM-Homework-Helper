#!/bin/zsh
set -euo pipefail
TASK_DIR="${0:A:h}"
cd "$TASK_DIR"
mkdir -p build/tests
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=13.0 \
 -framework Foundation -framework Cocoa -framework Vision -framework Security \
 Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSSecurity.m Sources/DDLCore.m Sources/DDLImport.m Tests/RecognitionTests.m -o build/tests/recognition-tests
AM_TEST_DATA=$(mktemp -d "$TASK_DIR/build/tests/recognition-data.XXXXXX")
export AM_TEST_DATA
trap 'rm -rf "$AM_TEST_DATA"' EXIT
build/tests/recognition-tests
xcrun swiftc -target arm64-apple-macosx13.0 -module-cache-path build/module-cache Sources/AMWorkspace.swift Tests/ReviewStateTests.swift -o build/tests/review-state-tests
build/tests/review-state-tests

clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=13.0 \
 -framework Foundation -framework Cocoa -framework Vision -framework Security \
 Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSSecurity.m Sources/DDLCore.m Sources/DDLImport.m Sources/SSGit.m Tests/LocalModelIntegration.m -o build/tests/local-model-integration
python3 Tests/LocalModelIntegration.py
