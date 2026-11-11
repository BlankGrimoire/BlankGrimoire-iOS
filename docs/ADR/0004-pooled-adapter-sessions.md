# 0004 — Reuse adapter sessions with reference-counted leases

- **Status:** Accepted
- **Date:** 2026-11-11

## Context

Opening an adapter creates a `JSVirtualMachine`, evaluates the vendored runtime
and the adapter bundle. Doing that for every chapter page and every search hit
was the dominant cost reported in SES-02, and it also discarded any warm
JavaScript state between consecutive operations.

## Decision

`AdapterSessionPool` caches sessions on the main actor, keyed by
`(siteProfileID, themeID, adapterVersion)`:

- Callers `acquire` a `Lease` and `release` it in a `defer`. Releases only
  decrement the in-use counter; the session stays warm.
- Concurrent acquires for the same key await one shared opening task.
- A session is disposed when it has been idle for ten minutes, when a different
  adapter version is installed, when the profile configuration (URL, headers,
  selector overrides) changed, when `invalidate` runs on adapter update or
  uninstall, and when `invalidateAll` runs after a memory warning.
- `ChapterPagesProvider` and `SiteCatalogService` hold a pool each and never
  dispose a session they did not open.

## Consequences

- Chapter pages and repeated searches reuse the same runtime, which removes the
  per-operation JavaScriptCore start-up cost.
- Memory stays bounded by the idle TTL and the memory-warning hook.
- Session identity includes the adapter version, so a stale adapter can never
  serve requests after an update.
