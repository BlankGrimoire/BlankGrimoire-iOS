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
4. packages the `.xcarchive` and the dSYMs and writes `release/SHA256SUMS`.

The GitHub release contains:

- `BlankGrimoire.xcarchive.zip`
- `BlankGrimoire.dSYM.zip`
- `SHA256SUMS`

`@semantic-release/git` commits `project.yml` and `CHANGELOG.md` with a
`chore(release): <version> [skip ci]` message. Do not edit `CHANGELOG.md` or
create release tags by hand.

## Code signing (D4)

The release publishes an **unsigned** archive. It does not build or upload an
IPA: `xcodebuild -exportArchive` needs a signed archive, so producing an IPA
requires a certificate, a provisioning profile and an export options plist.

`scripts/make-export-options.sh` generates a manual-signing plist from these
environment variables:

| Variable | Required | Default |
| --- | --- | --- |
| `IOS_TEAM_ID` | yes | — |
| `IOS_PROFILE_NAME` | yes | — |
| `IOS_BUNDLE_ID` | no | `com.blankgrimoire.app` |
| `IOS_EXPORT_METHOD` | no | `app-store-connect` |

Do not add the IPA asset to `.releaserc.json` until signing secrets and a
manual or automatic signing job are approved. Until then the unsigned archive
is the release artifact.

## SDK pin

`.sdk-version` is the explicit SDK release pin. `make sync-sdk` copies assets
from a local SDK checkout but keeps the pin unless `SDK_VERSION=<version>` is
passed. `make sync-sdk-release` downloads the pinned release and refuses to
replace vendored assets when their SHA-256 does not match
`sdk-assets.sha256`.

After an intentional SDK sync, commit `.sdk-version` and `sdk-assets.sha256`
together.
