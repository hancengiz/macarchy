# Developing Macarchy

For pull requests and bug reports, start with [CONTRIBUTING.md](../CONTRIBUTING.md).
Run the commands below from the repository root.

## Prerequisites

- macOS 13 or newer.
- Swift 6.2 or newer. Full Xcode 26+ is required for XCTest; a compatible
  Command Line Tools installation is sufficient for release builds.
- Python 3.11+ and Bash 5. macOS's system Bash 3 cannot run the build scripts.
- Git and Homebrew for the setup commands below.

```sh
brew install bash python
export PATH="$(brew --prefix)/bin:$PATH"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift --version
bash --version
```

Adjust `DEVELOPER_DIR` to your full Xcode installation. For build-only work with
Command Line Tools, omit that export. If you use Swiftly, the repository's
`.swift-version` records its toolchain selection.

## Build without changing your desktop

```sh
python3 macarchy/install.py --build-only
.local/macarchy.app/Contents/MacOS/macarchy --version
.local/macarchy.app/Contents/Helpers/macarchy --help
codesign --verify --deep --strict .local/macarchy.app
```

The installer generates command help and version/Git metadata, builds both Swift
executables, packages the default configuration and resources, and signs
`.local/macarchy.app`. It does not install, launch, or replace your running app
in `--build-only` mode.

The installer discovers any valid codesigning identity in your login keychain
(`macarchy-codesign` first, then Developer ID Application, then
any other) and signs with it; pass `--identity <name>` to override. A stable
identity keeps the Accessibility grant across rebuilds. With no identity it
falls back to ad-hoc signing and warns — every reinstall then needs a fresh
Accessibility grant.
Use `--build-version` to override the version embedded in the app and CLI.

## Settings app (fork)

```sh
swift build -c release --product MacarchySettings -Xswiftc -DOMARCHY
.build/release/MacarchySettings
```

GUI settings over the same socket as the CLI. The `-DOMARCHY` flag is
REQUIRED: without it the binary identifies as upstream AeroSpace and looks
for the wrong server socket. Draft-then-commit: edits apply only on Save
(writes the TOML file with comments preserved, then `reload-config`).
Tests: `swift test --filter MacarchySettingsTests`.

## Tests and generated files

After the build above has generated the required files:

```sh
swift test
python3 -m unittest discover -s macarchy -p 'test_*.py'
bash -n macarchy/action
```

If `swift test` reports `no such module XCTest`, select full Xcode rather than
Command Line Tools. Report unavailable checks in the PR rather than claiming
they passed.

For a generation-only bootstrap, or after changing commands:

```sh
./generate.sh --ignore-xcodeproj
```

The script uses Bash 5 from your `PATH`. Command help and descriptions come from
`docs/macarchy-*.adoc`. When changing command syntax, keep those docs,
`grammar/commands-bnf-grammar.txt`, and the argument parser aligned. Regenerate
and include changes to tracked generated files; do not hand-edit generated output.

`./test.sh` is a broader wrapper that also treats build warnings as errors,
checks CLI output, runs lint, and checks for generated-file drift. It is not the
same check set as the current release action.

## Formatting

```sh
./script/install-dep.sh --swiftformat
```

Run `.deps/swiftformat/swiftformat` with the Swift file paths you changed; it uses
the repository's `.swiftformat` configuration. `./format.sh` formats the whole
repository, so avoid committing unrelated formatting changes.

## Debugging and live verification

Open `Package.swift` in Xcode, or use an editor with SourceKit-LSP. After
generation, `swift build` builds the debug executables.
`./build-debug.sh` also builds the test target and stages binaries in `.debug`;
`./run-debug.sh` builds and launches the debug app, and `./run-cli.sh` addresses
it with the debug CLI.

For Xcode launches, selecting **Edit Scheme → Options → Console → Terminal**
can make Accessibility permission apply to the terminal hosting the debug
process. Check the actual permission state on your system.

Do not run two window managers at once. Use a disposable config and test windows
for layout experiments; never include personal session data, app bundles,
signing credentials, or unredacted window titles in a PR. Keep a backup before
testing installation with `python3 macarchy/install.py --build`.

For layout, Settings, shortcut, or restart changes, exercise the actual app as
well as automated checks. Record the macOS version, display arrangement, steps,
and observed result. Accessibility Inspector can help diagnose window behavior.
The architecture overview is in [architecture.md](architecture.md).

## Optional documentation and shell completions

- `./build-docs.sh` builds the site and man pages. It needs Ruby 3+ and the
  repository's Bundler dependencies.
- `./build-shell-completion.sh` builds shell completions. It additionally needs
  Rust/Cargo and Fish.
- `./generate.sh` without `--ignore-xcodeproj` also generates the Xcode project.

## Release automation

[macarchy-release.yml](../.github/workflows/macarchy-release.yml) selects Xcode
26.3 on `macos-15`, builds with the Python installer, runs Swift and Python
tests, smoke-checks the bundled executables and signature, and uploads the ZIP.
It runs on pushes to `main`, `v*` tags, and manual dispatch; it does not currently
run automatically for pull requests.

Pushing a `v*` tag publishes a GitHub release using the tag's version. Maintainers
should update `DEFAULT_BUILD_VERSION` in `macarchy/install.py` and verify the
`main` workflow before tagging a new release. The published bundle is Apple
Silicon-only, ad-hoc signed, and not notarized. The Python installer is the
packaging path used by the action; the legacy `build-release.sh` is not.

