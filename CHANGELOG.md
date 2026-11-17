# Changelog

## [2.0.0](https://github.com/BlankGrimoire/BlankGrimoire-iOS/compare/v1.3.0...v2.0.0) (2026-11-17)

### ⚠ BREAKING CHANGES

* the schema changed without a migration stage, so an
existing store cannot be opened. Remove the app from the device before
installing this build; the fresh container creates the new schema.

* feat(library): flag chapters added since the last visit

With no push notifications yet, the only way to notice a new chapter was to
open the series. The library card now shows an "N new" badge for chapters
that appeared after the user last looked at the chapter list.

Each series stores the newest chapter it had when the list was last opened;
opening the detail (or refreshing it) moves the marker, so the badge clears
as soon as the chapters are seen. A series without a marker starts fully
seen, which covers both a fresh import and libraries stored before this
field existed.

The field is additive but still changes the schema: this build needs the
same container reset as the previous one, not an additional one.

* refactor(persistence): drop local download support

Chapters and pages carried a download flag, a local path and a page count
for offline copies, plus repositories, UI badges and file-cleanup code that
kept them in sync. Nothing produced those files, so the state could only
ever be stale, and it complicated the schema ahead of sync.

Only the image cache remains: pages expire on their TTL and are fetched
again, without an offline copy.

* feat(persistence): support prose content and sync metadata

Two schema additions that were not representable before:

Prose. A series now carries a `ContentKind` (comic, novel, book) and prose
chapters own a `ChapterContentEntity` with the fetched body, its format and
a word count. Reading progress and bookmarks gained an optional
`textOffset`, because prose has no pages to index. Text is fetched on
demand and cached; there is no file download path.

Sync. Every synced record now carries `updatedAt`, and deletions write a
`SyncTombstoneEntity` so a merge cannot resurrect a series removed on
another device. Deleting a series records its chapters, progress and
bookmarks too. Pages and cached chapter text stay out of sync on purpose:
they are derived data that any device can fetch again.
* the schema changed without a migration stage; an existing
store cannot be opened. Remove the app before installing this build.

* docs(persistence): state that prose is HTML-only

`ContentKind.book` could be read as EPUB/PDF support. It means a single HTML
document exposed as one chapter; the app never opens files, and no download
path is planned.

* refactor(persistence): keep only comic and novel content kinds

`book` was never produced by any importer and only added a third value to
reason about. Content is now either image pages or HTML prose.

The removed raw value decodes as `comic`, so a store written by the
development build that had it still opens instead of failing to read the
series.

* feat(contract): align with text chapters in the adapter contract

The SDK now describes prose series: `details.contentKind`, a
`content` dispatch method returning `ChapterContent`, and manifest
`contentKinds`. The app can decode all of it.

- `ContentKind` uses the contract wire values (`image`/`text`) so no
  mapping layer is needed; unknown values still fall back to comics.
- `MangaDetails.contentKind` is applied on import, and a refresh that
  stops declaring it keeps the stored kind instead of downgrading a
  novel to a comic.
- `AdapterManifest.contentKinds` decodes with an empty default, so
  existing manifests stay valid.
- `ChapterContent`/`ChapterText` mirror the contract payload; the body is
  documented as untrusted markup to sanitise before rendering.
- `TextFormat.plain` becomes `text` to match the contract, still
  accepting the old value.
- `ChapterContentEntity.characterCount` and `fraction(forOffset:)` define
  the chapter percentage over characters, not rendered pages.
- `MangaEntity.updateReadingPosition(chapterId:chapterFraction:)` lets a
  text reader report its fraction while the series progress stays
  chapter-based.

* chore(sdk): sync the runtime and fixtures to 1.5.0

Brings in the text-chapter contract: the runtime now answers
`dispatch('content')`, and the fixtures include ChapterContent,
ContentStrategy and MangaDetails with a text content kind.

### Features

* end-of-chapter detection, prose schema and SDK 1.5.0 ([#35](https://github.com/BlankGrimoire/BlankGrimoire-iOS/issues/35)) ([a41428a](https://github.com/BlankGrimoire/BlankGrimoire-iOS/commit/a41428af58820abe56387e80945e209df106c723))

## [1.3.0](https://github.com/BlankGrimoire/BlankGrimoire-iOS/compare/v1.2.3...v1.3.0) (2026-11-17)

### Features

* polish the reader, library, sites and palettes ([#34](https://github.com/BlankGrimoire/BlankGrimoire-iOS/issues/34)) ([003a358](https://github.com/BlankGrimoire/BlankGrimoire-iOS/commit/003a358627feaee8bd4885eddcdc7c01e159bb10))

## [1.2.3](https://github.com/BlankGrimoire/BlankGrimoire-iOS/compare/v1.2.2...v1.2.3) (2026-11-17)

### Bug Fixes

* run the hidden verification pass and open the challenge sheet ([#32](https://github.com/BlankGrimoire/BlankGrimoire-iOS/issues/32)) ([c5e5ea3](https://github.com/BlankGrimoire/BlankGrimoire-iOS/commit/c5e5ea33ff55bc74712330636679f5b36f67f95a))

## [1.2.2](https://github.com/BlankGrimoire/BlankGrimoire-iOS/compare/v1.2.1...v1.2.2) (2026-11-16)

### Bug Fixes

* stop treating injected Cloudflare scripts as a challenge ([#31](https://github.com/BlankGrimoire/BlankGrimoire-iOS/issues/31)) ([2f32bd1](https://github.com/BlankGrimoire/BlankGrimoire-iOS/commit/2f32bd1d0ff1b422546489fbb46354cb9926a9db))

## [1.2.1](https://github.com/BlankGrimoire/BlankGrimoire-iOS/compare/v1.2.0...v1.2.1) (2026-11-16)

### Bug Fixes

* keep challenge cookies and web view state for theme detection ([9c73324](https://github.com/BlankGrimoire/BlankGrimoire-iOS/commit/9c73324b2e42351c38fba84e61c2a00f7003e924))

## [1.2.0](https://github.com/BlankGrimoire/BlankGrimoire-iOS/compare/v1.1.0...v1.2.0) (2026-11-16)

### Features

* let adapter hooks reach declared api hosts ([f002c87](https://github.com/BlankGrimoire/BlankGrimoire-iOS/commit/f002c8718eece97a1d765e8e65c3f287c0ccc169))

## [1.1.0](https://github.com/BlankGrimoire/BlankGrimoire-iOS/compare/v1.0.0...v1.1.0) (2026-11-15)

### Features

* publish a sideloading IPA, a SideStore source and a README showcase ([#23](https://github.com/BlankGrimoire/BlankGrimoire-iOS/issues/23)) ([58e0c3f](https://github.com/BlankGrimoire/BlankGrimoire-iOS/commit/58e0c3f2374ef95cf68ce042b55a1d6de759f12c))

## 1.0.0 (2026-11-14)

### Features

* release iOS quality milestone ([#18](https://github.com/BlankGrimoire/BlankGrimoire-iOS/issues/18)) ([f0075a0](https://github.com/BlankGrimoire/BlankGrimoire-iOS/commit/f0075a019e95590e8a05fc87eb865fa57ebc1f36))

### Bug Fixes

* pin a conventional-changelog preset compatible with the release writer ([cbf0381](https://github.com/BlankGrimoire/BlankGrimoire-iOS/commit/cbf03813693d664b03c27bfefa8d627aa772b339))
