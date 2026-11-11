# AGENTS.md

Instructions for AI coding agents working in this repository.
Human contributors: see `CONTRIBUTING.md` (if present) and the organization's `.github` repository.

## Repository Facts

| Key | Value |
|-----|-------|
| Repository | BlankGrimoire-iOS |
| Stack | Swift 6, SwiftUI, XcodeGen, SwiftPM (`Packages/ReaderCore`), SwiftData, iOS 17+ |
| License | MPL-2.0 |
| Source header | The three-line MPL-2.0 header at the top of every `.swift` file |
| Contact | blankgrimoire.dev@gmail.com |
| Copyright holder | BlankGrimoire contributors |

## Non-Negotiable Rules

1. **Flexible Endpoint Configuration.** Avoid hardcoding explicit real-world domains in code, tests, or documentation. Use configurable base URLs or generic identifiers (e.g., `SourceTypeA`, `TemplateB`) to abstract the underlying fan-site infrastructure.
2. **Generic Theme Adapters.** Scrapers and adapters must be designed around structural layout themes rather than being explicitly named after specific websites. Build them to support families of sites with similar architectures, keeping the actual target domains masked and dynamically injected.
3. **Abstracted Test Data.** Avoid bundling extensive real content from external platforms in the repository. Use genericized fixtures or placeholder assets for testing instead of direct rips from target sites.
4. **Silent anti-bot resolution first.** Adapters should attempt to handle and bypass standard anti-bot challenges or captchas automatically and transparently in the background. Only if automated resolution fails or is technically unfeasible must the challenge be deferred to the user via a visible WKWebView.
5. **Attribution preserved.** Site name, logo, credits, and the "Open on site" button must remain intact. Credit pages are never filtered.
6. **No marketing vocabulary.** The words manga, manhwa, and scanlation must not appear in descriptions, topics, or README marketing. Domain type names (e.g. `MangaSummary`) are acceptable in code. Published adapter names and descriptions are validated at build time.
7. **Never commit secrets.** The Ed25519 private key lives only in GitHub environment secrets. Local keys and certificates are gitignored.
8. **Never commit personal emails.** The only allowed email is blankgrimoire.dev@gmail.com.

## Git Rules

- Never `git push`, never force push, never create remote resources, never publish packages.
- Conventional Commits only: `feat`, `fix`, `perf`, `refactor`, `docs`, `chore`, `ci`, `test`, `revert`; use `!` for breaking changes.
- Branches: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`.
- Squash merge; the PR title is the commit message and drives semantic-release.
- Never edit `CHANGELOG.md` by hand. Never create release tags manually.

## Code Style

Swift 6 strict concurrency; `swift format`; no force unwraps, `try!`, or IUOs outside tests; `Sendable` and actors for shared state.

## Commands

| Task | Command |
|------|---------|
| Generate Xcode project | `make gen` |
| Package tests | `make test-readercore` |
| App tests | `make test` |
| App build (CI-equivalent) | `xcodebuild build -scheme <APP_SCHEME> -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` |
| Sync SDK (local) | `make sync-sdk SDK_REPO_PATH=../BlankGrimoire-sdk` |
| Sync SDK (release) | `make sync-sdk-release` (uses `.sdk-version`) |
| Format / lint | `make lint` |

> Replace `<APP_SCHEME>` with the scheme name defined in `project.yml` (`BlankGrimoire` in this repository).

## Local test troubleshooting on macOS

This checkout may live under `~/Documents` (iCloud Drive). SwiftPM's default
`Packages/ReaderCore/.build` then receives `com.apple.fileprovider.*` and
`com.apple.FinderInfo` extended attributes. `codesign` fails with:

```text
ReaderCore_ReaderCoreTests.bundle: resource fork, Finder information, or similar detritus not allowed
```

This is **not** a SwiftPM limitation and the tests are **not** CI-only. It is a
local xattr problem. `make test-readercore` already builds with a scratch path
outside iCloud (`~/Library/Caches/BlankGrimoire/ReaderCoreBuild`). Use it as-is,
or override the path:

```bash
READERCORE_SCRATCH=/path/outside/iCloud make test-readercore
```

Do not report ReaderCore tests as blocked, skipped or "known failing" until you
have run `make test-readercore` and pasted the real failure. `xattr -cr` on
`.build` is only a fallback: it can fail on read-only dependency checkouts and
does not stop iCloud from re-adding the attributes.

Canonical verification for every iOS phase:

```bash
make gen
make lint
make test-readercore
xcodebuild build -project BlankGrimoire.xcodeproj -scheme BlankGrimoire \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
```

## Before Every Commit

- [ ] All commands in the table above pass.
- [ ] Every new source file has the license header.
- [ ] Domain, vocabulary, secrets, and email scans are clean.
- [ ] No new dependencies without human approval.

## Ask a Human Before

- Adding dependencies not listed in the handouts.
- Changing the adapter contract after SDK-1 approval.
- Anything touching remotes, repository settings, or secrets.
- App icon or branding, distribution or code signing, and license questions.
