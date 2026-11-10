#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$SCRIPT_DIR/.." && pwd)}"
cd "$ROOT"

VERSION_FILE=".sdk-version"
SUMS_FILE="sdk-assets.sha256"
RUNTIME_JS="Packages/ReaderCore/Sources/ReaderCore/PluginEngine/Runtime/Resources/runtime.js"
FIXTURES_DIR="Packages/ReaderCore/Tests/ReaderCoreTests/Resources/Contract/fixtures/v1"

fail() {
    echo "SDK asset verification failed: $*" >&2
    exit 1
}

[[ -f "$VERSION_FILE" ]] || fail "missing $VERSION_FILE"
[[ -f "$SUMS_FILE" ]] || fail "missing $SUMS_FILE"
[[ -f "$RUNTIME_JS" ]] || fail "missing $RUNTIME_JS"
[[ -d "$FIXTURES_DIR" ]] || fail "missing $FIXTURES_DIR"

EXPECTED_VERSION="$(sed -n 's/^# sdk-version: //p' "$SUMS_FILE" | head -1)"
ACTUAL_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
[[ -n "$EXPECTED_VERSION" ]] || fail "$SUMS_FILE has no sdk-version header"
[[ "$EXPECTED_VERSION" == "$ACTUAL_VERSION" ]] || \
    fail "$SUMS_FILE expects $EXPECTED_VERSION but $VERSION_FILE declares $ACTUAL_VERSION"

shasum -a 256 -c "$SUMS_FILE"

MANIFEST_PATHS="$(mktemp)"
ACTUAL_PATHS="$(mktemp)"
trap 'rm -f "$MANIFEST_PATHS" "$ACTUAL_PATHS"' EXIT

grep -v '^#' "$SUMS_FILE" | sed -E 's/^[0-9a-f]{64}  //' | LC_ALL=C sort > "$MANIFEST_PATHS"
{
    printf '%s\n' "$RUNTIME_JS"
    find "$FIXTURES_DIR" -type f
} | LC_ALL=C sort > "$ACTUAL_PATHS"

if ! diff -u "$MANIFEST_PATHS" "$ACTUAL_PATHS"; then
    fail "vendored file list does not match $SUMS_FILE"
fi

echo "SDK assets match SDK $ACTUAL_VERSION"
