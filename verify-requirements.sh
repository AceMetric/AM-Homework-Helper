#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/tests
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 -framework Cocoa -framework PDFKit -framework Vision -framework CFNetwork -framework Security -lz Sources/DDLCore.m Sources/DDLImport.m Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSSecurity.m Sources/SSLocalData.m Tests/RequirementTests.m -o build/tests/requirements
build/tests/requirements "${1:-Tests/Fixtures/requirements-gold.json}"
