#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
set -euo pipefail

VERSION="$1"

# Update project.yml MARKETING_VERSION
if [ -f "project.yml" ]; then
    tmp="$(mktemp)"
    sed -E "s/MARKETING_VERSION: [0-9]+\.[0-9]+\.[0-9]+/MARKETING_VERSION: $VERSION/" project.yml > "$tmp"
    mv "$tmp" project.yml
fi

# Update Package.swift version
if [ -f "Packages/ReaderCore/Package.swift" ]; then
    tmp="$(mktemp)"
    sed -E "s/\"version\": \"[0-9]+\.[0-9]+\.[0-9]+\"/\"version\": \"$VERSION\"/" Packages/ReaderCore/Package.swift > "$tmp"
    mv "$tmp" Packages/ReaderCore/Package.swift
fi

# Update .sdk-version
echo "$VERSION" > .sdk-version