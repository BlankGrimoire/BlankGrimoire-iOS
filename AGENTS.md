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

1. **No real website domains** anywhere (code, tests, comments, commit messages, docs). Use `example.org` / `example.com` only.
2. **Themes, not websites.** No site-specific scrapers, no lists of sites, no adapters named after sites.
3. **Synthetic fixtures only.** Hand-written Lorem ipsum and placeholder images. Never copy HTML, text, or images from real sites.
4. **No circumvention.** No bypass of authentication, paywalls, DRM, or access controls. Anti-bot challenges are completed by the user in a **visible** WKWebView, never a hidden one.
5. **Attribution preserved.** Site name, logo, credits, and the "Open on site" button. Credit pages are never filtered.
6. **No marketing vocabulary.** The words manga, manhwa, and scanlation must not appear in descriptions, topics, or README marketing. Domain type names (e.g. `MangaSummary`) are acceptable in code.
7. **Never commit secrets.** The Ed25519 private key lives only in GitHub environment secrets.
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
| Generate Xcode project | `xcodegen generate` |
| Package tests | `swift test --package-path Packages/ReaderCore` |
| App build (CI-equivalent) | `xcodebuild build -scheme <APP_SCHEME> -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO` |
| Sync SDK (local) | `make sync-sdk SDK_PATH=../BlankGrimoire-sdk` |
| Sync SDK (release) | `make sync-sdk` (uses `.sdk-version`) |
| Format / lint | `swift format lint --recursive .` |

> Replace `<APP_SCHEME>` with the scheme name defined in `project.yml`. If `project.yml` does not exist yet (before IOS-0), leave the placeholder and note it in the report.

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
