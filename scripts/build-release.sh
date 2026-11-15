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

APP="build/BlankGrimoire.xcarchive/Products/Applications/BlankGrimoire.app"

ditto -c -k --sequesterRsrc --keepParent \
    build/BlankGrimoire.xcarchive \
    release/BlankGrimoire.xcarchive.zip

(
    cd build/BlankGrimoire.xcarchive/dSYMs
    zip -qry "$ROOT/release/BlankGrimoire.dSYM.zip" .
)

# Sideloading build: an unsigned IPA that SideStore, AltStore or Sideloadly can
# sign with a personal Apple ID. iOS cannot install it as-is; see
# docs/INSTALL.md. The archive above stays the canonical release artifact.
IPA_NAME="BlankGrimoire-$VERSION.ipa"
rm -rf build/ipa
mkdir -p build/ipa/Payload
cp -R "$APP" build/ipa/Payload/BlankGrimoire.app
(
    cd build/ipa
    zip -qry "$ROOT/release/$IPA_NAME" Payload
)

(
    cd release
    shasum -a 256 BlankGrimoire.xcarchive.zip BlankGrimoire.dSYM.zip "$IPA_NAME" > SHA256SUMS
)

# AltStore/SideStore source pointing at this release. Failing to generate it
# must not break a release, so a missing Node runtime only skips the file.
if command -v node >/dev/null 2>&1; then
    node scripts/generate-repo-json.mjs "$VERSION" "release/$IPA_NAME"
else
    echo "warning: node not found, repo.json not regenerated" >&2
fi

echo "Release $VERSION ($BUILD_NUMBER) assets written to release/"
