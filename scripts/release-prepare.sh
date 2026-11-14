#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
set -euo pipefail

VERSION="${1:?Usage: release-prepare.sh <version>}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

bash scripts/set-version.sh "$VERSION"
xcodegen generate --spec project.yml
bash scripts/build-release.sh "$VERSION"
