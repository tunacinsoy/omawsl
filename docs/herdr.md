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

## Notifications

Herdr can tell you when an agent in another tab or workspace finishes or needs input. Out of
the box it can't reach Windows from WSL, so omawsl asks how you want it (on first run, when
you pick Herdr) and lets you change it any time:

    omawsl notifications           # choose interactively
    omawsl notifications both      # sound + Windows popup
    omawsl notifications sound     # sound only
    omawsl notifications popup     # Windows popup only
    omawsl notifications off

- **Sound** installs `pulseaudio-utils` - the one step that asks for your sudo password, once
  per machine. Herdr plays its sounds with `paplay`, which reaches your Windows speakers
  through WSLg.
- **Popup** links `bin/omawsl-notify-send` in as `~/.local/bin/notify-send` (an existing
  `notify-send` there is left alone) and sets Herdr's `[ui.toast] delivery = "system"`. It
  shows a normal Windows notification via PowerShell. The popup is silent - pick `both` for
  a sound too.

Good to know:

- Herdr only notifies for agents in a tab you're **not** looking at - even when Windows
  Terminal itself is minimised.
- Both need WSLg (Windows 11, or Windows 10 with WSL from the Microsoft Store). Without it,
  omawsl warns and nothing plays or pops up.
- No popups at all? Check Windows' Do Not Disturb / Focus, and that notifications from
  "Windows PowerShell" are allowed in Settings > System > Notifications.
- Only `[ui.sound] enabled` and `[ui.toast] delivery` in your Herdr config are changed.

## Claude Code in Herdr

- **What each agent is doing**: the sidebar (`Ctrl g b` to show or hide it) lists every
  agent; under each Claude agent sits the short task summary zellij showed in the pane frame.
- **Its symbol** says whether it needs you: **blocked** - asking a question or for
  approval, answer it; **done** - finished and you haven't looked yet; **working** - still
  running; **idle** - finished and seen. A blocked agent marks its tab and workspace blocked
  too. Every state has its own shape as well as color (`status_indicators = "symbols"`).
  `Ctrl g g`, then `b`, lists only the blocked ones.
- **Scrolling a Claude chat**: Claude Code draws its own screen, so Herdr's scroll mode
  (`Ctrl g s`) doesn't reach the chat. Use Claude's keys instead - `PgUp` / `PgDn` scroll,
  `Ctrl+End` jumps back to the latest message, and `Ctrl+o` opens the transcript: `j/k`
  line by line, `{ }` jump between your prompts, `/` search, `Esc` back. `↑` stays prompt
  history.

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
