#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/tests
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -Wno-unused-parameter -mmacosx-version-min=13.0 -framework Cocoa Tests/QuietHarness.m -o build/tests/quiet-harness
python3 Tools/run-quiet-test.py build/tests/quiet-harness
