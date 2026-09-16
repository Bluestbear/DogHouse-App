#!/bin/zsh
# Type-check Cloud Functions without emitting.
cd "$(dirname "$0")/../DogHouse/functions" || exit 1
npx tsc --noEmit --pretty false -p . | head -40
