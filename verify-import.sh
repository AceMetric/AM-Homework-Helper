#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
mkdir -p "$SCRIPT_DIR/build"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter \
  -mmacosx-version-min=13.0 \
  -framework Cocoa -framework Vision \
  "$SCRIPT_DIR/Sources/DDLImport.m" \
  "$SCRIPT_DIR/Sources/DDLCore.m" \
  "$SCRIPT_DIR/Tests/ImportTests.m" \
  -o "$SCRIPT_DIR/build/import-tests"
"$SCRIPT_DIR/build/import-tests"
