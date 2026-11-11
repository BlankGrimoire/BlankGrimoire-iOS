# 0002 — Declarative theme adapters instead of site-specific scrapers

- **Status:** Accepted
- **Date:** 2025

## Context

BlankGrimoire is an empty container: it ships without content, sources or
pre-configured websites. Hardcoding scrapers for individual sites would make
the app site-specific, require an app release for every broken selector and
blur the project's positioning.

## Decision

Site support is delivered as signed **theme adapters** that describe detection
signals (`ThemeSignature`) and CSS extraction selectors. The app:

- loads adapters in an isolated JavaScriptCore runtime;
- detects the adapter by scoring the page and breaks ties deterministically;
- stores only the adapter id/version and optional selector overrides in a
  `SiteProfile`;
- lists adapters through local and remote `ThemeSource` implementations, with
  Ed25519 signature verification and trust-on-first-use for repository keys.

The adapter contract, runtime and release tooling belong to
[BlankGrimoire-sdk](https://github.com/BlankGrimoire/BlankGrimoire-sdk); the
official adapters belong to
[BlankGrimoire-themes](https://github.com/BlankGrimoire/BlankGrimoire-themes).

## Consequences

- The app contains no site-specific logic; adding or fixing a site is an
  adapter release, not an app release.
- Every adapter must implement the same versioned contract (`apiVersion`).
- Sites that cannot be expressed declaratively are out of scope instead of
  receiving a bespoke scraper.
- The runtime is a security boundary: one `JSVirtualMachine` per adapter, no
  direct network or file-system access, requests through a host allowlist.
