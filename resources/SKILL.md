# Rebecca

A macOS GUI automation tool for AI agents. Provides structured observation and input capabilities via the Accessibility API and Core Graphics.

## Core principle

This tool answers one question: **what is currently visible on the macOS GUI, and can I perform a specified observation or input action?**

This tool does **not** decide what to do next. That responsibility belongs to the calling agent (LLM, harness, or user).

## Required usage

All commands must use `--json` for machine-readable output. Non-JSON output is for human diagnostics only.

## Available commands

| Command | Purpose |
|---------|---------|
| `status` | Report host status, permissions, and emergency stop state |
| `displays` | List active displays with coordinate metadata |
| `windows` | List windows, optionally filtered by bundle ID |
| `capture` | Capture a window as PNG |
| `apps` | List running applications |
| `focused` | Report focused app, window, and AX element |
| `tree` | Query the accessibility tree |
| `find` | Search accessibility elements by attribute |
| `press` | Press an AX element (AXPress) |
| `set-value` | Set the value of an AX text field (AXSetValue) |
| `click` | Click an element (AX) or a window-targeted coordinate (CGEvent) |
| `type` | Type text into an element (AX) or a window-targeted field (CGEvent) |
| `key` | Press a key or chord targeted at a window (CGEvent) |
| `move` | Send a window-targeted pointer move (CGEvent) |
| `scroll` | Scroll a window target (CGEvent) |
| `drag` | Drag within a window target (CGEvent) |
| `activate` | Activate an application by bundle ID |
| `window-move` | Move a window to coordinates |
| `window-resize` | Resize a window |
| `window-close` | Close a window |
| `stop` | Emergency stop — block all mutating actions |
| `resume` | Resume after emergency stop |

## Agent loop

1. `status` — verify host is running and permissions are granted
2. `focused` or `windows` — identify the target application
3. `capture` + `tree` — observe the screen and accessibility structure
4. Select target element by ID from tree/find results
5. Perform a single action (`press`, `click`, `type`, etc.)
6. Re-observe (`focused`/`capture`/`tree`) to verify the result
7. Proceed to the next action

## Element ID and revision

- Element IDs are only valid within a specific revision
- Revisions change after actions, window movement, or time-based invalidation
- Using a stale element ID returns `stale_observation` error — re-query the tree
- Always capture a fresh tree before acting on elements

## Coordinate system

All external coordinates are macOS global logical points (not pixels). On Retina displays, 1 logical point = 2 pixels. The `displays` command provides scale factors for conversion.

Coordinate and un-targeted keyboard actions require `--window-id`. Obtain it from `windows`; the host resolves the window owner PID and routes synthesized events to that process. The host never falls back to the global event stream when a target window is missing or stale.

Examples:

```sh
rebecca click --window-id 123 --x 100 --y 200
rebecca key --window-id 123 --chord "cmd+a"
rebecca type --window-id 123 --text "hello"
rebecca drag --window-id 123 --from-x 100 --from-y 200 --to-x 300 --to-y 200
```

## Error handling

- `permission_denied`: Grant Accessibility or Screen Recording permission to `Rebecca.app`
- `stale_observation`: Element belongs to an old revision — re-query the tree
- `target_not_found`: Element or target window not found
- `target_window_required`: A targeted input action is missing `--window-id`
- `emergency_stop`: Mutating actions blocked — run `resume` to continue
- `security_rejection`: Secure text fields reject `type`/`set-value` for safety
- `unsupported`: The element does not support the requested action

## Secure field handling

- Never attempt to type into or set values on secure text fields (passwords)
- The tool will reject these with `security_rejection`
- Screenshots may contain sensitive information — the tool does not mask secure fields

## Emergency stop

- `stop` blocks all mutating actions (click, type, key, move, scroll, drag, activate, window control)
- Observation commands (status, displays, windows, capture, apps, focused, tree, find) remain available
- `resume` restores mutating action capability
- Respect emergency stop state — do not attempt to bypass it

## Important limitations

- `executed: true` means the targeted event was sent or AX action was called, **not** that the intended goal was achieved
- The tool does not verify whether the action achieved the user's intent
- High-risk user actions (deleting files, sending messages, etc.) should be approved by the calling harness
- The tool is a low-level primitive — orchestration and intent verification are the agent's responsibility
