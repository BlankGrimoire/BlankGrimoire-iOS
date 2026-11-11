# 0001 — Generate the Xcode project with XcodeGen

- **Status:** Accepted
- **Date:** 2025

## Context

`BlankGrimoire.xcodeproj` is a generated project file with unstable ordering
and merge-hostile internals. Editing it by hand makes reviews noisy and lets
build settings drift between contributors and CI.

## Decision

`project.yml` is the source of truth. The `.xcodeproj` is generated with
XcodeGen, ignored by Git, and never committed. Both local setup and CI run
`make gen`.

## Consequences

- Adding files or targets means editing `project.yml` (or
  `Packages/ReaderCore/Package.swift`), not the Xcode UI.
- Fresh checkouts must run `make gen` before building.
- Build settings are reviewable as text and stay identical across environments.
