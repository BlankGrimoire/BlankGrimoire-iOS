# 0003 — Read the library index off the main actor

- **Status:** Accepted
- **Date:** 2026-11-11

## Context

The library screen needs to filter and sort the entire collection. Loading
`MangaEntity` objects into `@Observable` state meant a large library blocked
the main actor while SwiftData materialised every row, and SwiftUI held live
model objects that are not `Sendable`.

## Decision

`MangaRepository.fetchLibraryIndex()` returns `[LibraryEntry]`, immutable value
snapshots of the fields the grid renders (`title`, `coverURL`, authors, tags,
status, favorite flag, progress and dates).

- The protocol ships a default implementation that maps `fetchAll()`.
- The SwiftData repository overrides it with `LibraryIndexReader`, a
  `@ModelActor` that fetches on its own `ModelContext` and maps each row to a
  `LibraryEntry` before returning.
- `LibraryViewModel` filters, sorts and renders snapshots only.
- Opening a series goes through `MangaDetailLoaderView`, which fetches one
  entity by id when the detail screen appears.
- Favorites and deletions resolve the entity by id before writing, so the
  store remains the source of truth.

## Consequences

- The main actor never materialises the whole store, and list state is
  `Sendable`.
- Details are fetched lazily per series; a deleted series shows an explicit
  unavailable state instead of a stale row.
- Mutations are two-step (fetch by id, then save), which is acceptable because
  the library view model is the only writer from the grid.
