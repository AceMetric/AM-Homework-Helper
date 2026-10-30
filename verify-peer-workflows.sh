#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/tests
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
clang -DDDL_TESTING=1 -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -O2 -mmacosx-version-min=13.0 -framework Cocoa -framework PDFKit -framework Vision -framework Security -lz Sources/DDLCore.m Sources/DDLImport.m Sources/SSRecognition.m Sources/SSAssignments.m Sources/SSSecurity.m Sources/SSLocalData.m Sources/SSGitHub.m Tests/PeerWorkflowTests.m -o build/tests/peer-workflows
peer_directory=$(mktemp -d "$PWD/build/tests/peers.XXXXXX")
trap 'rm -rf "$peer_directory"' EXIT
AM_TEST_DATA="$peer_directory" build/tests/peer-workflows
