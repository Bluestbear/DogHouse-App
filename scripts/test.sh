#!/bin/zsh
# Unit tests by default; `test.sh ui` runs the XCUITest target instead.
set -o pipefail
cd "$(dirname "$0")/../DogHouse" || exit 1
DEST="${SIM_DEST:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"
if [[ "$1" == "ui" ]]; then ONLY="-only-testing:DogHouseUITests"; else ONLY="-only-testing:DogHouseTests"; fi
# Parallel testing clones the sim per worker and never cleans up (~4 GB each in
# ~/Library/Developer/XCTestDevices), so run serially and sweep any clones after.
xcodebuild -project DogHouse.xcodeproj -scheme DogHouse -destination "$DEST" $ONLY \
  -parallel-testing-enabled NO test 2>&1 \
  | grep -E "error:|failed|passed|Executed|Test Suite|\*\* TEST"
code=${pipestatus[1]}
xcrun simctl --set testing delete all >/dev/null 2>&1
exit $code
