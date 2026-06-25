#!/bin/sh

# ci_post_xcodebuild.sh
#
# Xcode Cloud runs this after the build. For builds that produce a signed app
# (i.e. archive / TestFlight distribution), write the TestFlight "What to Test"
# notes so every build is identifiable and self-documenting: which branch it
# came from, and a cumulative list of everything this branch adds on top of its
# base branch (default: dev) — i.e. all the features/PRs included in this build.
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

# Base branch to diff against (everything on this branch since it forked from here).
BASE_BRANCH="${WHATTOTEST_BASE_BRANCH:-dev}"
# Max number of change lines to list (keeps notes well under TestFlight's limit).
MAX_LINES="${WHATTOTEST_MAX_LINES:-30}"

mkdir -p "$NOTES_DIR"

BRANCH="${CI_BRANCH:-$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)}"
SHORT_SHA="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)"

# Xcode Cloud uses a shallow clone. Get enough history to find the common
# ancestor with the base branch; fall back gracefully if anything fails.
git -C "$REPO" fetch --unshallow origin >/dev/null 2>&1 \
    || git -C "$REPO" fetch origin >/dev/null 2>&1 || true
git -C "$REPO" fetch origin "$BASE_BRANCH" >/dev/null 2>&1 || true

BASE="$(git -C "$REPO" merge-base HEAD "origin/$BASE_BRANCH" 2>/dev/null || true)"

{
    echo "Branch: ${BRANCH:-unknown}"
    echo "Build:  ${CI_BUILD_NUMBER:-?} (${SHORT_SHA:-?})"
    echo ""
    if [ -n "$BASE" ] && [ "$BASE" != "$(git -C "$REPO" rev-parse HEAD)" ]; then
        echo "Included in this build (vs ${BASE_BRANCH}):"
        # --first-parent collapses each merged feature/PR to a single line.
        git -C "$REPO" log --first-parent --pretty=format:'- %s' "${BASE}..HEAD" \
            | head -n "$MAX_LINES"
    else
        echo "Recent changes:"
        git -C "$REPO" log --first-parent -n "$MAX_LINES" --pretty=format:'- %s'
    fi
    echo ""
} > "$NOTES_FILE"

echo "Wrote What to Test notes to $NOTES_FILE:"
cat "$NOTES_FILE"
