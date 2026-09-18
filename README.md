# OmaTouch

An on-screen touch keyboard for Omarchy, built for tablet mode. Types full
AltGr levels, composes dead-key accents, and adds any language your system's
own `xkb` data supports, with nothing installed on your system until you
explicitly ask for it.

![Keyboard over a live theme, French AZERTY](https://github.com/M44F4/omatouch/releases/download/v1.1.0/keyboard-english-omaplus.png)
![Following the theme live, rounded corners](https://github.com/M44F4/omatouch/releases/download/v1.1.0/keyboard-solitude-theme.png)
![Mode tab: style, size, languages](https://github.com/M44F4/omatouch/releases/download/v1.1.0/settings-mode-tab.png)
![Appearance tab: opacity, radius, key color](https://github.com/M44F4/omatouch/releases/download/v1.1.0/settings-appearance-tab.png)
![Advanced tab: capability cards](https://github.com/M44F4/omatouch/releases/download/v1.1.0/settings-advanced-gesture.png)

## Features

- Four card styles: Omicro (compact QWERTY), Omini (+ modifiers), Omapad
  (phone-style, dedicated number row), Omaplus (full ANSI layout). Switch
  any time, each remembers its own size.
- Full AltGr / level-3 and level-4 characters, not just the first two levels
  (French `@`/`€`, and whatever your layout's own third and fourth levels are)
- Dead-key composition (`^` then `e` → `ê`), driven by the system's own X11
  Compose table, not a hand-typed table
- Long-press a key for its accent/symbol variants
- Shift and Ctrl/Alt/Super with tap-once or stay-on (sticky) behavior, your
  choice
- Live theme following, adjustable size/opacity/radius/border per style
- A real in-app language picker. Add any of the ~600 layouts and variants
  your system's `xkb` data knows, generated on the spot, no privileged access
  needed.
- Optional Super-key shortcuts and a three-finger double-tap gesture to
  open/close the keyboard, both fully opt-in, see below

## Languages

English ships in the box. Adding another language (Settings → Mode → *Add a
Language…*) reads directly from your system's own `xkb` layout database and
generates that language's keyboard on the spot. No network call, no
privileged access, nothing written outside this plugin's own state folder.

A handful of layouts are tagged **NOT SUPPORTED** in that list. This isn't a
hand-picked blocklist. Every layout is actually generated and compared
against plain US English, and anything that comes back character-for-character
identical gets flagged. That's exactly what `xkb`'s own "Chinese", "Japanese",
and "Korean" layouts do under the hood: real input for those languages needs
an IME (an input-method popup that converts what you type into candidate
characters), which `xkb` doesn't provide and this plugin doesn't implement.
Picking one of those without the tag would just look like it's typing English.

Right-to-left scripts (Arabic, Hebrew, Persian, and others) are **not** in
that list. They work correctly. This keyboard only injects the Unicode
characters; the app you're typing into handles its own bidirectional
rendering, the same as any other keyboard.

## Requirements

`wtype` is the only hard requirement: it's the sole thing plain typing
calls. Everything else below belongs to one specific feature, not to
typing itself, and the bundled English keyboard works without any of
them:

- `python3` + `xkbcli` / `libxkbcommon`: generating a new language.
  If you never add one, neither is needed.
- `hyprctl`: first-run layout auto-detection only. If it's missing or
  fails, this falls back to English instead of breaking.
- `wl-copy`: the clipboard-copy buttons for setup commands and the
  clipboard-history shortcut, unrelated to typing.

Optional, only if you opt into the feature below:

- **Super Key Support:** `ydotool` (also used at typing-time for
  Super-key chords specifically, once set up), a dedicated `omatouch`
  group, and access to `/dev/uinput`
- **Three-Finger Gesture:** membership in the standard `input` group

## What it installs, and how to undo it

Both of these are entirely opt-in. Nothing runs from inside the plugin
itself. Each one is a plain shell script you copy from Settings → Advanced
and run yourself, so you can read it first.

| Capability | What it installs | Undo |
|---|---|---|
| **Super Key Support** | `ydotool` (official package), a dedicated `omatouch` group + one udev rule for `/dev/uinput`, a small background service | Settings → Advanced → Super Key Support → *Uninstall…*. Removes exactly what it added, and only that. |
| **Three-Finger Gesture** | Your account into the standard `input` group (the one that already owns touch devices, not a group this plugin invents), a small background service watching for the gesture | Settings → Advanced → Three-Finger Gesture → *Uninstall…*. Same principle. |

If you were already in the relevant group before installing, uninstalling
leaves that alone. It only removes what it actually added, never someone
else's prior setup. Both services start at boot once installed; that's a
genuine, ongoing system change worth knowing about, not a one-time script run.

## Privacy & security

| Claim | Why it's true |
|---|---|
| Cannot log keystrokes | Zero `console.*`/logging calls anywhere typed text passes through |
| No network, no telemetry | Nothing here makes a network request. The language picker reads local `xkb` data only. |
| No `sudo`/`pkexec` from inside the plugin | Every privileged action is a command you copy and run yourself, in your own terminal |
| Nothing runs at install | Omarchy never executes plugin code on `plugin add`. Every capability above is opt-in and manual. |
| State confined to XDG dirs | Settings and generated languages live in `~/.local/state/omarchy/omatouch/`, nothing is written into the plugin folder at runtime |
| Plain, readable code | QML, JavaScript, Python, and bash. No obfuscation, nothing downloaded and executed. |

The two opt-in capabilities are real security-relevant changes and are stated
plainly, not buried: `/dev/uinput` access (Super key) means synthetic input
injection at the kernel level; `input` group membership (gesture) means read
access to every input device on the machine, including your physical
keyboard. Both are the documented, standard price of the feature they enable,
stated here so the choice is informed, not because they're unusual for what
they do.

## Known limitations

- **No CJK/IME support.** See Languages above; this needs a real
  input-method engine the shell doesn't currently expose.
- **No auto-show on text-field focus, no auto-hide when a physical keyboard
  reconnects.** Both need compositor protocol support this shell doesn't
  currently have; open/close is manual or via the three-finger gesture.
- **Multi-key Compose sequences aren't supported.** Only two-key sequences
  (`<dead_X> <Y>`), which covers the overwhelming majority of real dead-key
  accents.
- **Long-press is tap-to-pick**, not drag-to-select. Lift your finger, then
  tap a variant from the popup, rather than dragging in one motion.

## Reporting bugs

Report OmaTouch problems at
[github.com/M44F4/omatouch/issues](https://github.com/M44F4/omatouch/issues),
not on the main Omarchy repo, since this is a third-party plugin and
misfiled issues just cost everyone time. Settings → Advanced → *About* has a
**Copy diagnostics** button for exactly this: it copies plugin version,
active style/language, capability status, and detected dependencies. Never
keystrokes, clipboard contents, or file contents.

## Install

```bash
omarchy plugin add https://github.com/M44F4/omatouch --enable
```

Or add it manually: clone into
`~/.config/omarchy/plugins/M44F4.omatouch/` and enable it from Omarchy's
plugin manager. As with any third-party plugin, read the code before enabling
it. Everything above is meant to make that easy, not to replace it.

## License

MIT. See [LICENSE](LICENSE).
