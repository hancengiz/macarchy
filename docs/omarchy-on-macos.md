# Omarchy on macOS: Product Requirements and Agent Handoff

Last updated: 2026-09-07, Europe/Istanbul.

## 0. Rebrand (2026-09-07, latest)

The project is now **macarchy** ("Omarchy-like tiling manager for macOS"), a
fork of AeroSpace (MIT, © Nikita Bobko; LICENSE.txt retained). App bundle:
`~/Applications/macarchy.app`, identifier `com.hancengiz.macarchy`, GitHub
repo `hancengiz/macarchy`. The old `AeroSpace-Omarchy.app` is superseded —
delete it and re-grant Accessibility to macarchy after the first launch.
User guide: `README.md`; known issues incl. Option+arrow text-input
conflicts: `known_issues.md`. CI: `.github/workflows/macarchy-release.yml`
builds the app on every push to main and publishes releases on `v*` tags.

## 1. Read This First

**The work is not finished.** The window-manager features and a system-mode HUD
are installed. The user rejected the installed launcher and the oversized
shortcut-conflict window. A replacement launcher prototype compiles in the
working tree but is **not installed**. JSONC menu customization and a reusable,
animated tray-anchored notification surface are **not implemented**.

Do not mistake checked implementation tasks below for user acceptance or complete
live verification. Each area records its separate verification and acceptance status.

### Repository and References

| Item | Location |
| --- | --- |
| Working repository | `/Users/cengiz_han/workspace/code/AeroSpace` |
| Working branch | `omarchy-desktop` |
| User's fork / `origin` | `https://github.com/hancengiz/AeroSpace.git` |
| `upstream` | `https://github.com/nikitabobko/AeroSpace.git` |
| Local Omarchy reference source | `/Users/cengiz_han/workspace/code/omarchy` |
| Public references | <https://omarchy.org/manual/> and <https://omarchy.org/manual/hotkeys/> |
| Existing fork guide | [omarchy/README.md](../omarchy/README.md) |

All feature edits remain local and uncommitted. No feature commit or push was
made during this work. There are many modified and untracked files; preserve them.
Read the worktree before editing. Do not reset it or overwrite user configuration.

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
| Conflict detection and Recheck feedback | Installed | Implemented; conflict presentation migrated to the tray notice surface |
| Current-shortcuts menu entry | Installed | Implemented |
| Option+Space menu | Installed: native data-driven launcher panel | Implemented; JSONC defaults + user extension |
| Data-driven Omarchy menu customization | Installed (`menu.jsonc` sample + watcher) | Implemented |
| Generic tray notification/popover component | Installed | Implemented (NSStatusItem anchor; conflicts, modifier-mouse, menu parse errors) |

### Installed Artifacts

- App: `~/Applications/AeroSpace-Omarchy.app`.
- Bundle identifier: `com.hancengiz.aerospace`.
- Installed version label: `0.22.0-Omarchy`, snapshot build.
- Fork CLI: `~/Applications/AeroSpace-Omarchy.app/Contents/Helpers/aerospace`.
- Config: `~/.aerospace.toml`.
- Helper: `~/.config/aerospace/omarchy/action`.
- Generated reference: `~/.config/aerospace/omarchy/HOTKEYS.txt`.
- Build artifact: `.local/AeroSpace-Omarchy.app`; rebuild before treating it as
  matching the latest source.
- Original Homebrew app remains at `/Applications/AeroSpace.app`; do not run both
  window managers simultaneously. The Homebrew CLI talks to the upstream socket,
  not the fork's socket.
- Fork socket identity is separate: `/tmp/com.hancengiz.aerospace-<username>.sock`.

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
- [ ] Commit/push reviewed changes only when requested; none have been published.

Implementation: `Sources/Common/appMetadata.swift`,
`Sources/AppBundle/config/startAtLogin.swift`, `omarchy/install.py`.

Packaging trap already fixed: default Mac filesystems are case-insensitive.
Putting `AeroSpace` and `aerospace` in the same directory overwrites one with the
other. The app executable belongs in `Contents/MacOS`; CLI in `Contents/Helpers`.

### WM-02: Horizontal Scrolling Columns

- [x] Add `.scrolling` layout and `layout scrolling` command support.
- [x] Add configurable default column width, currently 49% of the viewport.
- [x] Keep per-column width overrides and per-container viewport offset.
- [x] Reveal the focused column with the smallest necessary horizontal movement.
- [x] Preserve widths of partially visible neighboring columns.
- [x] Park fully offscreen columns using AeroSpace's corner-hiding mechanism.
- [x] Restore offscreen columns when focused and when management is disabled.
- [x] Toggle scrolling/horizontal tiles on the same workspace with Option+L.
- [x] Keep scrolling horizontal when Option+J is pressed; split orientation
  toggles apply to tiles rather than rotating the scrolling strip vertically.
- [x] Add geometry, traversal, resize, config, and layout-toggle tests.
- [ ] Complete live acceptance on multiple monitors and varied app minimum sizes.
- [ ] Verify long sequences of focus, close, reopen, monitor move, fullscreen,
  float/tile, disable/enable, and nested-container operations.

Implementation: `tree/TilingContainer.swift`, `tree/TreeNode.swift`,
`tree/Window.swift`, `layout/ScrollingViewport.swift`, `layout/layoutRecursive.swift`,
`layout/refresh.swift`, `command/impl/LayoutCommand.swift`,
`command/impl/ResizeCommand.swift`, `command/impl/BalanceSizesCommand.swift` under
`Sources/AppBundle`, plus `Sources/Common/cmdArgs/impl/LayoutCmdArgs.swift`.

Widths/offsets are in memory, not persisted across app restarts. Per-monitor
compositor clipping and smooth Hyprland scrolling animation are not implemented.
Adjacent displays can expose overflow; apps can enforce minimum sizes.

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
| Option+J | Toggle split orientation in tiles |
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
| Option+Space | Desktop menu, currently being replaced |
| Option+K | Generated shortcut reference |
| Option+semicolon | Toggle pass-through mode |
| Option+Control+R | Reload config |

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
- [x] Pause detectable conflicting AeroSpace bindings; do not alter other apps.
- [x] Deduplicate warnings and preserve configuration diagnostics.
- [x] Offer Recheck, Pause in AeroSpace, app/settings/config access.
- [x] Keep Check Shortcut Conflicts and Show Current Shortcuts in the menu bar.
- [x] Show check time, no-conflict status, and reasons checking is unavailable.
- [x] Allow manual checking when automatic warnings are disabled.
- [x] Test a real Carbon reservation, probe cleanup, reset, resolution, and dedup.
- [ ] Replace the rejected window with the compact tray surface in UI-04.
- [ ] Test conflict removal in a second app followed by Recheck end to end.
- [ ] Improve paused-state visibility and make restoration discoverable; currently
  manual pauses are session-only and reset on config reload.

Implementation: `Sources/AppBundle/config/ShortcutConflicts.swift`,
`config/HotkeyBinding.swift`, `ui/ShortcutConflictList.swift`, `ui/MessageView.swift`,
`ui/MenuBar.swift`, `ui/currentShortcutsDescription.swift`.

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
exact button frame as the anchor, and provides the full menu (identification,
copy, Omarchy menu, conflicts, current shortcuts, config warnings, workspaces
with checkmarks, sponsor, enable/disable, experimental style picker, config
editor, reload, quit) as a native NSMenu rebuilt on every open.

- [x] `ui/TrayNotice.swift`: generic `TrayNotice` model (severity, message,
  rows with per-row actions, footer, optional lifetime, custom section),
  `NoticeCenter` (same-id in-place refresh, equal-content no-op, id-scoped
  dismiss, auto-dismiss), `TrayNoticePanel` (NSPanelHud, hudWindow material,
  content-driven compact size capped at 420x320, slide-down entrance behind
  the menu bar, Reduce Motion respected, stable hosting view with guaranteed
  animation end-state, global+local mouse monitors and Escape-observe
  dismissal that ignores clicks inside the panel, screen-rearrangement
  re-anchoring).
- [x] Conflicts migrated: warning notices with per-conflict Pause rows,
  Keyboard Settings/Recheck actions, "Open App…" running-apps menu only when
  conflicts exist, compact success state (Recheck only) when resolved,
  checked-time footer stable across monitor cycles, dedup so periodic checks
  never re-open a dismissed notice. Manual reopen via Check Shortcut
  Conflicts. The rejected `ShortcutConflictList` window is deleted.
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
- [ ] Live pixel verification blocked as above; user reported an "empty popup"
  against the first broken build — render path hardened (stable hosting view,
  forced end-state) but visual confirmation is still owed.

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

Latest recorded Swift run: **431 tests passed, zero failures** (405 baseline
+ 10 TrayNoticeTest + 16 OmarchyMenuDataTest, with ShortcutConflictsTest
migrated to notice semantics), at 19:12 on 2026-09-07. Log:
`/tmp/aerospace-fix-build.log`.

The Python installer suite was rerun during this handoff: **2 tests passed**.
Earlier shell syntax checks and `git diff --check` passed. These checks do not
establish UI acceptance, installation correctness for the new menu, or complete
live mouse/multi-monitor behavior.

Focused added tests:

- `Sources/AppBundleTests/ScrollingViewportTest.swift`
- `Sources/AppBundleTests/command/ScrollingLayoutTest.swift`
- `Sources/AppBundleTests/ManagedResizeTest.swift`
- `Sources/AppBundleTests/config/ShortcutConflictsTest.swift`
- `Sources/AppBundleTests/SystemModePanelTest.swift`
- `Sources/AppBundleTests/TrayNoticeTest.swift`
- `Sources/AppBundleTests/OmarchyMenuDataTest.swift`
- `omarchy/test_install.py`

Commands, from the repository root:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
python3 -m unittest discover -s omarchy -p 'test_*.py'
bash -n omarchy/action
git diff --check
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer python3 omarchy/install.py --build-only
```

Use full Xcode: Command Line Tools alone did not supply XCTest. Bash 5 is installed
at `/opt/homebrew/bin/bash`; system Bash 3 cannot run all generation scripts.
The installer invokes the correct Bash and uses release `-Xswiftc -DOMARCHY`.
The repo formatter is `.deps/swiftformat/swiftformat`; format only touched files.
Generated `Sources/Common/versionGenerated.swift` was restored to its original
`0.0.0-SNAPSHOT` after builds to avoid unrelated metadata churn.

For native UI verification, prior work used the computer-use skill and
`@oai/sky` through Node REPL. Read the skill before reuse. App-state screenshots
can inspect the HUD and dialogs. That tool's app-targeted key presses do not
invoke global shortcuts; use the fork CLI's `trigger-binding` for command-path
checks, and separately verify actual global-key behavior when possible.

Useful live commands after installing a matching binary/profile:

```sh
~/Applications/AeroSpace-Omarchy.app/Contents/Helpers/aerospace list-modes --current
~/Applications/AeroSpace-Omarchy.app/Contents/Helpers/aerospace reload-config --no-gui
~/Applications/AeroSpace-Omarchy.app/Contents/Helpers/aerospace trigger-binding --mode main alt-shift-esc
~/Applications/AeroSpace-Omarchy.app/Contents/Helpers/aerospace trigger-binding --mode system esc
```

`exec-and-forget` is config-only, not a CLI subcommand. Do not copy failed
`aerospace exec-and-forget ...` experiments into installation instructions.

## 8. Installation Safety and Rollback

- Build completely before stopping/replacing the running app. Verify the PID,
  stop only the fork, back up the app/config/helpers, and install matching pieces.
- `--build` and `--profile-only` overwrite the home profile with the template.
  Inspect and preserve user edits; do not use them blindly during iteration.
- Ad-hoc signing changes the designated code hash each build. macOS may revoke
  Accessibility; the app waits before starting its socket. Connection refused
  can therefore mean missing permission rather than a crash.
- Do not bypass TCC, disable SIP, or grant security permissions silently.
- Permission policy changed during the session. At handoff the workspace is
  writable, but home config, installed apps, GUI launching, network operations,
  and some build caches may require approval. Re-read active tool instructions.
- Never leave a temporary hotkey-reservation probe running after testing.
- Do not close/edit unrelated user windows. An existing TextEdit Untitled document
  was present during tests; treat it as user data, not a disposable fixture.

Backups under `~/.config/aerospace/backups/` include:

| Backup | Meaning |
| --- | --- |
| `20260907-170822-874539` | Earlier original Command-based profile |
| `20260907-173623-291481` | Installer backup before mouse/conflict build update |
| `before-option-shift-escape.toml` | Config before moving Option+Esc |
| `mode-overlay.77X7ECeK/` | App and config before the HUD update |
| `20260907-185919-139683` | Installer backup before the menu/notice/lifetime build (includes prior app) |

Only installer-created directories containing `manifest.json` work with
`omarchy/install.py --restore`. The HUD backup is a manual app/config snapshot,
not that manifest format. Restore also does not automatically switch running
apps or remove all newly introduced helper files; inspect before using it.

## 9. Recommended Continuation Order

1. Get pixel-level visual acceptance of the launcher panel and the tray notice
   from the user (the agent session cannot capture the screen). The user
   previously saw an empty popup from a broken build; the render path is
   hardened but unconfirmed visually. Known specifics to eyeball: notice
   appears below the workspace indicators with content, slides down, closes on
   outside click/Escape; menu rows show icons/descriptions; submenus navigate
   with Right/Backspace.
2. If visuals pass, complete UI-03 residuals: editable appearance/theme config,
   route aliases (`omarchy menu summon <name>` equivalent), per-user provider
   behavior beyond `apps`.
3. Complete mouse, resize, focus, and multi-monitor acceptance (WM-02/WM-03
   open items); record residual macOS limitations without claiming untested
   parity.
4. Commit/push when the user asks. All work is local and uncommitted.
5. Keep this PRD and the fork guide updated with actual results.

## 10. Broader Parity Backlog

These fall under the user's broad request to go beyond the initial setup, but
should not displace the explicit UI priorities above:

- [ ] Review pseudo-tiling, pinning, group semantics, and saved/restored widths.
  Option+P currently balances sizes; it is not Omarchy's pseudo-window behavior.
- [ ] Assess modifier+wheel workspace/group navigation.
- [ ] Assess true overlay scratchpad vs. the current scratch workspace.
- [ ] Assess smoother scrolling and better multi-monitor overflow handling within
  macOS constraints; no compositor implementation currently exists.
- [ ] Centralize theme/style customization across launcher, HUD, tray surfaces,
  and border companion without inventing fake Linux theme propagation.
- [ ] Review application defaults and helper fallbacks against installed Mac apps.
- [ ] Consider width/viewport persistence and a stable signing/update workflow.

Exact compositor clipping, complete Hyprland grouping, every Quickshell plugin,
Linux package management, and universal shortcut-owner/removal APIs are not
implemented. Some are platform constraints, others are future engineering work.
Keep that distinction explicit in subsequent status reports.
