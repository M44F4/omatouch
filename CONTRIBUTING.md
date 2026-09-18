# Contributing to OmaTouch

## Before filing an issue

Please search [existing issues](https://github.com/M44F4/omatouch/issues) first
to avoid duplicates.
Include your OmaTouch version and, if it's a display or typing bug, the
active keyboard style and language. Settings → Advanced → About → **Copy
diagnostics** gets most of this in one tap.

Report OmaTouch problems here, not on Omarchy's own repo. This is a
third-party plugin, and misfiled issues on the main project just create
noise for its maintainers without getting your bug seen by anyone who can
actually fix it.

## Making a change

Everything here is plain QML, JavaScript, Python, and bash. No build step.
Edit files directly under
`~/.config/omarchy/plugins/M44F4.omatouch/` and run

```bash
omarchy restart shell
```

to reload. Check `qs log -f -p /usr/share/omarchy/shell` for QML errors.
They don't show up in `journalctl`, since the shell is a plain process, not
a systemd unit. The two systemd-backed pieces (Super Key Support, the
three-finger gesture) do log to `journalctl`, since those genuinely are
services.

## Ground rules a PR needs to hold

These aren't style preferences. They're the actual claims the README makes
about this plugin, and a PR that breaks one of them breaks user trust, not
just a lint rule:

- **No `console.*` calls anywhere.** This is the basis for the "cannot log
  keystrokes" claim.
- **No network calls.** No `curl`, `wget`, `fetch`, `XMLHttpRequest`,
  anywhere. The language picker's "600 layouts" comes entirely from local
  `xkb` data, never a request.
- **No `sudo`/`pkexec` from inside the plugin.** Anything that needs
  privilege is a script the user copies and runs in their own terminal,
  never executed for them. See `bin/omatouch-super.sh` and
  `bin/omatouch-gesture.sh` for the existing pattern.
- **Never hand-author character/language data.** Everything about a
  language (its characters, its dead keys, whether it even has a usable
  script here) is derived from `xkbcli`, `libxkbcommon`, and the system's
  own X11 Compose table (see `bin/omatouch-lang-gen.py`). If you're tempted
  to type out a table of characters for some language, stop. There's
  almost certainly a way to derive it instead, and a hand-typed table is
  exactly the kind of thing that quietly goes wrong for a language nobody
  on the project actually reads.

## Testing a change

There's no automated test suite. Verification is manual, against the
actual running keyboard:

1. Make the change, `omarchy restart shell`.
2. Check the log for errors (see above).
3. Actually type with it. A change to layout/character logic needs testing
   in a real text field, not just a visual glance at the keyboard.
4. If you touched language generation, regenerate a couple of real
   languages (`python3 bin/omatouch-lang-gen.py --layout fr`) and check the
   output, not just that the command exits `0`.

## Pull requests

Small, focused PRs are much easier to review than one that touches five
unrelated things. If you're planning something larger, open an issue first
to talk through the approach before writing the code.
