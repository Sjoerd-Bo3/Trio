#!/bin/sh

# ci_post_xcodebuild.sh
#
# Xcode Cloud runs this after the build. For distribution builds (a signed app
# exists) it writes the TestFlight "What to Test" notes so every build is
# self-documenting: the branch, the build number, an optional manual message,
# and a cumulative, tidied list of everything this branch adds on top of its
# base branch (default: dev) — i.e. the features/PRs included in this build.
#
# Xcode Cloud picks up TestFlight/WhatToTest.<locale>.txt from the repo root.
#
# To add a manual note for a build, put text in ci_scripts/whattotest_message.txt
# (it is prepended above the auto-generated change list). The change list stays
# automatic, so good merge/PR subject lines keep these notes readable — see
# CLAUDE.md ("TestFlight What-to-Test notes").

set -e

# Only act on distribution builds (a signed app exists).
if [ -z "$CI_APP_STORE_SIGNED_APP_PATH" ]; then
    echo "No signed app (not a distribution build) — skipping What to Test notes."
    exit 0
fi

REPO="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/.." && pwd)}"
NOTES_DIR="$REPO/TestFlight"
NOTES_FILE="$NOTES_DIR/WhatToTest.en-US.txt"
MESSAGE_FILE="$REPO/ci_scripts/whattotest_message.txt"

BASE_BRANCH="${WHATTOTEST_BASE_BRANCH:-dev}"   # diff this branch against here
MAX_LINES="${WHATTOTEST_MAX_LINES:-30}"        # keep notes under TestFlight's limit

mkdir -p "$NOTES_DIR"

BRANCH="${CI_BRANCH:-$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)}"
SHORT_SHA="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null)"

# Xcode Cloud uses a shallow clone; get enough history to find the merge-base.
git -C "$REPO" fetch --unshallow origin >/dev/null 2>&1 \
    || git -C "$REPO" fetch origin >/dev/null 2>&1 || true
git -C "$REPO" fetch origin "$BASE_BRANCH" >/dev/null 2>&1 || true
BASE="$(git -C "$REPO" merge-base HEAD "origin/$BASE_BRANCH" 2>/dev/null || true)"

# Collapse first-parent history to one tidy line per feature/PR.
tidy_changes() {
    range="$1"
    git -C "$REPO" log --first-parent --pretty=format:'%s' $range 2>/dev/null \
        | grep -vE "^Merge (branch|remote-tracking branch) '(origin/)?(dev|${BASE_BRANCH})'" \
        | sed -E \
            -e "s|^Merge [^ ]+/[^ ]+ PR #([0-9]+) \((.*)\) into .*|PR #\1 — \2|" \
            -e "s|^Merge [^ ]+/[^ ]+ PR #([0-9]+) into .*|PR #\1|" \
            -e "s|^Merge remote-tracking branch 'origin/(.*)' into .*|\1|" \
            -e "s|^Merge branch '(.*)' into .*|\1|" \
            -e "s| into ${BRANCH}\$||" \
            -e "s|^Merge ||" \
            -e "s|^claude/||" \
        | sed -E 's/^/- /' \
        | head -n "$MAX_LINES"
}

{
    echo "Branch: ${BRANCH:-unknown}"
    echo "Build:  ${CI_BUILD_NUMBER:-?} (${SHORT_SHA:-?})"
    echo ""

    if [ -f "$MESSAGE_FILE" ] && [ -s "$MESSAGE_FILE" ]; then
        cat "$MESSAGE_FILE"
        echo ""
    fi

    if [ -n "$BASE" ] && [ "$BASE" != "$(git -C "$REPO" rev-parse HEAD)" ]; then
        echo "Included in this build (vs ${BASE_BRANCH}):"
        tidy_changes "${BASE}..HEAD"
    else
        echo "Recent changes:"
        tidy_changes "-n ${MAX_LINES}"
    fi
    echo ""
} > "$NOTES_FILE"

echo "Wrote What to Test notes to $NOTES_FILE:"
cat "$NOTES_FILE"
