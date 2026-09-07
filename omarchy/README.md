# Omarchy Desktop for macOS

This fork adds scrolling columns to AeroSpace and a macOS adaptation of
[Omarchy's shortcuts](https://omarchy.org/manual/hotkeys/). The local Omarchy
sources used were `default/hypr/bindings/tiling.lua`, `default/hypr/looknfeel.lua`,
and `bin/omarchy-hyprland-workspace-layout-toggle`.

## Install

Requires macOS 13+, Swift 6.2+, Python 3.11+, and Bash 5 (`brew install bash`).
Use full Xcode for XCTest; Command Line Tools alone do not include XCTest.

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 omarchy/install.py --build
```

The installer builds `~/Applications/AeroSpace-Omarchy.app`, installs the profile
in `~/.aerospace.toml`, and backs up the previous config and helper files under
`~/.config/aerospace/backups/`. The Homebrew app is kept. Quit it before starting
the fork, and enable **AeroSpace Omarchy** in System Settings > Privacy & Security
> Accessibility. Run only one window manager at a time. Disable the previous
app's login item if it was enabled. The fork enables its own login item.

Local builds are ad-hoc signed. Rebuilding changes the signature and macOS may
turn off the fork's Accessibility permission. Re-enable its entry after an update;
until then the app waits and the CLI cannot connect. The installer does not grant
or bypass this security permission.

The fork has a separate bundle ID and socket. Its CLI is:

```sh
~/Applications/AeroSpace-Omarchy.app/Contents/Helpers/aerospace list-windows --all
```

`python3 omarchy/install.py --stock` installs compatible shortcuts for Homebrew
AeroSpace, without scrolling, and disables its login item. `--build-only` builds
without installing. `--profile-only` updates an installed fork's shortcuts.
`--dry-run` prints the profile without changing files.
The installer prints a `--restore BACKUP_DIRECTORY` command. Quit the fork before
restoring and reopening the previous app. Restore recovers the config and prior
helper contents; the separate fork app is retained.

## Shortcuts

**Super means Option.** The letters follow Omarchy where practical.

| Shortcut | Action |
| --- | --- |
| Super+Left/Right | Focus the previous/next column in this workspace |
| Super+Shift+arrows | Swap windows |
| Super+L | Toggle this workspace between scrolling and horizontal tiling |
| Super+- / Super+= | Shrink/grow this column by 100 pixels |
| Super+Control+- / = | Shrink/grow by 25 pixels |
| Super+R, then arrows | Resize mode; Escape or Enter exits |
| Super+P | Reset column widths / balance tiles |
| Super+T | Float / tile |
| Super+F | Fullscreen; repeat to restore |
| Super+J | Toggle split orientation in tiles; scrolling stays horizontal |
| Super+left drag | Move floating windows or swap tiled positions |
| Super+right drag | Resize from the nearest corner |
| Super+G | Accordion grouping / tiles |
| Super+Control+arrows | Join a neighboring container |
| Super+Control+G | Flatten the workspace tree |
| Super+period / comma | Cycle all tiled windows in order |
| Super+1...9,0 | Workspaces 1...10 |
| Super+Shift+1...9,0 | Move window and follow |
| Super+Control+Shift+1...9,0 | Move without following |
| Super+Tab / Shift+Tab | Next / previous numbered workspace |
| Super+Control+Tab | Previous workspace, explicitly |
| Super+S or backtick | Scratch workspace and back |
| Super+Shift+backtick | Send to scratch |
| Super+PageDown / PageUp | Next / previous monitor |
| Super+Control+Shift+arrows | Move workspace to another monitor |
| Super+Enter | Terminal |
| Super+Shift+Enter | Browser |
| Super+Space | Searchable application and desktop menu (see below) |
| Super+Shift+Escape | Enter/exit system mode: settings, screenshots, reminders, lock |
| Super+K | Complete local shortcut reference |
| Super+semicolon | Pass-through mode; repeat to resume shortcuts |
| Super+Control+R | Reload config |

The full reference is generated from the actual installed TOML, including
application launchers and system-mode keys. It does not point to Linux shortcuts
that work differently here. Existing apps are used with fallbacks; no unrelated
apps are installed. Clipboard history requires Maccy or Paste.

System mode displays a click-through translucent shortcut list at the bottom-left
of the focused monitor (`show-system-mode-overlay = true`). Option+Shift+Escape
toggles the mode; Escape and any selected action return to normal shortcuts. The
overlay lists the loaded bindings and disappears when the mode exits or AeroSpace
is disabled. It does not take keyboard focus or intercept clicks.

## Application and Desktop Menu

Super+Space opens a Spotlight-like native panel on the focused monitor. It is
driven by an Omarchy-style JSONC menu: a flat file whose dotted ids define the
tree (`system.sound` lives inside `system`). Shipped defaults cover Apps
(installed applications with their real icons, from /Applications and
/System/Applications), System settings, AeroSpace actions (current shortcuts,
conflict check, reload, hotkey file), and Learn links. Type to search across
names, aliases and descriptions; Return runs; Right enters a submenu;
Backspace goes back; Escape closes; Super+Space toggles.

Customize without rebuilding via `~/.config/aerospace/omarchy/menu.jsonc`:
same-id entries merge per field and keep their position, new ids append.
Whole-line `//` comments and trailing commas are allowed; inline comments are
not. `action` entries run shell commands; `when`/`checked`/`disabled` accept
bash conditions; the `apps` submenu accepts an `exclude` list. The installer
writes a commented sample there once and never overwrites it. The file is
watched: edits apply immediately; a parse error keeps the last working menu
and shows a small notification.

## Desktop Notifications

Small notices appear under the workspace indicators in the menu bar: they
slide down, stay out of focus, and close on outside click or Escape. Shortcut
conflict warnings, modifier-mouse failures, and menu config errors use this
surface. Conflict notices offer per-shortcut Pause, Keyboard Settings, and
Recheck actions, and a resolved check collapses to a compact confirmation.
**Check Shortcut Conflicts...** in the menu-bar menu reopens it any time.

## Native Shortcut Conflicts

The earlier Super=Command translation intercepted Chrome's new tab and address
bar, as well as Save, Find, Open, Print, Quit, Close Tab, browser tab numbers,
reopen tab, app switching, preferences, Spotlight, and text navigation. The new
profile has no Command bindings in any mode. Command shortcuts and Control-only
terminal shortcuts stay native. Option now belongs to the desktop, so bound
Option combinations (including Option+arrows for word navigation and some special
characters) are intentionally intercepted. Option cannot act as both Super and a
second Alt modifier in one chord: Control supplies that extra modifier for group
operations, fine resizing, and silent moves. This is the necessary Mac adaptation
of Omarchy's multi-modifier shortcuts.

Disable overlapping shortcuts in other window managers. For Option typing or
VoiceOver conflicts, use pass-through mode or the optional
`--leader` profile: **F18, then L** toggles layout, **F18, then Right** focuses the
next column. Only F18 is global in this profile. Use an extended keyboard or map
a spare key to F18 with your preferred keyboard utility. Backspace opens system
mode; Escape cancels. This avoids needing app-specific exceptions or synthetic
Command-key forwarding. Pass-through mode is available in the chord profile.

The profile enables `warn-about-shortcut-conflicts`. AeroSpace checks enabled
macOS symbolic shortcuts and probes Carbon registrations on mode activation,
reload, and every 30 seconds in the main mode with no modifiers held. Detectable
conflicts pause that AeroSpace binding and post a compact notice under the
workspace indicators. The menu-bar action **Check Shortcut Conflicts...**
reopens that notice, even when automatic warnings are disabled.
**Show Current Shortcuts...** lists loaded bindings grouped by mode. Recheck
reports its result and check time, or explains why checking is unavailable.
**Pause in AeroSpace** suppresses our copy until config reload; **Keyboard
Settings** and **Open App…** help you change the competing binding, then
**Recheck** retries. No other app's settings are silently modified. macOS
supplies neither a universal shortcut-owner lookup nor an API to remove
another app's bindings. Event-tap and app-local shortcuts cannot be
exhaustively detected, and registration can race.

## Scrolling Behavior

### Active Window Border

Install the optional macOS 14+ border companion with
`brew install FelixKratz/formulae/borders`. The startup helper applies Omarchy's
2-point cyan-to-green active border and subdued gray inactive borders, with
Retina rendering. The border follows native focus, movement, and resizing; no
global shortcuts or extra Accessibility permission are needed in this setup.
To apply it immediately, run `~/.config/aerospace/omarchy/action borders`.
Repeated invocations update the existing process rather than launching another.
Remove the `after-startup-command` entry and run `pkill -x borders` to turn it off.
Appearance options live in `omarchy/action` in this fork. The helper is a no-op
when the optional `borders` executable is not installed.

### Columns

The profile starts with horizontal scrolling columns at 49% width. Left/Right
traverses every column in tree order; it does not alternate between the last two
windows. The viewport moves only enough to reveal the focused column. Resizing a
column leaves its neighbors at their own widths, so a neighbor can extend beyond
the screen edge and remain partially visible. Fully offscreen columns are parked
using AeroSpace's existing corner-hiding mechanism and reappear when focused.
`scrolling-column-width` accepts an integer percentage from 10 through 100.

Split layouts, nested groups, floating windows, fullscreen, numbered workspaces,
and monitor movement continue to use AeroSpace's tree and commands. With
`mouse-modifier = 'alt'`, Option+left drag swaps tiled positions or moves floating
windows, and Option+right drag resizes from the nearest corner. Accessibility
permission is needed for the mouse event tap; a config warning appears if macOS
refuses it. Mouse gestures are inactive outside the main mode.
`adopt-native-window-resize = true` adopts native edge/corner resizing into column
widths or tile split weights instead of restoring the old managed width. Tile
neighbors share the available space; scrolling neighbors retain their own widths.
Width overrides and viewport positions are kept in memory and reset on restart.

This is an AX window manager, not a macOS compositor. There is no smooth Hyprland
animation or per-monitor clipping: adjacent displays can show overflow, apps can
enforce minimum window sizes, and macOS can constrain window positions. The
profile uses a scratch **workspace**, not Hyprland's overlay scratchpad. Accordion
containers approximate grouping; they are not Hyprland tab groups. Pseudo-tiling,
pinning, global modifier+wheel bindings, Quickshell panels,
transparency, and unified Linux theme propagation are not implemented. Native
settings, screenshots/recording, reminders, and an ordered menu-bar workspace
display provide the available macOS equivalents.

## Verify

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
python3 -m unittest discover -s omarchy -p 'test_*.py'
bash -n omarchy/action
```

For a live check, open at least four windows on one workspace. Walk from the
first to the last with Super+Right, enlarge a middle column, toggle Super+L twice,
then float/fullscreen and restore a window. Verify native Command+T and Command+L
inside Chrome. Check a second monitor separately because of the clipping limits.
