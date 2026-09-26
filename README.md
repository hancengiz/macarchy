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
  and native edge resizing is adopted into the layout. Mouse-edge focus is
  optional and disabled by default (`enable-mouse-edge-focus = false`).
- **System mode HUD** — Option+Shift+Esc overlays a click-through cheat sheet
  of one-key system actions (Bluetooth, Displays, Screenshot, Lock…).
- **The menu (Option+Space)** — a native Spotlight-like launcher driven by an
  Omarchy-style JSONC menu: nested submenus, dotted ids, per-field overrides,
  searchable installed apps with real icons, bash `when/checked/disabled`
  guards, and a **Keybindings** section that can run any live shortcut.
  Customize `~/.config/macarchy/menu.jsonc`; edits apply live.
- **Native Settings** — open **Settings…** in the tray for General, App Widths,
  and Shortcuts. Changes are saved to the active configuration.
- **Desktop notifications** — compact panels for failed shortcut registrations,
  gesture failures, and config errors. Advisory app shortcuts stay in Settings.
- **Remembered widths and sessions** — per-app scrolling defaults and restored
  live-window layouts, with a layout-preserving **Restart** action.
- **Hyprland-style layering** — floating windows stay above the tiling layer.

## Install

Prebuilt Apple Silicon app bundles are available from
[GitHub Releases](https://github.com/hancengiz/macarchy/releases). These builds
are ad-hoc signed, not notarized; macOS may require approval before opening
and a fresh Accessibility grant. The source installer below also installs
the Omarchy profile and helper scripts.

Building requires macOS 13+, Swift 6.2+ (Xcode Command Line Tools), Python 3.11+,
and Bash 5 (`brew install bash`). Full Xcode is needed for XCTest, not release builds.

```sh
python3 macarchy/install.py --build
```

This builds and installs `~/Applications/macarchy.app` and the helper files in
`~/.config/macarchy/`. A fresh installation creates `~/.macarchy.toml`;
upgrades preserve existing configuration and Settings. Backups are stored in
`~/.config/macarchy/backups/`. Enable **macarchy** under System Settings →
Privacy & Security → Accessibility.

- Upgrades call `macarchy restart` if the old version supports it. For the
  first upgrade from a legacy version, quit it and open the newly installed
  app once; the installer does not send an unsupported restart signal.
- Builds prefer an available local Developer ID Application signing identity,
  with ad-hoc signing as a fallback. Ad-hoc rebuilds may require re-enabling
  Accessibility access.
- `--profile-only` explicitly replaces the profile (with a backup);
  `--build-only` builds/signs without installing. `--build-version 0.22.1`
  sets the version embedded in the app and CLI; builds also embed the Git commit.
- `--leader` selects an F18 leader profile when installing a profile for
  VoiceOver users; `--restore` restores a backup.

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
| Option+Control+Shift+W | Save current width as this app's scrolling default |

## Settings, widths, and sessions

Open tray **Settings…** to adjust layout, gaps, mouse behavior, app widths, and
shortcut settings. Top and bottom **outer** gaps default to zero; inner gaps
remain separately configurable.

Per-app widths use quoted bundle IDs and integer percentages from 1 through 100:

```toml
[app-window-widths]
'com.google.Chrome' = 75
'com.microsoft.VSCode' = 75
```

Scrolling windows without an explicit manual width use their app default,
falling back to `scrolling-column-width` (49 by default, range 10–100).
Defaults are resolved during layout. Manual window overrides take precedence;
`macarchy balance-sizes` clears them in the workspace and returns to defaults.
`macarchy save-app-width [--window-id <window-id>]` saves the selected window's
width and clears only that window's manual scrolling override. The default
profile binds it to `alt-ctrl-shift-w`. Settings captures the focused target
before activating its own window. Scrolling capture uses the logical requested
width, tiled capture uses the allocated width, and floating capture uses the
display's visible width as its reference. These defaults affect scrolling;
they do not automatically resize floating windows. App minimum sizes can still
limit the physical result.

`~/Library/Application Support/macarchy/session.json` stores workspace trees,
window order, widths, viewport offsets, display assignments, and focus. Startup
restores only live windows: exact process/window matches, or unambiguous
bundle-ID/title matches across relaunch. It does not launch closed apps.
Displays are matched by stable UUID, with the first monitor as fallback when
a saved display is absent.

Use `macarchy restart` or tray **Restart** to save the session and launch a fresh
Macarchy process without the normal **Quit** rearrangement. This also preserves
the menu-bar item, which macOS can detach after an in-place process replacement.

See [known_issues.md](known_issues.md) for text-input conflicts like
Option+arrows word navigation.

## Omarchy parity

Implemented features (not a claim of full-suite or complete live acceptance):

- Scrolling-column layout with per-column widths, viewport reveal, and
  scrolling ⇄ tiling toggle preserving proportions (`Option+L`).
- Omarchy `togglesplit` semantics via `Option+J`; float/tile via `Option+T`.
- Option-as-Super chords; Command stays with applications.
- Mouse gestures (Option+drag move/swap, Option+right-drag resize), native
  edge-resize adoption, optional mouse-edge focus (off by default).
- Workspaces 1-10 + scratch, pass-through mode, system-mode HUD,
  Spotlight-like customizable menu (`menu.jsonc`), desktop notifications,
  native Settings, workspace indicators, start-at-login, and session restore.

Deliberate macOS adaptations (platform limits, see
[known_issues.md](known_issues.md)):

- No compositor: no smooth scrolling animation or per-monitor clipping.
  Partially visible columns intentionally retain true desktop-wide positions,
  so adjacent displays may show overflow. Fully hidden parking minimizes
  rectangle intersection across all displays and never moves native-fullscreen
  windows. Applications may enforce minimum window sizes.
- Option+arrows/letters replace native text-editing chords while bindings are
  active; pass-through mode (`Option+;`) or the `--leader` profile restores
  them. macOS has no separate Super modifier.
- Pseudo-tiling, modifier+wheel navigation, and a true overlay scratchpad are
  not ported.
- Failed shortcut registrations produce compact notices linking to Settings.
  Advisory app-shortcut overlaps are informational, remain Settings-only, and
  do not disable bindings. Detection is best-effort, not a universal audit.

## Development

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
python3 -m unittest discover -s macarchy -p 'test_*.py'
bash -n macarchy/action
```

The full product brief and continuation notes live in
[docs/omarchy-on-macos.md](docs/omarchy-on-macos.md).
