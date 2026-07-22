# Rebecca

Rebecca is a macOS computer-use tool with a command-line client and a
permission-bearing `Rebecca.app` host. The app performs protected macOS
operations; the `rebecca` CLI provides the user-facing commands.

macOS 15+ on Apple Silicon (`arm64`) is required.

## Install

Install the signed and notarized release from the Homebrew tap:

```sh
brew tap jwoo0122/tap
brew install --cask jwoo0122/tap/rebecca
```

The cask installs `Rebecca.app` and exposes the bundled `rebecca` command.

Grant **Accessibility** and **Screen Recording** permission to:

```text
/Applications/Rebecca.app
```

Then check the host:

```sh
rebecca status
```

The CLI automatically starts the installed app and replaces an older or
unrelated Rebecca host that owns the local socket. For local development, set
`REBECCA_APP_PATH` to the development app bundle.

## Commands

### Status

```sh
rebecca status
rebecca status --json
```

Reports host status and Accessibility / Screen Recording permission state.

### Displays

```sh
rebecca displays
rebecca displays --json
```

Lists connected displays and their logical frames, pixel sizes, and scale
factors. Requires Screen Recording permission.

### Windows

```sh
rebecca windows
rebecca windows --app com.apple.TextEdit
rebecca windows --json
```

Lists visible windows. Use `--app` to filter by bundle identifier. Requires
Screen Recording permission.

### Capture

```sh
rebecca capture \
  --window-id 123 \
  --output /tmp/window.png
```

Captures one window as a PNG. Existing output files are not overwritten.
Requires Screen Recording permission.

### Common options

```text
--json       Emit one JSON object to stdout
--no-start   Do not launch Rebecca.app automatically
--socket     Use a specific Unix socket
--timeout    Set the host/socket timeout, for example 250ms or 2s
--verbose    Print connection diagnostics to stderr
```

## Development

Build and test the Rust components:

```sh
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test --all-features --locked
```

Build and verify the local app bundle:

```sh
./scripts/build-macos-app.sh
./scripts/verify-macos-app.sh dist/Rebecca.app
```

The release workflow runs from `main` for release-worthy Conventional Commits:

- `feat` → minor release
- `fix` and `perf` → patch release
- `BREAKING CHANGE` or `!` → major release
- `docs`, `test`, `ci`, and `chore` alone → no release

Each release is signed, notarized, stapled, published to GitHub Releases, and
published to the Homebrew tap.
