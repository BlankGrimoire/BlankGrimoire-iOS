#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION_FILE=".sdk-version"
SUMS_FILE="sdk-assets.sha256"
RUNTIME_JS="Packages/ReaderCore/Sources/ReaderCore/PluginEngine/Runtime/Resources/runtime.js"
FIXTURES_DIR="Packages/ReaderCore/Tests/ReaderCoreTests/Resources/Contract/fixtures/v1"

if [[ ! -f "$VERSION_FILE" ]]; then
    echo "Missing $VERSION_FILE" >&2
    exit 1
fi

if [[ ! -f "$RUNTIME_JS" ]]; then
    echo "Missing vendored runtime: $RUNTIME_JS" >&2
    exit 1
fi

if [[ ! -d "$FIXTURES_DIR" ]]; then
    echo "Missing vendored fixtures: $FIXTURES_DIR" >&2
    exit 1
fi

SDK_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

{
    printf '# sdk-version: %s\n' "$SDK_VERSION"
    shasum -a 256 "$RUNTIME_JS"
    find "$FIXTURES_DIR" -type f | LC_ALL=C sort | while IFS= read -r file; do
        shasum -a 256 "$file"
    done
} > "$TMP_FILE"

mv "$TMP_FILE" "$SUMS_FILE"
echo "Updated $SUMS_FILE for SDK $SDK_VERSION"
