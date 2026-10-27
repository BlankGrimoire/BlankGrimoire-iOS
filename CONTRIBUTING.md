# Contributing to BlankGrimoire for iOS

Thanks for your interest in contributing! Please read this guide before
opening an issue or a pull request.

## Ground rules (non-negotiable)

1. **No real website domains** in code, tests, comments, commit messages,
   issues or screenshots.
2. **No site-specific logic** in the app. Site support lives exclusively in
   theme adapters (see [BlankGrimoire-themes](https://github.com/BlankGrimoire/BlankGrimoire-themes)).
3. **No circumvention.** Code must not bypass authentication, paywalls, DRM
   or access controls.
4. **Attribution is preserved.** Never strip the original site's name, logo,
   credits or credit pages.
5. **Screenshots use mock or public-domain content only.**

## Development setup

Requirements: macOS, Xcode 16+, Swift 6, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
make gen    # generate BlankGrimoire.xcodeproj
make test   # run package tests with `swift test`
```

The `.xcodeproj` is **generated and never committed**. To add files or
targets, edit `project.yml` or `Packages/ReaderCore/Package.swift`.

## Architecture rules

Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) first. In short:

- `Domain` depends only on Foundation.
- `Features` depends only on `Domain` and `DesignSystem`: views never import
  `PluginEngine`, `Persistence`, `Networking` or `ImagePipeline`.
- Only the `App` target wires concrete implementations (composition root).
- `PluginEngine/Runtime/Resources/runtime.js` and the contract fixtures are
  **vendored from the SDK**: never edit them by hand, use `make sync-sdk`.

Significant architectural changes require an ADR in `docs/ADR/`.

## Code style

- Swift 6 language mode with **strict concurrency** enabled.
- Format with `swift format` (bundled with the Swift 6 toolchain).
- Prefer `struct` and `actor` over classes; types crossing isolation
  boundaries must be `Sendable`.
- No force unwraps outside tests, except for documented invariants.
- Every source file starts with the MPL-2.0 header:

```swift
// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
```

## Tests

- Every PR that changes behavior must add or update tests.
- Engine tests use **fake plugins and mock servers only**: no network access
  to real websites.
- `ContractTests` must stay green: if they fail, the SDK contract changed.

## Workflow

1. Open an issue first for non-trivial changes.
2. Create a branch: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`.
3. Use [Conventional Commits](https://www.conventionalcommits.org/)
   (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, `ci:`).
4. The PR title (Conventional Commits) determines the version bump and the changelog. Mark breaking changes with `!` (e.g. `feat!:`).
5. Open a PR and fill in the template. PRs are squash-merged.

## License

By contributing, you agree that your contributions are licensed under the
[Mozilla Public License 2.0](LICENSE).