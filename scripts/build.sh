#!/bin/zsh
# Headless Debug build for the simulator. Prints only errors/warnings; exit code is xcodebuild's.
set -o pipefail
cd "$(dirname "$0")/../DogHouse" || exit 1
DEST="${SIM_DEST:-platform=iOS Simulator,name=iPhone 17,OS=26.5}"
if command -v xcbeautify >/dev/null; then FILTER=(xcbeautify --quiet); else FILTER=(grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)"); fi
NSUnbufferedIO=YES xcodebuild -project DogHouse.xcodeproj -scheme DogHouse -destination "$DEST" \
  -configuration Debug -quiet build 2>&1 | "${FILTER[@]}"
exit ${pipestatus[1]}
