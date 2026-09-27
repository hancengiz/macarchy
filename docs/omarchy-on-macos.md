# Omarchy on macOS: Product Requirements and Implementation Notes

_Historical implementation notes with current session, Settings, and upgrade
contracts updated below. The project's identity, names, and paths are
**macarchy** — see the [README](../README.md) for setup._

Feature-contract update: 2026-09-26. Release **v0.22.1** was published on
2026-09-26 from commit `726282bb0d51f346d15d0fe6faaa9dc032c44a56`.
Its [release workflow](https://github.com/hancengiz/macarchy/actions/runs/36278685201)
passed **462 Swift tests and 6 Python installer tests**, plus packaged-executable
and signature checks. The downloaded release archive was also smoke-checked.
Older dated entries below remain historical observations, not blanket live
acceptance claims. Contributor setup lives in [CONTRIBUTING.md](../CONTRIBUTING.md).

## 0. Rebrand (2026-09-07)

The project is now **macarchy** ("Omarchy-like tiling manager for macOS"), a
fork of AeroSpace (MIT, © Nikita Bobko; LICENSE.txt retained). App bundle:
`~/Applications/macarchy.app`, identifier `com.hancengiz.macarchy`, GitHub
repo `hancengiz/macarchy`. The old `AeroSpace-Omarchy.app` is superseded —
delete it and re-grant Accessibility to macarchy after the first launch.
User guide: `README.md`; known issues incl. Option+arrow text-input
conflicts: `known_issues.md`. CI: `.github/workflows/macarchy-release.yml`
builds the app on every push to main and publishes releases on `v*` tags.

## 1. Read This First

The current release is installed with a native JSONC launcher, compact tray
notices, native **Settings…**, and session persistence. The tray Settings window
has **General**, **App Widths**, and **Shortcuts** tabs. The old oversized
conflict window and per-binding pause controls are no longer part of the UI.
Automatic shortcut notices are reserved for actual failed registrations;
advisory app-shortcut suggestions remain in Settings and do not disable bindings.

Do not mistake checked implementation tasks below for user acceptance or complete
live verification. Each area records its separate verification and acceptance status.

### Repository and References

| Item | Location |
| --- | --- |
| Repository | `https://github.com/hancengiz/macarchy` |
| Working branch | `main` |
| Fork / `origin` | `https://github.com/hancengiz/macarchy.git` |
| `upstream` | `https://github.com/nikitabobko/AeroSpace.git` |
| Contribution guide | [CONTRIBUTING.md](../CONTRIBUTING.md) |
| Public references | <https://omarchy.org/manual/> and <https://omarchy.org/manual/hotkeys/> |
| Project guide | [README.md](../README.md) |

The feature work is committed, pushed, and published as
[v0.22.1](https://github.com/hancengiz/macarchy/releases/tag/v0.22.1).
Preserve any subsequent local changes and user configuration when continuing work.

## 2. Product Goal

Create an Omarchy-like everyday desktop experience on macOS, built on the user's
AeroSpace fork. Prioritize the workflows the user actually uses: horizontal
scrolling windows, recognizable tiling shortcuts, mouse movement/resizing,
visible focus, searchable menus, and unobtrusive desktop feedback.

The user explicitly wants a **1:1 Omarchy look, feel, and customization experience**
where feasible. Treat that as the design target, not as an achieved compatibility
claim. macOS Accessibility window management is not a Wayland compositor.
Document unavoidable differences; do not silently substitute unrelated behavior
and describe it as exact parity.

### Non-Negotiable Decisions

- **Option is Super. Command belongs to applications.** Earlier Command and
  Control+Option experiments were superseded. Do not reintroduce global Command
  bindings or synthetic Command forwarding.
- Chrome Command+T, Command+L, and other native app shortcuts must work normally.
- Horizontal focus must traverse all columns on the same workspace, not alternate
  between the last two windows or switch workspaces to simulate scrolling.
- A column may retain its full width while only part is visible at a screen edge.
- Native macOS edge/corner resizing must update managed dimensions instead of
  immediately snapping back to the previous width.
- Menus must be usable desktop UI, not AppleScript list/OK dialogs.
- Notifications should be compact floating surfaces under the workspace
  indicators, not large standalone utility windows.
- Preserve the user's open apps, documents, custom bindings, and existing changes.

## 3. Current Runtime vs. Source

| Component | Installed state | Working-tree state |
| --- | --- | --- |
| Scrolling, mouse gestures, resize adoption | Installed | Implemented |
| Option-based profile | Installed | Implemented |
| Active-window borders | JankyBorders installed and started | Helper/startup integration implemented |
| System-mode shortcut overlay | Installed and visually checked | Implemented |
| Shortcut registration diagnostics | Installed | Compact failure notices; details and Recheck in Settings |
| Current shortcuts | Installed | Listed in Settings -> Shortcuts and the launcher's Keybindings section |
| Option+Space menu | Installed: native data-driven launcher panel | Implemented; JSONC defaults + user extension |
| Data-driven Omarchy menu customization | Installed (`menu.jsonc` sample + watcher) | Implemented |
| Generic tray notification/popover component | Installed | Implemented (NSStatusItem anchor; conflicts, modifier-mouse, menu parse errors) |
| Native Settings | Installed | General, App Widths, Shortcuts; edits saved to active config |
| Session restore and layout-preserving Restart | Installed | Live-window matching, stable monitor UUIDs, durable save + fresh-process handoff |

### Installed Artifacts

- App: `~/Applications/macarchy.app`.
- Bundle identifier: `com.hancengiz.macarchy`.
- Fork CLI: `~/Applications/macarchy.app/Contents/Helpers/macarchy`.
- Config: `~/.macarchy.toml` or the configured XDG location.
- Helper/menu: `~/.config/macarchy/`.
- Session: `~/Library/Application Support/macarchy/session.json`.
- Do not run another window manager simultaneously. The fork has its own
  socket identity; the upstream Homebrew CLI does not address it.

**Drift resolved 2026-09-07 evening:** the installed config now matches the
repository template (`alt-space = 'mode omarchy-menu'`), the installed binary
includes the launcher, the tray notice surface, and the app-lifetime fix
(`NSApplicationDelegateAdaptor` refuses last-window-close termination). User
extension file: `~/.config/aerospace/omarchy/menu.jsonc`.

The installed app was live-checked 2026-09-07 ~19:20: socket answers, AX
granted (`list-windows` works), menu/system mode toggles verified via
`trigger-binding`, and the app survived a 90-second soak through three
conflict-check cycles. Pixel-level visual verification of the panel and
notice is still owed (the agent session cannot capture the screen). Recheck
current permission and process state instead of relying on historical PIDs.

## 4. Implemented Tasks

### WM-01: Fork, Packaging, and Installation

- [x] Point `origin` to the user's fork and retain upstream separately.
- [x] Work on `omarchy-desktop`.
- [x] Build a separately identified app using `-DOMARCHY`.
- [x] Keep the Homebrew installation available for rollback.
- [x] Add a profile/helper installer with backups, dry run, build-only,
  profile-only, stock, leader, and restore paths.
- [x] Use ordered workspace indicators in the menu bar (`i3Ordered`).
- [x] Commit and push the reviewed work; published as v0.22.1.

Implementation: `Sources/Common/appMetadata.swift`,
`Sources/AppBundle/config/startAtLogin.swift`, `macarchy/install.py`.

Packaging trap already fixed: default Mac filesystems are case-insensitive.
Putting `AeroSpace` and `aerospace` in the same directory overwrites one with the
other. The app executable belongs in `Contents/MacOS`; CLI in `Contents/Helpers`.

### WM-02: Horizontal Scrolling Columns

- [x] Add `.scrolling` layout and `layout scrolling` command support.
- [x] Add configurable default column width, currently 49% of the viewport.
- [x] Keep per-column width overrides and per-container viewport offset.
- [x] Reveal the focused column with the smallest necessary horizontal movement.
- [x] Preserve widths of partially visible neighboring columns.
- [x] Park fully hidden columns by minimizing rectangle intersection across all
  displays; never move native-fullscreen windows during parking.
- [x] Restore offscreen columns when focused and when management is disabled.
- [x] Toggle scrolling/horizontal tiles on the same workspace with Option+L.
- [x] Keep the scrolling strip horizontal. Option+J now binds to
  `toggle-split opposite` (Omarchy `togglesplit` semantics): it arms the split
  direction for the next new window, which joins the focused window inside an
  opposite-orientation container — including a vertical stack within one
  scrolling column. `layout horizontal vertical` still rotates tiles roots.
  The wrapper is materialized only at the atomic bind site, so the flatten
  normalization never dissolves a half-built split (see `consumeSplitHint`).
- [x] Preserve window proportions across scrolling <-> tiles switches by
  converting `scrollingSize` <-> `adaptiveWeight` in `changeTilingLayout`.
- [x] Add geometry, traversal, resize, config, and layout-toggle tests.
- [ ] Complete live acceptance on multiple monitors and varied app minimum sizes.
- [ ] Verify long sequences of focus, close, reopen, monitor move, fullscreen,
  float/tile, disable/enable, and nested-container operations.

Implementation: `tree/TilingContainer.swift`, `tree/TreeNode.swift`,
`tree/Window.swift`, `layout/ScrollingViewport.swift`, `layout/layoutRecursive.swift`,
`layout/refresh.swift`, `command/impl/LayoutCommand.swift`,
`command/impl/ResizeCommand.swift`, `command/impl/BalanceSizesCommand.swift` under
`Sources/AppBundle`, plus `Sources/Common/cmdArgs/impl/LayoutCmdArgs.swift`.

Workspace trees, window order, widths, viewport offsets, display assignments,
and focus are persisted in
`~/Library/Application Support/macarchy/session.json`. Startup restores live
windows only, using exact process/window identity or an unambiguous
bundle-ID/title match across relaunch. It never launches closed apps or assigns
ambiguous matches arbitrarily. Monitors use stable UUIDs, with the first monitor
as fallback when the saved display is absent.

`macarchy restart` and tray **Restart** save and relaunch without the normal
**Quit** rearrangement. The initial in-place restart preserved all eight AX/CG
frames and workspace trees, but did not preserve the visible menu-bar item.
The subsequent missing-icons report traced this to in-place executable replacement:
Macarchy's status item was at (-1, 792), while a fresh launch restored it to
(1459, 3) with workspace trees unchanged. Restart now waits for the old process
to exit before starting a fresh process, retaining arguments and environment.

The installed fresh-process path passed both CLI and tray-menu restarts:
each produced a new PID, retained all five currently listed window frames and
workspace trees, and kept the status item at (1459, 3). The CLI scenario also
checked unchanged focus and configuration contents. Icon rendering itself was
not redesigned; the fix is in `restartMacarchy.swift`.

Separate single-window AppKit fixtures passed the scrolling boundary check:
left-column widths 1531, 1831, and 1889 kept the right column at x=1551, 1851,
and 1909 on the 1920-point main display; width 1890 parked it instead.
The parked frame intersected neither the main nor the right-hand display.
macOS can constrain parking coordinates and leave a one-point-wide strip on
the bottom display; this is not compositor-level invisibility. The existing
native-fullscreen window remained unchanged during the initial boundary run.
A 2036×1200 floating fixture fitted to 1920×774 when moved to the smaller display.

Per-monitor compositor clipping and smooth Hyprland scrolling are intentionally
not implemented. Partially visible columns keep true desktop-wide positions;
adjacent displays can expose overflow, and apps can enforce minimum sizes.
The original early-hide report is not established as definitively fixed.

### SETTINGS-01: Native Settings and App Width Defaults

Open tray **Settings…** for General, App Widths, and Shortcuts. Settings writes
to the active TOML configuration; advanced options remain available through
**Open Configuration…**. Mouse-edge focus defaults to
`enable-mouse-edge-focus = false`. Vertical **outer** gaps (top/bottom) default
to zero; inner gaps remain independent.

`[app-window-widths]` maps quoted bundle IDs to integer percentages from 1
through 100:

```toml
[app-window-widths]
'com.google.Chrome' = 75
'com.microsoft.VSCode' = 75
```

Scrolling windows resolve app defaults during layout, falling back to
`scrolling-column-width` (49 by default; range 10–100). Explicit manual window
widths take precedence. `balance-sizes` clears manual overrides in the workspace
and returns windows to app defaults or the fallback.

`macarchy save-app-width [--window-id <window-id>]` saves the selected window's
width; without a window ID it uses the focused window. The default profile
binds it to `alt-ctrl-shift-w` (Option+Control+Shift+W). Saving clears only the
target's manual scrolling override. Settings captures that target before
activating its own window, and also supports editing/removing saved defaults.
Capture uses the logical requested scrolling width, allocated tiled width, or
floating width relative to the display's visible width. Defaults affect
scrolling, not automatic floating sizing; app minimum sizes still apply.

### KEY-01: Omarchy-Inspired Shortcuts Without Command Conflicts

- [x] Use Option-based global shortcuts and keep Command combinations native.
- [x] Map daily T/J/L operations, directional focus/swap, resizing, workspaces,
  scratch workspace, monitor moves, fullscreen, and app launch actions.
- [x] Keep previous-workspace and ordered window traversal as distinct operations.
- [x] Add pass-through mode and an optional F18 leader profile.
- [x] Generate a local reference from the installed TOML.
- [x] Move system mode from Option+Esc to **Option+Shift+Esc**.
- [x] Make Option+Shift+Esc toggle system mode both on and off; Escape also exits.
- [ ] Audit remaining bindings against Omarchy's source and document deviations
  explicitly rather than claiming all keys are identical.

Relevant final keys:

| Key | Current purpose |
| --- | --- |
| Option+Left/Right | Previous/next window within the workspace |
| Option+Shift+arrows | Swap windows |
| Option+L | Scrolling / horizontal tiles |
| Option+J | Arm split direction for the next new window (vertical/horizontal) |
| Option+T | Float / tile |
| Option+- / = | Shrink / grow width by 100 |
| Option+Control+- / = | Fine width resize by 25 |
| Option+Shift+- / = | Height resize |
| Option+R | Resize mode; Escape/Enter exits |
| Option+Tab / Shift+Tab | Next / previous numbered workspace |
| Option+Control+Tab | Previous workspace |
| Option+period / comma | Ordered window traversal |
| Option+1...0 | Workspaces 1...10 |
| Option+Shift+1...0 | Move window and follow |
| Option+S or backtick | Scratch workspace |
| Option+Shift+Esc | Enter/exit system-controls mode |
| Option+Space | Native JSONC desktop menu |
| Option+K | Generated shortcut reference |
| Option+semicolon | Toggle pass-through mode |
| Option+Control+R | Reload config |
| Option+Control+Shift+W | Save current app width as its scrolling default |

Option+Esc is macOS's default Speak Selection shortcut, not app-window cycling.
Command+grave accent cycles windows of the front app. A fresh Carbon symbolic-key
query still reported Option+Esc reserved when the user thought it had been
removed. The warning was real for that case; changing our binding cleared it.
Option+Shift+Esc passed a live registration probe.

The extra Control layer substitutes for Omarchy chords containing both Super and
Alt, since Option cannot represent two separate modifiers. Bound Option word-
navigation/special-character shortcuts are intentionally taken by the desktop.
VoiceOver and accessibility interactions need particular care.

### WM-03: Mouse and Native Resizing

- [x] Option+left drag moves floating windows or swaps tiled positions.
- [x] Option+right drag resizes from the nearest corner.
- [x] Keep gestures inactive outside main mode and preserve Command mouse chords.
- [x] Coalesce mouse motion and retain mouse-up to finish gestures.
- [x] Adopt native AX resize changes into column widths or tile weights.
- [x] Account for top/left native resize emitting both moved and resized events.
- [x] Make a drag returning to its starting dimensions restore the original size.
- [x] Test size conservation, clamping, native width persistence, and neighbors.
- [ ] Perform live left/right modifier-drag tests across app types and monitors.
- [ ] Stress native resize notification races, app size constraints, and repeated
  resize/move cycles; unit coverage is not proof that every app avoids snapping.

Manager-written AX sizes are acknowledged using the actual app-constrained
result, so their notifications do not rewrite logical column widths. Genuine
native changes adopt the observed dimension only on the changed axes. A live
fixture retained logical width 100 while enforcing physical minimum 200;
an external resize to 260 then remained logical/physical 260 instead of snapping
back to 200. This is scoped constraint/feedback evidence, not every app's timing.

Implementation: `Sources/AppBundle/mouse/ManagedResize.swift`, `ModifierMouse.swift`,
`moveWithMouse.swift`, `resizeWithMouse.swift`, and `GlobalObserver.swift`.

The CGEvent tap callback deliberately extracts flags/coordinates before entering
`MainActor.assumeIsolated`. An earlier inline callback carrying CGEvent through
the actor closure crashed the Swift compiler. Do not casually revert that pattern.

### UI-01: Active Panel Border

- [x] Install `FelixKratz/formulae/borders` (JankyBorders 1.9.0 at installation).
- [x] Start it and integrate startup through the Omarchy action helper.
- [x] Use Omarchy's 2-point cyan-to-green active border and subdued gray inactive
  border; enable Retina rendering.
- [x] Exclude AeroSpace's own panels and avoid additional global shortcuts.
- [ ] Verify visual behavior during modifier dragging, native fullscreen, clipping,
  display changes, and future tray/launcher surfaces.

Options live in `omarchy/action`: active gradient `0xee33ccff` to `0xee00ff99`,
inactive `0xaa595959`, width `2.0`, `ax_focus=off`, transparent background.
This is an optional macOS 14+ companion, not AeroSpace compositor support.

### KEY-02: Shortcut Conflict Detection

- [x] Check enabled macOS symbolic shortcuts and exclusive Carbon reservations.
- [x] Release our registrations before probing to avoid self-conflicts.
- [x] Detect on mode activation/reload and periodically in idle main mode.
- [x] Report actual failed registrations as inactive; do not alter other apps.
- [x] Deduplicate compact automatic notices and preserve config diagnostics.
- [x] Put Recheck, Keyboard Settings, current bindings, and detailed diagnostics
  in native Settings -> Shortcuts.
- [x] Keep advisory app-shortcut suggestions Settings-only; these bindings stay
  active and do not trigger automatic notices.
- [x] Show check time, no-conflict status, and reasons checking is unavailable.
- [x] Allow manual checking when automatic warnings are disabled.
- [ ] Test conflict removal in a second app followed by Recheck end to end.

Implementation: `Sources/AppBundle/config/ShortcutConflicts.swift`,
`config/HotkeyBinding.swift`, `ui/SettingsWindow.swift`, `ui/TrayStatusItem.swift`,
`ui/currentShortcutsDescription.swift`.

Detection is best-effort. macOS exposes neither all event-tap/app-local shortcuts
nor a universal owner lookup or removal API. A registration race remains possible.
Do not promise automatic removal of another app's shortcut. Some applications may
retain a registration until they quit. Checking currently covers the active mode.

### UI-02: System-Controls Mode HUD

- [x] Display a small translucent list at the focused monitor's bottom-left.
- [x] Derive rows from actual configured bindings, not a separate stale key list.
- [x] Use short names for exact bundled helper actions; preserve custom commands.
- [x] Keep the HUD click-through and non-key/non-main so it does not take focus.
- [x] Hide on mode exit, an action, or disabling management.
- [x] Verify rendering and both exit paths in the installed app.
- [x] Test labels, custom-command fallback, exit rows, and monitor coordinates.
- [ ] Test live monitor changes, tiny displays, and unusually long custom rows.

Implementation: `Sources/AppBundle/ui/SystemModePanel.swift`, existing
`NSPanelHud.swift`, activation in `config/HotkeyBinding.swift`, refresh integration
in `layout/refresh.swift`. Config: `show-system-mode-overlay = true`.

System mode is a temporary shortcut layer, not a color mode. The user initially
did not understand it, which motivated the HUD. B opens Bluetooth, D Displays,
C Screenshot, etc. Each action returns to main mode before launching its helper.

## 5. Implemented This Session: Menu and Tray Surface

### UI-03: Spotlight-Like, Omarchy-Customizable Menu — implemented, installed, pending user acceptance

The rejected AppleScript `choose from list` menu is gone from the helper. The
installed launcher is now a native panel driven by Omarchy's data model,
ported from `MenuModel.js`/`docs/menu.md` semantics (see §6):

- [x] `ui/OmarchyMenuData.swift`: flat dotted-id JSONC schema, whole-line
  comments + trailing commas dialect, per-key merge of the user extension onto
  shipped defaults (order preserved, new ids append, synthetic `root`),
  multi-term search (name substring or description whole-word), tiered scoring,
  batched bash guards (`when` hides on failure, `checked` marks, `disabled`
  disables; failed batches keep the last complete set), apps provider rows
  (searchable, never routable, `exclude` list supported).
- [x] `ui/OmarchyMenuModel.swift`: navigation state (enter/back with stack,
  selection wrapping that skips disabled rows and the search divider).
- [x] `ui/OmarchyMenuPanel.swift`: submenu chevrons, real app icons via
  NSWorkspace, descriptions while searching, current/drilldown divider,
  Backspace/Left back-navigation, Right enters a submenu, PageUp/Down,
  native NSSearchField text editing, Escape/outside-click dismissal.
- [x] Shipped macOS defaults as an app-bundle resource
  (`Sources/AppBundle/Resources/omarchy-menu.jsonc`): `apps` (provider),
  `system.*` (settings panes, lock, screenshot, activity via the helper),
  `aerospace.*` (shortcuts/conflicts/reload/hotkeys as reserved in-app
  actions `aerospace:*`), `learn.*` (manual links). No Linux commands shipped.
- [x] Per-user extension at `~/.config/aerospace/omarchy/menu.jsonc`; sample
  installed by the installer only when absent (edits survive upgrades). File
  watcher reloads without rebuild; parse failure keeps last-known-good and
  posts a visible notice; actions come only from parsed files, never search
  text.
- [x] Legacy `menu` action removed from `omarchy/action`.
- [x] 16 new tests in `Sources/AppBundleTests/OmarchyMenuDataTest.swift`
  (dialect, parse order/kind/parent, items wrapper, merge, guard script and
  output semantics, search match/scoping/scoring, navigation, slugify,
  provider rows).
- [x] Live: menu mode toggles via CLI trigger-binding on the installed app.
- [ ] Live pixel verification of panel content and typed interaction (blocked:
  the agent session cannot capture the screen; screencapture TCC applies to
  the agent's process, not the terminal).
- [ ] Appearance/theme parity with Omarchy's `[menu]` styling is not attempted;
  the panel keeps the fork's existing 560pt Spotlight-like card. Editable
  appearance config is still open.
- [ ] Omarchy features not ported: route aliases/summon CLI, dmenu modes,
  fonts/power-profiles providers, uninstall flow for app rows.

### UI-04: Generic Tray-Anchored Notification Surface — implemented, installed, pending user acceptance

`MenuBarExtra` was replaced by a manual `NSStatusItem` (`ui/TrayStatusItem.swift`)
because MenuBarExtra hides its status item and cannot anchor anything. The
status item renders the same `MenuBarLabel` via ImageRenderer, exposes the
exact button frame as the anchor, and exposes the native tray menu, including
**Settings…**, configuration access/reload, workspace controls, **Restart**, and
**Quit**. Shortcut diagnostics and app suggestions live in Settings -> Shortcuts,
not a separate conflict HUD or pause menu.

- [x] `ui/TrayNotice.swift`: generic `TrayNotice` model (severity, message,
  rows with per-row actions, footer, optional lifetime, custom section),
  `NoticeCenter` (same-id in-place refresh, equal-content no-op, id-scoped
  dismiss, auto-dismiss), `TrayNoticePanel` (NSPanelHud, hudWindow material,
  content-driven compact size capped at 420x320, slide-down entrance behind
  the menu bar, Reduce Motion respected, stable hosting view with guaranteed
  animation end-state, global+local mouse monitors and Escape-observe
  dismissal that ignores clicks inside the panel, screen-rearrangement
  re-anchoring).
- [x] Actual failed registrations produce compact notices linking to Settings.
  Deduplication prevents periodic checks from reopening dismissed notices;
  resolved state can update a visible notice. Advisory app-shortcut suggestions
  remain Settings-only. Per-conflict pause rows and the rejected standalone
  conflict window are removed.
- [x] Reused for two more notice types: modifier-mouse-gesture failure (was a
  window auto-open; now a warning notice with Accessibility Settings/Retry)
  and menu.jsonc parse errors (error notice with Open menu.jsonc).
- [x] 10 tests in `Sources/AppBundleTests/TrayNoticeTest.swift` (frame
  geometry incl. edge clamping and anchor fallback, replace/dismiss/in-place
  semantics, lifetime auto-dismiss, conflict notice compactness and rows).
- [x] App-lifetime regression fixed that this work exposed: with MenuBarExtra
  gone, SwiftUI terminated the app when the last window closed
  (`NSApplicationDelegateAdaptor` now refuses). Symptom was AeroSpace dying
  whenever the user closed a popup.
- [x] Live: installed app survived a 90s soak through three conflict-check
  cycles with mode toggles; CLI socket and AX window listing verified.
- [x] Codex vision checked the actual 420×170 reserved-shortcut conflict notice:
  title, message, controls, and Review in Settings button were fully visible.
  General, App Widths, and Shortcuts screenshots also showed no confirmed clipping.

Installer repairs done with regression coverage in `omarchy/test_install.py`:
`--stock` no longer references `omarchy-menu` anywhere; `--leader` maps
`space = ["mode main", "mode omarchy-menu"]` inside the leader mode and keeps
the launcher and passthrough sections.

Acceptance status against the original criteria:

1. Option+Space opens the native panel immediately (no AppleScript, no OK
   step) — verified via mode transitions; visual check pending.
2. Customization without rebuilding works through `menu.jsonc` (watcher +
   last-known-good), documented in the shipped sample file.
3. Nested menus, dotted ids, per-key overrides, order preservation, search
   and scoring follow the Omarchy reference; deviations (SF Symbols instead
   of Nerd Font glyphs, `exclude` extension, `aerospace:*` reserved actions)
   are documented in the sample and defaults header.
4. Invalid config contributes nothing and never runs; search text is never
   executed.
5. Shipped entries all dispatch to the local helper or native panes; no
   Linux-only commands shipped.

## 6. What the Omarchy Source Actually Does

Read these local files before continuing UI-03/UI-04:

| Relative to `/Users/cengiz_han/workspace/code/omarchy` | Purpose |
| --- | --- |
| `docs/menu.md` | Menu schema, merge, guards, providers, routes, reload semantics |
| `default/omarchy/omarchy-menu.jsonc` | Shipped menu tree and actual root categories |
| `config/omarchy/extensions/omarchy-menu.jsonc` | Sample per-user extension format |
| `shell/plugins/menu/Menu.qml` | UI, dimensions, search, navigation, selection |
| `shell/plugins/menu/MenuModel.js` | Pure parsing/merge/search logic and semantics |
| `bin/omarchy-menu` | Toggle/summon/close/refresh/ping routing wrapper |
| `test/shell.d/menu-test.sh` and `menu-guards-test.sh` | Behavioral reference tests |
| `default/hypr/bindings/tiling.lua` | Original tiling shortcuts |
| `default/hypr/looknfeel.lua` | Original border/layout values |
| `bin/omarchy-hyprland-workspace-layout-toggle` | Workspace layout toggle |

Key findings already gathered:

- Current local Omarchy uses the Quickshell `omarchy.menu` plugin, not an
  AppleScript-style selector and not necessarily older Walker configurations.
- Defaults are overlaid by `~/.config/omarchy/extensions/omarchy-menu.jsonc`.
  Same-ID overrides replace only declared fields and preserve original order;
  new IDs append. Dotted IDs define the tree.
- An `action` makes a command item, `target` a link, otherwise a submenu.
- Apps come from a runtime provider; app entries cannot steal menu routes.
- Guard work is asynchronous/batched rather than blocking the menu-opening path.
- JSONC in this reference permits whole-line `//` comments and trailing commas;
  inline trailing comments are not supported by its documented parser.
- Defaults include Apps, Learn, Trigger, Style, Setup, Install, Remove, Update,
  About, System. Do not copy Linux package/power commands onto macOS blindly.
- Menu colors come from the central `[menu]` theme section. QML uses roughly
  300-wide normal menus, some 520-wide submenus, 50/58-high rows, a partial-row
  hint when scrolling, and a stable top edge during search.
- The latest user request combines Spotlight-style search with Omarchy fidelity.
  Match the source deliberately and document macOS adaptations rather than
  promising literal pixel identity without side-by-side verification.

## 7. Verification, Gaps, and Build Commands

Historical Swift run: **431 tests passed, zero failures** (405 baseline
+ 10 TrayNoticeTest + 16 OmarchyMenuDataTest, with ShortcutConflictsTest
migrated to notice semantics), at 19:12 on 2026-09-07. Log:
`/tmp/aerospace-fix-build.log`.

During the historical 2026-09-07 handoff, the Python installer suite recorded
**2 tests passed**.
Earlier shell syntax checks and `git diff --check` passed. These checks do not
establish UI acceptance, installation correctness for the new menu, or complete
live mouse/multi-monitor behavior.

For v0.22.1, the full suite passed on GitHub's full-Xcode runner: **462 Swift
tests and 6 Python installer tests**, with zero failures. Full Xcode/XCTest was
unavailable on the local machine; release builds worked with Command Line Tools.
Installed live checks confirmed native Settings opens with General/App Widths/Shortcuts,
layout-preserving restart (details in WM-02), and byte-for-byte preservation of
the existing configuration during upgrade.
Additional live checks exercised Settings Save Width, floating-width capture,
per-app layout defaults, and the actual Option+Control+Shift+W shortcut.
Temporary fixture preferences were removed without replacing existing app
preferences. Standalone executables exercised the production session matcher
and atomic store, plus the production monitor-resolution methods against live
display UUIDs and a missing UUID. No physical monitor-disconnect test was run.

Focused added tests:

- `Sources/AppBundleTests/ScrollingViewportTest.swift`
- `Sources/AppBundleTests/command/ScrollingLayoutTest.swift`
- `Sources/AppBundleTests/ManagedResizeTest.swift`
- `Sources/AppBundleTests/config/ShortcutConflictsTest.swift`
- `Sources/AppBundleTests/SystemModePanelTest.swift`
- `Sources/AppBundleTests/TrayNoticeTest.swift`
- `Sources/AppBundleTests/OmarchyMenuDataTest.swift`
- `macarchy/test_install.py`

Commands, from the repository root:

```sh
python3 macarchy/install.py --build-only
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
python3 -m unittest discover -s macarchy -p 'test_*.py'
bash -n macarchy/action
```

Full Xcode is needed for XCTest, not release builds: Command Line Tools can build
the current release. Bash 5 is required; system Bash 3 cannot run all generation scripts.
The installer selects the Homebrew Bash and generates version/Git metadata
before building. See [the development guide](../dev-docs/development.md) for
toolchain setup and generated-file handling. Format only touched Swift files.

For native UI changes, inspect the actual app and include screenshots or a short
recording when useful. The fork CLI's `trigger-binding` exercises the command
path but does not prove that a physical global shortcut can be registered and
invoked; verify the real key chord separately.

Useful live commands after installing a matching binary/profile:

```sh
~/Applications/macarchy.app/Contents/Helpers/macarchy list-modes --current
~/Applications/macarchy.app/Contents/Helpers/macarchy reload-config --no-gui
~/Applications/macarchy.app/Contents/Helpers/macarchy trigger-binding --mode main alt-shift-esc
~/Applications/macarchy.app/Contents/Helpers/macarchy trigger-binding --mode system esc
```

`exec-and-forget` is config-only, not a CLI subcommand. Do not copy failed
`macarchy exec-and-forget ...` experiments into installation instructions.

## 8. Installation Safety and Rollback

- Build, stage, and verify the signed app before replacing the installation;
  back up the existing app/config/helpers.
- `python3 macarchy/install.py --build` preserves existing configuration and
  Settings. It calls `macarchy restart` when the old version supports it.
  A legacy version without restart support needs a one-time manual quit and
  launch of the new app; no unsupported signal is sent.
- `--profile-only` explicitly replaces the profile after backing it up.
  `--build-only` builds/signs without installing or changing the desktop.
- Signing prefers an available local Developer ID Application identity, with
  ad-hoc fallback. Ad-hoc rebuilds may require a new Accessibility grant; a
  missing grant can delay the socket rather than indicate a crash.
- Do not bypass TCC, disable SIP, or grant security permissions silently.
- Permission policy changed during the session. At handoff the workspace is
  writable, but home config, installed apps, GUI launching, network operations,
  and some build caches may require approval. Re-read active tool instructions.
- Never leave a temporary hotkey-reservation probe running after testing.
- Do not close/edit unrelated user windows. An existing TextEdit Untitled document
  was present during tests; treat it as user data, not a disposable fixture.

Historical backups from the original implementation were recorded under `~/.config/aerospace/backups/`:

| Backup | Meaning |
| --- | --- |
| `20260907-170822-874539` | Earlier original Command-based profile |
| `20260907-173623-291481` | Installer backup before mouse/conflict build update |
| `before-option-shift-escape.toml` | Config before moving Option+Esc |
| `mode-overlay.77X7ECeK/` | App and config before the HUD update |
| `20260907-185919-139683` | Installer backup before the menu/notice/lifetime build (includes prior app) |

Only installer-created directories containing `manifest.json` work with
`python3 macarchy/install.py --restore`. The HUD backup is a manual app/config snapshot,
not that manifest format. Restore also does not automatically switch running
apps or remove all newly introduced helper files; inspect before using it.

## 9. Recommended Continuation Order

1. Continue visual acceptance on varied displays and accessibility settings.
   Native Settings, compact notices, and workspace indicators were visually
   checked during the later implementation work. Verify the launcher, menu
   navigation, notice dismissal, and actual key chords on the target setup;
   record the steps and result rather than inferring them from unit tests.
2. If visuals pass, complete UI-03 residuals: editable appearance/theme config,
   route aliases (`omarchy menu summon <name>` equivalent), per-user provider
   behavior beyond `apps`.
3. Complete mouse, resize, focus, and multi-monitor acceptance (WM-02/WM-03
   open items); record residual macOS limitations without claiming untested
   parity.
4. Submit subsequent focused changes through PRs against `main`; v0.22.1 is
   already published. Follow [CONTRIBUTING.md](../CONTRIBUTING.md).
5. Keep these implementation notes and the project guide updated with actual results.

## 10. Broader Parity Backlog

These fall under the user's broad request to go beyond the initial setup, but
should not displace the explicit UI priorities above:

- [ ] Review pseudo-tiling, pinning, and group semantics.
  Option+P currently balances sizes; it is not Omarchy's pseudo-window behavior.
- [ ] Assess modifier+wheel workspace/group navigation.
- [ ] Assess true overlay scratchpad vs. the current scratch workspace.
- [ ] Assess smoother scrolling and better multi-monitor overflow handling within
  macOS constraints; no compositor implementation currently exists.
- [ ] Centralize theme/style customization across launcher, HUD, tray surfaces,
  and border companion without inventing fake Linux theme propagation.
- [ ] Review application defaults and helper fallbacks against installed Mac apps.
- [x] Persist widths/viewport state and preserve settings during upgrades;
  prefer stable local signing with ad-hoc fallback.

Exact compositor clipping, complete Hyprland grouping, every Quickshell plugin,
Linux package management, and universal shortcut-owner/removal APIs are not
implemented. Some are platform constraints, others are future engineering work.
Keep that distinction explicit in subsequent status reports.
