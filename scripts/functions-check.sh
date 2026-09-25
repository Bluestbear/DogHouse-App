#!/bin/zsh
# Type-check Cloud Functions without emitting.
setopt pipefail
export PATH="/usr/local/bin:/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")/../DogHouse/functions" || exit 1
command -v npx >/dev/null || { echo "npx not found" >&2; exit 127; }
npx tsc --noEmit --pretty false -p . | head -40
