#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p build/tests
export CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache"
clang -fobjc-arc -fblocks -Wall -Wextra -Werror -mmacosx-version-min=13.0 -framework Foundation Sources/DDLCore.m Tests/RecurrenceTests.m -o build/tests/recurrence-tests
build/tests/recurrence-tests
AM_UI_TEST=ScheduledUsage zsh verify-hybrid-ui.sh
