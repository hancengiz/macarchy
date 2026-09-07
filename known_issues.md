# Known issues

## Option+Left/Right conflicts with macOS text-editing shortcuts

macarchy binds **Option+←/→** to *focus previous/next window* (Omarchy's
Super+Left/Right). macOS uses the exact same chords as the standard
**"move to previous/next word"** caret commands in every text area — editors,
browser URL bars, terminal prompts, mail compose, and so on.

Because macarchy owns those chords globally, typing in any text field loses
native word-jump on Option+arrows (and other bound Option+letter chords also
swallow their special-character output, e.g. Option+L would normally type
"¬").

Workarounds:

- Use **pass-through mode** (Option+;) to suspend all desktop bindings while
  writing; press it again to resume.
- Most native apps still support the emacs-style caret commands:
  Control+F/B/A/E move forward/back/start/end of line, and Option+Click
  places the caret anywhere.
- The `--leader` installer profile keeps every binding behind a single F18
  leader key, leaving Option completely free for text input.

This is an intentional trade-off: macOS has no separate "Super" modifier, so
Option must play that role for an Omarchy-like experience. It cannot be fixed
per-app without synthetic Command forwarding, which this fork deliberately
avoids.

## Launcher activation flash

Opening a new window in a *running* app (Option+Enter) requires activating
the app before sending Cmd+N. macOS focuses the app's existing window first,
so you may see a brief flash of the workspace containing that window before
the new window is pulled into your current workspace. Window placement is
correct; only the transit is visible. New-window keystrokes also need a
one-time **Automation → System Events** grant in Privacy & Security.

## Platform limits inherited from AeroSpace

- No compositor: no smooth scrolling animation, no per-monitor clipping —
  adjacent displays can expose column overflow, and apps can enforce minimum
  window sizes.
- Column widths and viewport positions reset on restart (not persisted).
- Shortcut-conflict detection is best-effort; macOS exposes no universal
  owner lookup or removal API for another app's shortcuts.
- Native-fullscreen windows cannot be covered by overlays (menu, HUD,
  notifications dock above normal windows only).
