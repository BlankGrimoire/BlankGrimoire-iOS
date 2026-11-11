#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

VERSION="${1:?Usage: set-version.sh <version> [build-number]}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_NUMBER="${2:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "Invalid version: $VERSION" >&2
    exit 1
fi

# Update project.yml MARKETING_VERSION and CURRENT_PROJECT_VERSION.
if [[ -f "project.yml" ]]; then
    tmp="$(mktemp)"
    sed -E \
        -e "s/MARKETING_VERSION: [0-9]+\.[0-9]+\.[0-9]+([^ ]*)/MARKETING_VERSION: $VERSION/" \
        -e "s/CURRENT_PROJECT_VERSION: [0-9]+/CURRENT_PROJECT_VERSION: $BUILD_NUMBER/" \
        project.yml > "$tmp"
    mv "$tmp" project.yml
fi

echo "Project version set to $VERSION ($BUILD_NUMBER)"
