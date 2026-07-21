---
id: architecture.privileged-host-boundary
status: accepted
scope: architecture
decision_type: security-boundary
applies_to:
  - crates/rebecca-cli
  - host
  - schemas/protocol-v1.json
summary: An unprivileged CLI delegates protected macOS operations to a same-user app host over a versioned local socket.
constrains: []
depends_on: []
supersedes: []
superseded_by: []
last_reviewed: "2026-07-20"
---

# Privileged host boundary

## Decision question

How do the command-line client and the permission-bearing macOS process divide responsibility and communicate?

## Current decision

`rebecca` MUST remain an unprivileged Rust CLI. `Rebecca.app` MUST be the only component that calls protected macOS GUI and screen APIs. The two processes MUST communicate through a versioned, same-user Unix-domain-socket protocol using length-prefixed JSON. Version 1 observation responses MUST keep command-specific result fields at the top level, alongside `protocol_version`, `request_id`, and `ok`; they MUST NOT introduce a generic `result` envelope. Successful observation responses MUST include a monotonically increasing `revision` that identifies the returned snapshot.

## Context and forces

The tool must be shell-callable without granting Terminal or arbitrary CLI processes Accessibility or Screen Recording privileges. Local clients are not automatically trusted, so the transport needs explicit access controls and a protocol contract.

## Invariants

- CLI code does not link or invoke protected macOS permission APIs.
- Protected operation requests cross the local protocol boundary.
- Protocol requests include `protocol_version` and `request_id`.
- The runtime directory is mode `0700` and its socket is mode `0600`.
- The host accepts only its logged-in user's peers; later milestones add peer-PID, executable audit, and connection nonce enforcement.
- Version 1 observation responses use command-specific top-level result fields rather than a generic `result` envelope.
- Successful observation responses include a monotonically increasing snapshot `revision`; identifiers returned by an observation are valid only within that revision until a later milestone defines a narrower lifetime.
- ScreenCaptureKit-backed observation and capture requests run only in the host and require the host app's Screen Recording permission; the host returns `permission_denied` without creating output when that permission is unavailable.
- The host is responsible for ScreenCaptureKit/ImageIO capture and publishes PNG output through a same-directory temporary file and exclusive finalization; an existing requested output is never overwritten.

## Alternatives and trade-offs

Direct CLI access would be simpler but violates the permission boundary. XPC would provide stronger native identity facilities but is deferred to keep initial CLI compatibility and implementation scope small.

## Consequences

The app host and CLI are separately built artifacts. Protocol tests can use a mock host without TCC permissions, while native tests exercise the app host on a prepared macOS runner.

## Enforcement

`rebecca-protocol` tests validate protocol framing and schemas, including the command-specific observation response shapes. CLI integration tests use a mock socket and verify revision correlation. Host integration tests check runtime file modes, status behavior, native observation snapshots, and no-overwrite PNG publication. Code review rejects protected macOS API imports from CLI crates.

## Revisit when

Revisit if macOS code-signature client authentication becomes required, sandboxing prevents the socket design, or an XPC transport is needed for reliability or distribution.
