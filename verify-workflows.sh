#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/tests
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unused-function -O2 -mmacosx-version-min=13.0 -framework Cocoa -framework PDFKit -framework Vision -framework Security Sources/DDLCore.m Sources/DDLImport.m Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSSecurity.m Sources/SSLocalData.m Tests/WorkflowTests.m -o build/tests/workflow-tests
workflow_directory=$(mktemp -d "$PWD/build/tests/workflows.XXXXXX")
trap 'rm -rf "$workflow_directory"' EXIT
AM_TEST_DATA="$workflow_directory" build/tests/workflow-tests
