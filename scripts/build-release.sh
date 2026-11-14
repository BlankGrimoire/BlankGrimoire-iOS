#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

VERSION="${1:?Usage: build-release.sh <version>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_NUMBER="$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: ([0-9]+).*/\1/p' project.yml | head -1)"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

rm -rf build release
mkdir -p build release

xcodebuild archive \
    -project BlankGrimoire.xcodeproj \
    -scheme BlankGrimoire \
    -destination 'generic/platform=iOS' \
    -archivePath build/BlankGrimoire.xcarchive \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    GCC_TREAT_WARNINGS_AS_ERRORS=YES

ditto -c -k --sequesterRsrc --keepParent \
    build/BlankGrimoire.xcarchive \
    release/BlankGrimoire.xcarchive.zip

(
    cd build/BlankGrimoire.xcarchive/dSYMs
    zip -qry "$ROOT/release/BlankGrimoire.dSYM.zip" .
)

(
    cd release
    shasum -a 256 BlankGrimoire.xcarchive.zip BlankGrimoire.dSYM.zip > SHA256SUMS
)

echo "Release $VERSION ($BUILD_NUMBER) assets written to release/"
