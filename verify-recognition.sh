#!/bin/zsh
set -euo pipefail
TASK_DIR="${0:A:h}"
cd "$TASK_DIR"
mkdir -p build/tests
export CLANG_MODULE_CACHE_PATH="$TASK_DIR/build/module-cache"
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=13.0 \
 -framework Foundation -framework Cocoa -framework PDFKit -framework Vision -framework Security -lz \
 Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSSecurity.m Sources/DDLCore.m Sources/DDLImport.m Tests/RecognitionTests.m -o build/tests/recognition-tests
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=13.0 -framework Foundation -framework Cocoa -framework PDFKit -framework Vision -framework Security -lz Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSSecurity.m Sources/DDLCore.m Sources/DDLImport.m Tests/EvidenceRecoveryTests.m -o build/tests/evidence-recovery-tests
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=13.0 -framework Cocoa -framework PDFKit -framework Vision -framework Security -lz Sources/SSLocalData.m Sources/SSSecurity.m Sources/DDLCore.m Sources/DDLImport.m Tests/OperationTests.m -o build/tests/operation-tests
build/tests/operation-tests
AM_TEST_DATA=$(mktemp -d "$TASK_DIR/build/tests/recognition-data.XXXXXX")
export AM_TEST_DATA
trap 'rm -rf "$AM_TEST_DATA"' EXIT
build/tests/recognition-tests
build/tests/evidence-recovery-tests
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=13.0 -framework Cocoa -framework PDFKit -framework Vision -framework Security -lz Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSSecurity.m Sources/DDLCore.m Sources/DDLImport.m Tests/ActivityBoundaryTests.m -o build/tests/activity-boundary-tests
build/tests/activity-boundary-tests
xcrun swiftc -target arm64-apple-macosx13.0 -module-cache-path build/module-cache Sources/AMWorkspace.swift Tests/ReviewStateTests.swift -o build/tests/review-state-tests
build/tests/review-state-tests

clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=13.0 \
 -framework Foundation -framework Cocoa -framework PDFKit -framework Vision -framework Security -lz \
 Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSSecurity.m Sources/DDLCore.m Sources/DDLImport.m Sources/SSGit.m Tests/LocalModelIntegration.m -o build/tests/local-model-integration
python3 Tests/LocalModelIntegration.py
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=13.0 -framework Foundation -framework Cocoa -framework PDFKit -framework Vision -framework Security -lz Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSLocalData.m Sources/SSSecurity.m Sources/DDLCore.m Sources/DDLImport.m Tests/RecognitionSlicesTests.m -o build/tests/recognition-slices-tests
AM_TEST_DATA=$(mktemp -d "$TASK_DIR/build/tests/slices-data.XXXXXX") build/tests/recognition-slices-tests
