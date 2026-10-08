# Herdr in omawsl (preview)

[Herdr](https://herdr.dev) is a terminal multiplexer built for AI coding agents: it shows
which agent in which pane is working, blocked or done, notifies you, and resumes agent
conversations after a restart. omawsl offers it as an alternative to zellij - never both at
once. Every new terminal opens exactly one of them.

It's marked **preview** because Herdr itself is still pre-1.0.

## Switching

    omawsl multiplexer herdr     # installs Herdr if needed; new terminals open Herdr
    omawsl multiplexer zellij    # back to zellij
    omawsl multiplexer           # choose interactively

The terminal you run it in doesn't change - open a new one. If Herdr can't be downloaded
(e.g. a corporate network blocking herdr.dev), the choice stays on zellij.

## Same keys as zellij

omawsl's Herdr config (`configs/herdr.toml`, deployed to `~/.config/herdr/config.toml` only
if you don't already have one) ports omawsl's zellij keymap:

| You press | Does |
|---|---|
| `Alt h/j/k/l`, `Alt ←↓↑→` | focus pane (h/l switch tab at the edge, like zellij) |
| `Alt n` | new pane |
| `Alt =` / `Alt -` | grow / shrink pane |
| `Alt i` / `Alt o` | move tab left / right |
| `Ctrl g p` → `hjkl n d r x f c Tab` | pane mode |
| `Ctrl g t` → `hjkl 1-9 n x r b [ ]` | tab mode |
| `Ctrl g r` → `hjkl HJKL + - =` | resize mode |
| `Ctrl g m` → `hjkl n p Tab` | move mode |
| `Ctrl g Ctrl q` | quit (asks first) |
| `Ctrl g w` | workspace picker (`↑↓`, `Enter`) |
| `Ctrl g [` / `Ctrl g ]` | previous / next workspace |
| `Ctrl g 1-9` | jump to workspace 1-9 (tabs are `Ctrl g t 1-9`) |

Herdr itself only supports one key after its prefix, so the mode keys run through a small
popup (`bin/omawsl-herdr-mode`) that shows the mode's hints and reads your next key -
`Esc`, `Enter` or `Ctrl g` leave it, just like zellij.

## What's different

- **Session mode** (`Ctrl g o`) only points at Herdr's own keys: detach is `Ctrl g q`,
  sessions/workspaces `Ctrl g w`, jump to an agent `Ctrl g g`, settings `Ctrl g ,`.
- **Scroll** (`Ctrl g s`) is Herdr's copy mode: `j/k`, `PageUp/PageDown` and `Ctrl b/Ctrl f`
  are the same; half-page is `Ctrl u/Ctrl d` (not `u/d`), search is `/` (not `f`),
  edit scrollback is `Ctrl g e`.
- **Floating panes**: none in Herdr. `Alt f` opens a scratch shell popup instead; exit it to
  get back.
- **`Alt +`** can't be bound in Herdr 0.9 - use `Alt =`, which grows the pane in zellij
  too.
- **Herdr dialogs**: cancelling one with `Esc` (e.g. `Ctrl g Shift d`'s "Close workspace?")
  lands in Herdr's NAVIGATE mode, which swallows what you type - press `Esc` again.
- **Tab mode's `h/j/k/l`** switch one tab and close the popup (zellij stays in tab mode) -
  Herdr loses track of a popup that changes tabs while it's open. Repeat `Ctrl g t l`, or
  use `Alt h/l`.
- **Not available**: swap layouts (`Alt [ ]`), pane-frame toggle, tab sync, last-tab toggle.

## Themes

`omawsl theme` switches Herdr too. Themes Herdr has built in map directly (Rose Pine maps to
Herdr's light `rose-pine-dawn`, matching omawsl's Rose Pine); the rest use Herdr's
`terminal` theme, which follows Windows Terminal's colors.

## Removing it

    omawsl uninstall herdr

Run it from a zellij terminal, not from inside Herdr - it stops Herdr's server. New
terminals go back to zellij.
