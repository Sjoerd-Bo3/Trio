#!/bin/sh
# ci_scripts/ci_pre_xcodebuild.sh
# Fail fast
set -euo pipefail

# Decide where to get the marketing version.
# 1) Prefer a Git tag pushed by your release process (CI_TAG).
# 2) Fall back to the value in Config.xcconfig if no tag is present.
MARKETING_VERSION="${CI_TAG:-$(/usr/libexec/PlistBuddy -c 'Print :MARKETING_VERSION' Config.xcconfig)}"

# CI_BUILD_NUMBER is an integer that Xcode Cloud auto-increments,
# but you can also derive it from Git commits, Fastlane, etc.
BUILD_NUMBER="${CI_BUILD_NUMBER:-$(git rev-list --count HEAD)}"

echo "⇢ Setting MARKETING_VERSION to ${MARKETING_VERSION}"
agvtool new-marketing-version "${MARKETING_VERSION}"            # bumps CFBundleShortVersionString

echo "⇢ Setting BUILD_NUMBER to ${BUILD_NUMBER}"
agvtool new-version -all "${BUILD_NUMBER}"                      # bumps CFBundleVersion
