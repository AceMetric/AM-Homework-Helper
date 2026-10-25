#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/tests
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -Wno-unused-function -O2 -mmacosx-version-min=13.0 -framework Cocoa -framework PDFKit -framework Vision -framework Security -lz Sources/DDLCore.m Sources/DDLImport.m Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSSecurity.m Sources/SSLocalData.m Tests/OnlineReviewTests.m -o build/tests/online-review-tests
online_directory=$(mktemp -d "$PWD/build/tests/online-review.XXXXXX")
trap 'rm -rf "$online_directory"' EXIT
AM_TEST_DATA="$online_directory" build/tests/online-review-tests
