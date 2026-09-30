#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
DEV_DIR="$(xcode-select -p)"
TEST_FRAMEWORKS="$DEV_DIR/Library/Developer/Frameworks"
if [[ -d "$TEST_FRAMEWORKS/Testing.framework" ]]; then
  swift test --disable-xctest \
    -Xswiftc -F -Xswiftc "$TEST_FRAMEWORKS" \
    -Xlinker -F -Xlinker "$TEST_FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$TEST_FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$DEV_DIR/Library/Developer/usr/lib"
else
  swift test --disable-xctest
fi
