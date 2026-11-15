# Release process

The iOS app is released from `main` by GitHub Actions. The workflow is defined
in `.github/workflows/release.yml`.

## Quality gates

The release job only starts after the `quality` job passes:

- vendored SDK assets match `sdk-assets.sha256` (`make verify-sdk`);
- ReaderCore package tests pass (`make test-readercore`);
- Swift formatting passes (`make lint`);
- app tests pass (`make test`), including the composition-root smoke test.

## What semantic-release produces

`semantic-release` analyses Conventional Commit messages and, when a release is
due, runs `scripts/release-prepare.sh` in the `prepare` phase. That script:

1. updates `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`;
2. regenerates the Xcode project;
3. archives the app for `generic/platform=iOS` without code signing;
4. wraps the unsigned `.app` in a sideloading IPA
   (`BlankGrimoire-<version>.ipa`, a `Payload/` zip);
5. packages the `.xcarchive` and the dSYMs, then writes `release/SHA256SUMS`
   covering all three artifacts;
6. regenerates `repo.json`, the AltStore/SideStore source for that release.

The GitHub release contains:

- `BlankGrimoire.xcarchive.zip`
- `BlankGrimoire.dSYM.zip`
- `BlankGrimoire-<version>.ipa`
- `repo.json` (also committed at the repository root)
- `SHA256SUMS`

`@semantic-release/git` commits `project.yml`, `CHANGELOG.md` and `repo.json`
with a `chore(release): <version> [skip ci]` message. Do not edit
`CHANGELOG.md`, `repo.json` or create release tags by hand.

## Sideloading IPA vs signed IPA

The release publishes an **unsigned** sideloading IPA: the `.app` is simply
zipped into a `Payload/` directory, and SideStore, AltStore or Sideloadly sign
it with the user's own Apple ID. Nothing secret is involved, so it can be
attached to the release automatically. See `docs/INSTALL.md`.

That is different from a **signed** IPA produced by `xcodebuild -exportArchive`,
which needs a certificate, a provisioning profile and an export options plist.
Do not replace the sideloading IPA with a signed export until signing secrets
and a manual or automatic signing job are approved.

`scripts/make-export-options.sh` generates a manual-signing plist from these
environment variables:

| Variable | Required | Default |
| --- | --- | --- |
| `IOS_TEAM_ID` | yes | — |
| `IOS_PROFILE_NAME` | yes | — |
| `IOS_BUNDLE_ID` | no | `com.blankgrimoire.app` |
| `IOS_EXPORT_METHOD` | no | `app-store-connect` |

Do not add a **signed** IPA to `.releaserc.json` until signing secrets and a
manual or automatic signing job are approved. The unsigned sideloading IPA is
already published and is not affected by this rule.

## SDK pin

`.sdk-version` is the explicit SDK release pin. `make sync-sdk` copies assets
from a local SDK checkout but keeps the pin unless `SDK_VERSION=<version>` is
passed. `make sync-sdk-release` downloads the pinned release and refuses to
replace vendored assets when their SHA-256 does not match
`sdk-assets.sha256`.

After an intentional SDK sync, commit `.sdk-version` and `sdk-assets.sha256`
together.
