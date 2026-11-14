#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="${1:-build/ExportOptions.plist}"
TEAM_ID="${IOS_TEAM_ID:?IOS_TEAM_ID is required}"
PROFILE_NAME="${IOS_PROFILE_NAME:?IOS_PROFILE_NAME is required}"
BUNDLE_ID="${IOS_BUNDLE_ID:-com.blankgrimoire.app}"
METHOD="${IOS_EXPORT_METHOD:-app-store-connect}"

mkdir -p "$(dirname "$OUT")"

cat > "$OUT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>destination</key>
    <string>export</string>
    <key>method</key>
    <string>${METHOD}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>stripSwiftSymbols</key>
    <true/>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>${BUNDLE_ID}</key>
        <string>${PROFILE_NAME}</string>
    </dict>
</dict>
</plist>
PLIST

plutil -lint "$OUT" >/dev/null
echo "Export options written to $OUT"
