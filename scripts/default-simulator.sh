#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Print the name of the first available iPhone simulator, for Make defaults.
set -euo pipefail

xcrun simctl list devices available \
    | sed -nE 's/^ *(iPhone [^(]*) \(.*/\1/p' \
    | head -1 \
    | sed -E 's/ *$//'
