#!/bin/sh

# ci_post_xcodebuild.sh
#
# Xcode Cloud runs this after the build. For builds that produce a signed app
# (i.e. archive / TestFlight distribution), write the TestFlight "What to Test"
# notes so every build is identifiable: which branch it came from and the last
# 5 commits it contains.
#
# Xcode Cloud picks up TestFlight/WhatToTest.<locale>.txt from the repo root.

set -e

# Only act on distribution builds (a signed app exists).
if [ -z "$CI_APP_STORE_SIGNED_APP_PATH" ]; then
    echo "No signed app (not a distribution build) — skipping What to Test notes."
    exit 0
fi

REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
NOTES_DIR="$REPO/TestFlight"
NOTES_FILE="$NOTES_DIR/WhatToTest.en-US.txt"

mkdir -p "$NOTES_DIR"

# Xcode Cloud uses a shallow clone; deepen it so `git log -5` has history.
git -C "$REPO" fetch --deepen 20 >/dev/null 2>&1 || true

BRANCH="${CI_BRANCH:-$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)}"
SHORT_SHA="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)"

{
    echo "Branch: ${BRANCH:-unknown}"
    echo "Build:  ${CI_BUILD_NUMBER:-?} (${SHORT_SHA:-?})"
    echo ""
    echo "Last 5 commits:"
    git -C "$REPO" log -5 --pretty=format:'- %h %s' 2>/dev/null
    echo ""
} > "$NOTES_FILE"

echo "Wrote What to Test notes to $NOTES_FILE:"
cat "$NOTES_FILE"
