---
id: architecture.platform-baseline
status: accepted
scope: architecture
decision_type: compatibility
applies_to:
  - Cargo.toml
  - host
  - scripts/build-app.sh
summary: The initial release targets macOS 15 or later on Apple Silicon only.
constrains: []
depends_on: []
supersedes: []
superseded_by: []
last_reviewed: "2026-07-20"
---

# Initial platform baseline

## Decision question

What macOS version and CPU architectures does the first release support?

## Current decision

The initial release MUST support macOS 15 or later on Apple Silicon (`arm64`) only. It MUST NOT claim Intel or universal-binary support.

## Context and forces

The first implementation relies on modern macOS GUI APIs and needs a narrow compatibility and test matrix while the app-host boundary is established.

## Invariants

- Build configuration declares macOS 15 as its deployment target.
- Release documentation and artifacts identify `arm64` support.
- CI and release scripts do not label the output universal or x86_64-compatible.

## Alternatives and trade-offs

A universal binary broadens the install base but adds native dependency, signing, and testing complexity. Supporting older macOS versions risks API availability divergence.

## Consequences

Developers need an Apple-Silicon macOS 15+ environment for native integration testing. A later architecture expansion requires an explicit decision revision and additional CI coverage.

## Enforcement

The app build script sets the deployment target and architecture. Build checks verify the resulting binary architecture. Release review verifies stated support boundaries.

## Revisit when

Revisit when a supported Intel customer segment is established or a validated universal-build pipeline and test matrix are available.
