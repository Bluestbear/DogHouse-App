#!/bin/zsh
# Unit tests by default; `test.sh ui` runs the XCUITest target instead.
# `test.sh ui <Class>` runs one UI test class; set RESULT=<path.xcresult> to keep screenshots.
set -o pipefail
cd "$(dirname "$0")/../DogHouse" || exit 1
DEST="${SIM_DEST:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"
if [[ "$1" == "ui" ]]; then ONLY="-only-testing:DogHouseUITests${2:+/$2}"; else ONLY="-only-testing:DogHouseTests"; fi
EXTRA=(); [[ -n "$RESULT" ]] && EXTRA=(-resultBundlePath "$RESULT")
xcodebuild -project DogHouse.xcodeproj -scheme DogHouse -destination "$DEST" $ONLY "${EXTRA[@]}" test 2>&1 \
  | grep -E "error:|failed|passed|Executed|Test Suite|\*\* TEST"
exit ${pipestatus[1]}
