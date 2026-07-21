---
id: architecture.input-strategy
status: accepted
scope: architecture
decision_type: quality-attribute
applies_to:
  - crates/rebecca-cli
  - host
  - requirements.md
summary: Input commands prioritize AX actions over CGEvent to minimize window activation and preserve user cursor control.
constrains: []
depends_on:
  - architecture.privileged-host-boundary
supersedes: []
superseded_by: []
last_reviewed: "2026-07-21"
---

# Input strategy

## Decision question

How should the tool inject user input to balance reliability with the user's ability to continue using the computer during automation?

## Current decision

Input commands MUST follow a three-tier priority:

1. AX action (`AXPress`, `AXSetValue`) without window activation, attempted first for all element-based operations.
2. Window activation followed by AX action retry, only when the first tier fails because the target app requires a frontmost window.
3. CGEvent coordinate-based injection, used only when AX action is unavailable for the target element or when the operation is inherently coordinate-based (drag, canvas, scroll on non-AX surfaces).

The host MUST NOT activate a window when AX action succeeds in the background. The host MUST attempt AX action before any CGEvent path. The CLI MUST expose both element-based and coordinate-based interfaces so callers can target elements by ID when possible.

## Context and forces

CGEvent injection moves the real system cursor and requires the target window to be frontmost, preventing the user from operating the computer during automation. AX actions can operate on background windows without touching the cursor, but do not work on elements that lack accessibility support (canvas, custom drawing, some web content). A pure CGEvent approach is reliable but invasive; a pure AX approach is non-invasive but incomplete.

## Invariants

- AX action is always attempted before CGEvent for element-based operations.
- Window activation is never performed when AX action succeeds without it.
- CGEvent is only used when AX action is unavailable or the operation is inherently coordinate-based.
- The input method used is reported in the action response so callers can distinguish paths.
- Protected macOS input APIs (AXUIElement, CGEvent) are called only in the Swift host, never in the Rust CLI.

## Alternatives and trade-offs

CGEvent-only is simpler and universally applicable but blocks user interaction during automation. AX-only is non-invasive but cannot handle coordinate-based operations. The three-tier approach adds implementation complexity and fallback logic but maximizes the range of operations the user can observe without losing control of the computer.

## Consequences

M3 (tree, find, element ID) must be implemented before M2 (input) because AX-based input requires element identification. The action response must report which input path was used. Some operations will still require CGEvent and window activation, so the user experience is improved but not perfect.

## Enforcement

CLI integration tests verify that element-based clicks use the AX path when available. Host unit tests verify AX action is attempted before CGEvent. Code review rejects CGEvent imports in CLI crates. Requirements §7.1.1 documents the priority order.

## Revisit when

Revisit if macOS provides a non-invasive coordinate-based input API, if AX action reliability changes significantly across macOS versions, or if sandboxing prevents the AX fallback path.
