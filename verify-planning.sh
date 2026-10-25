#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/tests
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 -framework Cocoa -framework PDFKit -framework Vision -framework Security -lz Sources/DDLCore.m Sources/DDLImport.m Sources/SSLocalData.m Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSSecurity.m Tests/PlanningTests.m -o build/tests/planning-tests
planning_directory=$(mktemp -d "$PWD/build/tests/planning.XXXXXX")
AM_TEST_DATA="$planning_directory" build/tests/planning-tests
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 -framework Cocoa -framework PDFKit -framework Vision -framework Security -lz Sources/DDLCore.m Sources/DDLImport.m Sources/SSLocalData.m Sources/SSSecurity.m Tests/TaskManagementTests.m -o build/tests/task-management-tests
AM_TEST_DATA="$planning_directory" build/tests/task-management-tests
