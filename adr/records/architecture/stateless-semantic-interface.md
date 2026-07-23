---
id: architecture.stateless-semantic-interface
status: accepted
scope: architecture
decision_type: quality-attribute
applies_to:
  - crates/rebecca-cli
  - host
  - schemas/protocol-v1.json
  - README.md
summary: Agent-facing semantic actions are request-scoped and stateless; they resolve a window and locator afresh, reject ambiguity, and preserve low-level commands.
constrains: []
depends_on:
  - architecture.input-strategy
  - architecture.privileged-host-boundary
supersedes: []
superseded_by: []
last_reviewed: "2026-07-23"
---

# Stateless semantic interface

## Decision question

How should Rebecca expose agent-friendly interaction without introducing persistent sessions or server-side target handles?

## Current decision

Rebecca MUST keep its agent-facing semantic operations stateless and request-scoped. A semantic action request MUST include its app/window target and element locator. The host MUST resolve the target and locator from current state during that request, execute only when exactly one element matches, and reject missing or ambiguous matches. Existing low-level observation and input commands remain available for precise workflows and debugging.

Semantic actions MUST preserve the input strategy from `architecture.input-strategy`: element actions attempt AX first and use activation/CGEvent only through the existing fallback path. Actions that accept postconditions MUST report event dispatch (`executed`) separately from observed state (`verified`). Navigation, waiting, and scroll-to-visible operations MUST perform their resolution and verification within the same request.

## Context and forces

An agent should not have to carry a server-issued target handle or manually coordinate an observation revision across commands. A persistent session would simplify some races but would add lifecycle, cleanup, and concurrency semantics to a tool that should remain a stateless local primitive. The existing low-level interface is precise but verbose and easy to mis-target when an app has multiple windows.

## Invariants

- Semantic requests carry their app/window target and locator in the request.
- The host retains no semantic session or target handle after the request completes.
- Missing or ambiguous targets and elements are explicit failures; the host never chooses an arbitrary match.
- Low-level tree, find, and element-id commands remain available.
- Element actions retain the AX-first input priority from `architecture.input-strategy`.

## Alternatives and trade-offs

Persistent sessions and server-side handles could reduce repeated resolution and improve optimistic concurrency, but they make lifetime and recovery part of the protocol. Request-scoped resolution is simpler and keeps the host stateless, at the cost of races when the UI changes between requests. Locator-only actions can be ambiguous, so exact-one matching is required.

## Consequences

- The host does not retain sessions, target handles, or locator state between requests.
- Window and element resolution can race with external UI changes; requests fail explicitly when the current state is missing or ambiguous.
- Semantic actions are easier for agents to call, while low-level commands remain the escape hatch for unusual interfaces.
- Postcondition waits consume the request timeout; callers do not receive a persistent waiter or background task.
- The protocol can add request-scoped commands without changing the lifetime of the local socket host.

## Enforcement

CLI integration tests verify exact semantic request arguments, low-level API compatibility, and action response validation. Host tests and macOS acceptance tests verify numeric window targeting and rejection of zero or multiple locator matches. README examples document the request-scoped contract.

## Revisit when

Revisit if reliable cross-request optimistic concurrency or browser/document adapters require a protocol-level snapshot token; such a token must remain optional and must not turn the host into a session store.
