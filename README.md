# macarchy

**Omarchy-like tiling window manager for macOS.**

macarchy is a fork of [AeroSpace](https://github.com/nikitabobko/AeroSpace) by
[Nikita Bobko](https://github.com/nikitabobko) — a hybrid manual tiling window
manager built on macOS Accessibility — reimagined to feel like
[Omarchy](https://omarchy.org) (the Hyprland-based Linux desktop by
[DHH](https://github.com/dhh)): scrolling columns, Option-as-Super shortcuts,
a Spotlight-like customizable menu, and small desktop notifications.

This project is independently maintained and is not affiliated with either
upstream project. All credit for the window-management engine goes to
AeroSpace; the desktop experience design follows Omarchy.

## Features

- **Scrolling columns** — horizontal Hyprland-style layout: each workspace is
  a strip of full-height columns; neighbors stay partially visible at the
  edges; Option+L toggles between scrolling and tiling.
- **Super is Option** — Omarchy-style chords with Command left entirely to
  your applications. Chrome's ⌘T/⌘L, Save, Find, and friends stay native.
- **Mouse gestures** — Option+drag moves/swaps, Option+right-drag resizes,
  native edge resizing is adopted into the layout, and parking the pointer at
  a dead-end screen edge focuses the next window that side.
- **System mode HUD** — Option+Shift+Esc overlays a click-through cheat sheet
  of one-key system actions (Bluetooth, Displays, Screenshot, Lock…).
- **The menu (Option+Space)** — a native Spotlight-like launcher driven by an
  Omarchy-style JSONC menu: nested submenus, dotted ids, per-field overrides,
  searchable installed apps with real icons, bash `when/checked/disabled`
  guards, and a **Keybindings** section that can run any live shortcut.
  Customize `~/.config/macarchy/menu.jsonc`; edits apply live.
- **Desktop notifications** — compact panels under the workspace indicators
  for shortcut conflicts, gesture failures, and config errors.
- **Hyprland-style layering** — floating windows stay above the tiling layer.

## Install

Requires macOS 13+, full Xcode (for XCTest), Python 3.11+, and Bash 5
(`brew install bash`).

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 macarchy/install.py --build
```

This builds `~/Applications/macarchy.app`, installs the profile to
`~/.macarchy.toml`, the helper to `~/.config/macarchy/`, and backs
up anything it replaces under `~/.config/macarchy/backups/`. Enable
**macarchy** under System Settings → Privacy & Security → Accessibility.

- Local builds are ad-hoc signed: every rebuild changes the signature and
  macOS may drop the Accessibility grant — re-enable it after updates.
- The Homebrew AeroSpace app is kept for rollback; never run two window
  managers at once.
- `--stock` installs shortcuts for upstream AeroSpace without fork features;
  `--leader` uses an F18 leader key for VoiceOver users; `--restore` rolls back.

## Daily shortcuts

| Keys | Action |
| --- | --- |
| Option+←/→ | Focus previous/next column |
| Option+Shift+arrows | Swap windows |
| Option+L | Scrolling ⇄ tiling |
| Option+T | Float / tile |
| Option+- / = | Resize column (Control for fine steps) |
| Option+R | Resize mode |
| Option+1…0 | Workspaces (Shift moves window along) |
| Option+Tab | Next workspace |
| Option+S | Scratch workspace |
| Option+Enter / Shift+Enter | Terminal / browser (new window) |
| Option+Space | The menu |
| Option+Shift+Esc | System mode |
| Option+; | Pass-through mode (suspend all bindings) |
| Option+Control+R | Reload config |

See [known_issues.md](known_issues.md) for text-input conflicts like
Option+arrows word navigation.

## Development

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
python3 -m unittest discover -s macarchy -p 'test_*.py'
bash -n macarchy/action
```

The full product brief and continuation notes live in
[docs/omarchy-on-macos.md](docs/omarchy-on-macos.md).
