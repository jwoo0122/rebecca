---
id: architecture.input-strategy
status: accepted
scope: architecture
decision_type: quality-attribute
applies_to:
  - crates/rebecca-cli
  - host
  - resources/SKILL.md
summary: Input commands prefer background AX actions and target-process CGEvent routing with an explicit window target, while preserving the user's frontmost application and focus when possible.
constrains: []
depends_on:
  - architecture.privileged-host-boundary
supersedes: []
superseded_by: []
last_reviewed: "2026-07-24"
---

# Input strategy

## Decision question

How should the tool inject user input to balance reliability with the user's ability to continue using the computer during automation?

## Current decision

Input commands MUST follow this priority:

1. AX action (`AXPress`, `AXSetValue`) without window activation, attempted first for all element-based operations.
2. Target-process event injection using the target window's owner PID for coordinate-based or keyboard operations that cannot use AX. The caller MUST provide `window_id`; the host MUST resolve its owner PID from a current window snapshot and MUST NOT fall back to the global event stream when the target is missing or stale.
3. Explicit application activation remains available only through the `activate` command and is not an implicit action fallback.

For target-process input, the host MUST capture the user's frontmost application before the action, route synthesized events to the target PID, observe the resulting focus state, and restore the previous frontmost application if the target action changed it. The host MUST report the input method used in the action response.

The CLI MUST expose element-based interfaces and coordinate/window-targeted interfaces so callers can use AX elements or an explicit window ID. Coordinate and un-targeted keyboard actions MUST require `window_id`.

## Context and forces

CGEvent injection can be reliable for canvas, custom drawing, and other surfaces that lack useful accessibility actions, but global event posting moves or affects the user's active session. macOS also provides process-targeted event posting and event taps. These can route synthesized input to a target application's event stream without using the global event stream, but target applications may still require activation or have app-specific behavior. AX actions are non-invasive when supported, but incomplete for custom UI.

## Invariants

- AX action is always attempted before synthesized event input for element-based operations.
- AX failure never implicitly activates the target application.
- Target-process input requires a positive `window_id` and a resolvable owner PID.
- Target-process input uses `CGEventPostToPid` or an equivalent host-only target-PID path; global `CGEventPost` is not a fallback for targeted actions.
- The host captures and protects the user's frontmost application around targeted input and restores it if changed.
- The input method used is reported in the action response.
- Protected macOS input APIs (AXUIElement, CGEvent) are called only in the Swift host, never in the Rust CLI.

## Alternatives and trade-offs

Global CGEvent injection is broadly compatible but moves the user's cursor and competes with user input. AX-only input is non-invasive but cannot handle all custom UI. Target-process event routing adds target resolution, focus management, and app-specific compatibility work, but reduces user-session impact while retaining a fallback for non-AX surfaces. A separate isolated desktop remains the strongest option when an application cannot accept background target-process events.

## Consequences

Window observation must precede coordinate or un-targeted keyboard actions so callers can provide a valid `window_id`. Targeted input must be tested against a background fixture while a separate sentinel application remains frontmost. Some applications may reject process-targeted events or require activation; those failures must be explicit rather than silently routed to the user's current app.

## Enforcement

CLI integration tests verify that targeted action requests carry `window_id`. Host tests verify target PID resolution, target-process event posting, AX-before-event ordering, and no implicit activation. Native acceptance tests verify that a background fixture changes state while the sentinel application's frontmost and focus state are restored. Code review rejects global event fallback for targeted actions and protected API imports in CLI crates.

## Revisit when

Revisit if process-targeted events are unreliable across the supported macOS/app matrix, if macOS provides a stable non-invasive coordinate API, or if isolated execution becomes the default for unsupported applications.
