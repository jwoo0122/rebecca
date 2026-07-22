# Rebecca — Milestone 1 (`windows`/`capture` slice)

A macOS 15+ / Apple Silicon-only foundation for a `rebecca` CLI and a
permission-bearing `Rebecca.app` host. Milestone 0 provides `status`, and
Milestone 1 currently provides `displays`, filtered `windows`, and single-window
PNG `capture`: the Rust CLI asks the local app host for ScreenCaptureKit-backed
observations over a versioned, length-prefixed JSON Unix socket.

## Build prerequisites

- macOS 15 or later on Apple Silicon (`arm64`)
- Rust 1.93.0 (pinned in `rust-toolchain.toml`)
- Apple Command Line Tools with `swiftc`

The build configuration explicitly sets `MACOSX_DEPLOYMENT_TARGET=15.0` and
builds `aarch64-apple-darwin` / `arm64` only.

## Install

Signed and notarized releases are published through the Homebrew tap:

```sh
brew tap jwoo0122/tap
brew install --cask jwoo0122/tap/rebecca
rebecca status
```

The cask installs `Rebecca.app` and exposes the bundled `rebecca` CLI. The CLI
checks that the socket belongs to this installed host and automatically replaces a
stale or older Rebecca host after an app update. For local development, set
`REBECCA_APP_PATH` to the development app bundle before invoking the CLI.

## Build and test

```sh
cargo fmt --check
cargo test
cargo build --workspace
scripts/test-host.sh
scripts/build-app.sh
scripts/build-fixture.sh
# After granting Screen Recording to the rebuilt bundle:
scripts/test-displays-app.sh
scripts/test-windows-capture-app.sh
```

The app builder creates `build/Rebecca.app`. To exercise it locally, copy
that app to `/Applications` (or launch its executable directly), then run:

```sh
open build/Rebecca.app
cargo run -p rebecca-cli -- status --json --no-start
cargo run -p rebecca-cli -- displays --json --no-start
cargo run -p rebecca-cli -- windows --app dev.jwoo0122.rebecca-fixture --json --no-start
```

For socket tests or a development host, pass an explicit path:

```sh
rebecca status --json --no-start --socket /tmp/rebecca-test.sock
```

Without `--no-start` and without `--socket`, the CLI tries `open -a
Rebecca` if the default host socket is unavailable. The default socket is:

```text
~/Library/Application Support/Rebecca/runtime/control.sock
```

## JSON and exits

`--json` emits exactly one JSON object on stdout. `status` output includes
`protocol_version`, `request_id`, host details, permissions, and
`emergency_stop`. `displays` and `windows` output includes a snapshot
`revision`. Display output includes global logical frames, pixel sizes, scale
factors, and primary-display flags. Window output includes bundle filtering,
window IDs, titles, frames, onscreen state, and nullable AX-dependent focus
metadata. Capture output includes PNG path, target, pixel size, logical frame,
scale factor, and revision. Errors are `{ "ok": false, "error": ... }`.

The CLI maps invalid input to exit 2, unavailable host to exit 3, IPC errors to
4, and protocol mismatch to 11. It also maps host error codes to the documented
Milestone exit-code set (permission denied through security rejection).

The v1 request/response schema is at `schemas/protocol-v1.json`. Frames are a
four-byte big-endian payload length followed by UTF-8 JSON, with a 64 KiB
maximum payload.

## Security boundary

The Rust CLI has no AppKit, Accessibility, CoreGraphics, or Screen Recording
API calls. Only the Swift host calls protected APIs, including
`AXIsProcessTrusted`, `CGPreflightScreenCaptureAccess`, and ScreenCaptureKit.
The host creates its per-user runtime directory with mode `0700`, its socket with
mode `0600`, and rejects peers whose UID differs from the current user.

## Current limitations

- Milestone 1 currently implements `displays`, filtered `windows`, and
  single-window PNG `capture`. `apps`, full `focused` semantics, the complete
  fixture UI, and input remain pending.
- `displays`, `windows`, and `capture` require Screen Recording permission on
  `Rebecca.app` and return `permission_denied` without it.
- The current windows slice reports AX-dependent `focused` state as `null` and
  only reports `minimized: false` for visible windows; richer AX semantics are
  deferred.
- Capture refuses to overwrite an existing output path and currently supports
  PNG window output only.
- A non-granted non-prompt preflight result is reported as `unknown`, because it
  cannot distinguish TCC denial, `not_determined`, or `restricted`.
- The accessory AppKit host shows a status window on launch with non-prompt
  Accessibility, Screen Recording, and service state.
