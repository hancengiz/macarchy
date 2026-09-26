# Contributing

The main and the most important rule: **read the room!**

* Does your patch look like typical commit in the repo?
* Does your commit message look like typical commit message in the repo?
* Does your test look like typical test in the repo?
* etc.

## Submiting bugs and feature ideas

Submit bugs to https://github.com/hancengiz/macarchy/issues

Submit feature ideas to https://github.com/hancengiz/macarchy/discussions

Rules:
* Search for duplicates (in GitHub Issues and Discussions) before creating a new one
* Upvote for issues/discussions that you find useful

**Consider including in bug reports**

* `macarchy debug-windows` output, if the problem is about handling some windows
* Screenshots of problematic windows
* Videos of problematic windows
* What did you try to resolve the issue?
* Your config
* `macarchy --version` output
* macOS version

**Consider including in feature request**

* Use cases!
* Alternative approaches
* Links to docs of similar features in other window managers that you know
* Synopsis, if you suggest a new command
* Mental model description

## Submiting code

Send GitHub PRs to https://github.com/hancengiz/macarchy

**License Agreement**. By contributing changes to this repository, you agree to license your contributions under the MIT license.

## Share your workflow and tips

Submit your tips by opening an issue or pull request; the Goodies page lives in `./docs/goodies.adoc`.

## Building and testing

* Build and install from sources: `env DEVELOPER_DIR=$(xcode-select -p) python3 macarchy/install.py --build`
* Run the debug CLI: `./run-cli.sh --version` (prints `macarchy --version` output)
* Run tests: `swift test`
* Format the code: `.deps/swiftformat/swiftformat .`
* See `dev-docs/development.md` for the full development guide
