# BlankGrimoire for iOS

> A native, ad-free reader and personal library for the content **you** bring.

BlankGrimoire is an **empty container**. It ships with no content, no sources
and no pre-configured websites. Users add the websites they already visit; the
app recognizes common site structures through open-source *theme adapters* and
gathers everything in a single, private library.

> ⚠️ **Status:** early development. Nothing here is usable yet.

## Features (planned)

- 📚 **Unified library**: all your series in one place, from any site you add
- 🔖 **Reading progress**: resume exactly where you left off
- 📖 **Native reader**: smooth vertical/paged reading with aggressive prefetching
- 🔎 **Cross-site search**: query every enabled site, then load more results
  page by page following each site's own pagination
- 🚫 **Ad-free**: only the content, with full attribution to the original site
- 🧩 **Theme adapters**: one adapter supports every site built on the same theme
- ☁️ **iCloud sync** across iPhone and iPad (planned)

## Requirements

- Xcode 16+ · iOS 17+ · Swift 6
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

```bash
git clone git@github.com:BlankGrimoire/BlankGrimoire-iOS.git
cd BlankGrimoire-iOS
make gen              # generates BlankGrimoire.xcodeproj (not versioned)
make lint             # swift-format check
make test-readercore  # ReaderCore package tests (fast, no simulator)
make test             # app tests on the default iPhone simulator
open BlankGrimoire.xcodeproj
```

`make test-readercore` builds outside iCloud by default
(`READERCORE_SCRATCH=~/Library/Caches/BlankGrimoire/ReaderCoreBuild`). Point it
elsewhere with `READERCORE_SCRATCH=/path` if needed.

## Project structure

ReaderCore is a single SwiftPM target; its folders are organisational, not
separate modules.

| Path | Purpose |
|---|---|
| `BlankGrimoire/` | App target: entry point, composition root (`AppComposition`) and `Info.plist` |
| `Packages/ReaderCore/Sources/ReaderCore/Domain` | Contract DTOs (`ContractModels.swift`) and URL value types |
| `Packages/ReaderCore/Sources/ReaderCore/PluginEngine` | JavaScriptCore runtime, HTML bridge, HTTP policy, theme detection and sources |
| `Packages/ReaderCore/Sources/ReaderCore/Persistence` | SwiftData entities/schema, repositories and the signed adapter store |
| `Packages/ReaderCore/Sources/ReaderCore/ImagePipeline` | Image cache and prefetching |
| `Packages/ReaderCore/Sources/ReaderCore/Features` | SwiftUI views, view models, dependency composition and the adapter session pool |
| `Packages/ReaderCore/Sources/ReaderCore/DesignSystem` | Design tokens and shared styling |
| `Packages/ReaderCore/Tests/ReaderCoreTests` | Package tests, localization checks and the vendored contract fixtures |

The remote theme repository defaults to the official GitHub Pages index. A
build can override it with the `BlankGrimoireThemesRepositoryURL` key in
[`BlankGrimoire/Info.plist`](BlankGrimoire/Info.plist) without changing code.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.

## SDK runtime

`runtime.js` and the contract fixtures are vendored from
[BlankGrimoire-sdk](https://github.com/BlankGrimoire/BlankGrimoire-sdk).
[`.sdk-version`](.sdk-version) records the pinned release and
[`sdk-assets.sha256`](sdk-assets.sha256) its checksums.

```bash
make sync-sdk                            # from a local checkout (../BlankGrimoire-sdk)
make sync-sdk-release                    # from the GitHub release for .sdk-version
make verify-sdk                          # re-check the vendored files
```

`make sync-sdk` never changes the pinned version unless you pass
`SDK_VERSION=<version>`. Update `.sdk-version`, run `make sync-sdk-release`,
commit the generated files and the pin together.

## Related repositories

- [BlankGrimoire-sdk](https://github.com/BlankGrimoire/BlankGrimoire-sdk): adapter contract, runtime and tooling
- [BlankGrimoire-themes](https://github.com/BlankGrimoire/BlankGrimoire-themes): official theme adapters

## Contributing

Contributions are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

[Mozilla Public License 2.0](LICENSE). Third-party components are listed in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## Disclaimer

BlankGrimoire does not host, provide or link to any content.
Read the full [DISCLAIMER](DISCLAIMER.md).