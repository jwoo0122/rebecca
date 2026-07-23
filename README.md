<p align="center">
  <img src="icon.png" alt="Rebecca icon" width="80">
</p>

<h1 align="center">Rebecca</h1>

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

### Targeted input

Coordinate and un-targeted keyboard actions require an explicit window target. Get a `window_id` from `rebecca windows`; the host routes synthesized events to that window's owner process instead of the global event stream.

```sh
rebecca click --window-id 123 --x 100 --y 200
rebecca key --window-id 123 --chord "cmd+a"
rebecca type --window-id 123 --text "hello"
```

Element-based `click` and `type` continue to use Accessibility actions and require their observation revision.

### Semantic actions

Semantic actions are stateless and request-scoped. Each request includes its
application or window target and resolves elements from the current
accessibility tree. Rebecca never creates a session or server-side target
handle. An action runs only when its locator matches exactly one element;
missing, ambiguous, or truncated matches fail explicitly. Low-level commands
such as `find` and `press` remain available.

Press one uniquely located element and verify the resulting page state:

```sh
rebecca act \
  --window-id 2939 \
  --action press \
  --role AXLink \
  --label "에덴의 문" \
  --expect-title "에덴의 문" \
  --wait-ms 2000 \
  --timeout 3s
```

Navigate without manually composing address-bar key events:

```sh
rebecca navigate \
  --window-id 2939 \
  --url https://jinwoojeo.ng/posts \
  --expect-url https://jinwoojeo.ng/posts \
  --wait-ms 2000 \
  --timeout 3s
```

Wait for a URL, title, or uniquely located element:

```sh
rebecca wait-until \
  --window-id 2939 \
  --label "Comments" \
  --wait-ms 3000 \
  --timeout 4s
```

Scroll a uniquely located accessibility element into view:

```sh
rebecca scroll-to \
  --window-id 2939 \
  --label "Comments"
```

Use exactly one of `--app` or `--window-id` as the target. Available element
locators are `--role`, `--label`, `--label-contains`, `--value`, `--enabled`,
and `--focused`. `act` currently supports `--action press`; `navigate`,
`wait-until`, and `scroll-to` are separate semantic operations. Window-targeted
operations require Accessibility and Screen Recording permission. The JSON
response distinguishes event dispatch (`executed`) from state verification
(`verified`) and includes before/after URL and title when available.


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
