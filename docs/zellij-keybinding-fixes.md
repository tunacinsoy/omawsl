# Zellij / Windows Terminal keybinding fixes (interim)

> **Status: interim stopgap, added during Phase 5 (Theming).** This is **not**
> part of the design spec's documented doc structure (§13, §16) — it exists so
> the real, sourced finding below isn't lost before Phase 6 builds
> `docs/windows-setup.md` and `windows/windows-terminal.json` /
> `windows-terminal-fallback.json` (design spec §13). **Phase 6 must fold this
> finding into both of those `windows/*.json` files (both need the identical
> fix — it's independent of which font variant the user merged in) and delete
> this file.** Do not leave `windows-terminal.json` shipping without this fix
> just because this doc exists — the fix isn't real until it's in the JSON a
> user actually merges into their `settings.json`.

## The collision

Cross-referencing Omakub's real zellij keybindings (`configs/zellij.kdl`,
ported verbatim in Phase 5 Task 1) against Windows Terminal's real default
keybindings (`microsoft/terminal` `main` branch,
`src/cascadia/TerminalSettingsModel/defaults.json`) turns up exactly one
direct, real collision:

**`Alt+Left` / `Alt+Down` / `Alt+Up` / `Alt+Right`** is bound by both layers:

- Windows Terminal (default): `Terminal.MoveFocusLeft` / `Down` / `Up` / `Right`
  — moves focus between **Windows Terminal's own** split panes.
- zellij (`configs/zellij.kdl`, `shared_among "normal" "locked"`): the same
  four chords fire `MoveFocusOrTab`/`MoveFocus` between **zellij's own** panes
  — and critically, this is one of the few bindings zellij fires even in its
  default `locked` mode, without needing `Ctrl g` to unlock first.

Since Windows Terminal owns the keypress at the terminal-app layer, it
intercepts `Alt+Left/Down/Up/Right` before zellij (running inside it) ever
sees the keystroke — even when Windows Terminal itself has no other pane to
move focus to (the common case, since zellij is the pane multiplexer here,
not Windows Terminal). Net effect: these four zellij bindings are dead by
default under Windows Terminal.

Every other zellij binding was checked against the full Windows Terminal
default keybinding list and found *not* to collide — Omakub's zellij runs in
`default_mode "locked"` with `clear-defaults=true`, so almost nothing else
fires without first unlocking (`Ctrl g`) into a leader-key mode
(`p`=pane, `t`=tab, `r`=resize, `s`=scroll, `o`=session, `m`=move), and none
of those leader chords or their follow-up keys match a Windows Terminal
default.

## The fix

Unbind Windows Terminal's default `Alt+Left/Down/Up/Right` pane-focus
bindings so the keystroke passes through to zellij. Windows Terminal's
documented mechanism for clearing a default keybinding is to redeclare the
same `keys` with `"command": "unbound"` in the user's own `actions`/
`keybindings` array:

```json
{ "command": "unbound", "keys": "alt+left" },
{ "command": "unbound", "keys": "alt+down" },
{ "command": "unbound", "keys": "alt+up" },
{ "command": "unbound", "keys": "alt+right" }
```

**This exact JSON snippet is not yet verified against a real, current
Windows Terminal settings.json** — Windows Terminal's schema has evolved
(older `keybindings`/`command` vs. newer `actions`/`id`), and both are
believed still supported for backward compatibility, but this needs
confirming for real, not assumed. **Task 9 (manual verification) must apply
this snippet to the real test machine's actual Windows Terminal
`settings.json`, confirm `Alt+Left/Down/Up/Right` reaches zellij afterward,
and update this file with whatever the real, working form turns out to be**
before Phase 6 copies it into `windows/windows-terminal.json` /
`windows-terminal-fallback.json`.

## Everything else: confirmed non-issue, not a UX gap worth changing

- `Ctrl+Shift+T` (WT: new tab), `Ctrl+Shift+W` (WT: close pane) — no chord
  collision (zellij's own tab-new/pane-close are multi-key sequences behind
  `Ctrl g`), so no fix needed, even though WT "owns" these chords first.
- `Ctrl+Tab` / `Ctrl+Shift+Tab` (WT: next/prev tab) — no zellij binding on
  these chords at all.
- `Ctrl+,` (WT: settings), `Ctrl+Shift+F` (WT: find) — no zellij collision.
