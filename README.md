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
make gen     # generates BlankGrimoire.xcodeproj (not versioned)
make test    # runs package tests headlessly with `swift test`
open BlankGrimoire.xcodeproj
```

## Project structure

| Path | Purpose |
|---|---|
| `App/` | Thin app target: composition root and resources |
| `Packages/ReaderCore/Sources/Domain` | Entities and protocols, no dependencies |
| `Packages/ReaderCore/Sources/PluginEngine` | JavaScriptCore runtime and theme detection |
| `Packages/ReaderCore/Sources/Persistence` | SwiftData models and repositories |
| `Packages/ReaderCore/Sources/ImagePipeline` | Image cache and prefetching |
| `Packages/ReaderCore/Sources/Features` | SwiftUI views and view models |

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for details.

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