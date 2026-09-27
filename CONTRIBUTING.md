# Contributing to Macarchy

**Pull requests are welcome.** You can help with bug fixes, documentation,
accessibility, app compatibility, multi-monitor behavior, or focused features.
You do not need to be a Swift expert to improve setup instructions or report a
reproducible problem.

Macarchy is an independently maintained AeroSpace fork. Send Macarchy-specific
issues and PRs to [hancengiz/macarchy](https://github.com/hancengiz/macarchy),
not to the upstream project.

## Before starting

- Search existing [issues](https://github.com/hancengiz/macarchy/issues) and
  [pull requests](https://github.com/hancengiz/macarchy/pulls) for related work.
- Small fixes and documentation improvements can go straight to a PR.
  For larger features or behavior changes, open an issue with the use case,
  proposed behavior, and tradeoffs before investing in an implementation.
- Keep changes focused and follow the surrounding code and naming conventions.
  Avoid unrelated formatting or refactoring in a functional change.

## Local setup

Fork the repository, clone your fork, and create a topic branch from `main`.
The build needs macOS 13+, Swift 6.2+, Python 3.11+, and Homebrew Bash 5.
Full Xcode 26+ is needed for Swift tests; compatible Command Line Tools are
enough for release builds.

Follow the [development guide](dev-docs/development.md) to select Xcode and put
Bash 5 on your `PATH`. From the repository root:

```sh
python3 macarchy/install.py --build-only
.local/macarchy.app/Contents/MacOS/macarchy --version
.local/macarchy.app/Contents/Helpers/macarchy --help
codesign --verify --deep --strict .local/macarchy.app
```

This generates the files required by a fresh checkout and stages a signed app
without installing it, replacing your configuration, or changing your running
desktop. You do not need a paid signing certificate; the builder can use ad-hoc
signing.

## Verify your change

With full Xcode selected and the build above complete:

```sh
swift test
python3 -m unittest discover -s macarchy -p 'test_*.py'
bash -n macarchy/action
```

Run the checks relevant to your change and report the exact commands and results.
If a prerequisite is unavailable, say which checks you could not run.
The current GitHub workflow runs on `main` pushes, release tags, and manual
dispatch, not automatically on PRs.

For code changes:

- Add or update focused regression tests for behavior, boundaries, and error
  cases. Tests should be deterministic and independent of personal configuration.
- Exercise the actual affected path. For layout, shortcuts, Settings, or restart
  changes, run the app and describe what you observed; unit tests alone do not
  establish desktop behavior.
- Do not run two window managers at once. Use disposable windows and keep a
  backup before testing installation or configuration changes.
- Format changed Swift files using the repository's SwiftFormat configuration.
  See the development guide for installing and invoking the formatter.
- Update relevant documentation and regenerate command help when command syntax
  changes. Do not hand-edit generated files.

Do not commit built app bundles, personal configs or session snapshots, signing
credentials, or private screenshots and window titles.

## Open a pull request

Open the PR against **`hancengiz/macarchy:main`** and fill in the PR template:

1. Explain the problem, the change, and any important tradeoffs.
2. Link related issues when applicable.
3. List the checks you ran and any limitations.
4. Include reproduction steps for bug fixes and screenshots or a short recording
   for visible UI changes. Redact personal content.
5. Note any changes to shortcuts, configuration, persisted sessions, or upgrades.

Use descriptive commit messages and keep commits focused. Draft PRs are welcome
for early discussion; identify what still needs verification. Address review
feedback in the same PR.

## Report a bug or suggest a feature

Use [GitHub Issues](https://github.com/hancengiz/macarchy/issues). For bugs, include:

- Steps to reproduce, expected behavior, and actual behavior.
- `macarchy --version` output, macOS version, and whether you installed a release
  ZIP or built from source. If `macarchy` is not on your `PATH`, use the bundled
  CLI path documented in the [README](README.md#install).
- A minimal relevant config, affected apps and versions, and display arrangement
  or scaling when the problem involves window placement.
- For window-handling problems, `macarchy debug-windows` output or a recording
  when useful. Inspect diagnostics before sharing: titles and screenshots may
  contain private information.
- What you tried and whether the problem is reproducible after a restart.

For feature requests, describe the workflow you need, alternatives you tried,
and how it should fit Macarchy's macOS adaptations. Workflow tips can also be
submitted as PRs to [the Goodies page](docs/goodies.adoc).

## License

By contributing, you agree to license your contribution under the repository's
[MIT license](LICENSE.txt). Preserve existing copyright and attribution notices.

