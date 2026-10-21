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

Still getting zellij? Look in `~/.bashrc` for an `eval "$(zellij setup --generate-auto-start bash)"`
line. It starts zellij before omawsl's block runs. omawsl doesn't edit lines it didn't write,
so `omawsl multiplexer herdr` and `omawsl doctor` point at that line, and you delete it yourself.

## Same keys as zellij

omawsl's Herdr config (`configs/herdr.toml`, deployed to `~/.config/herdr/config.toml` only
if you don't already have one) ports omawsl's zellij keymap: the same `Alt` chords, and the same `Ctrl g` modes (`p` pane, `t` tab, `r` resize, `m` move),
plus Herdr-only keys like `Ctrl g g` to jump to any agent and `Ctrl g w` for workspaces. The
full list: `omawsl keys herdr`, or [`docs/keys.md`](keys.md).

Herdr itself only supports one key after its prefix, so the mode keys run through a small
popup (`bin/omawsl-herdr-mode`) that shows the mode's hints and reads your next key -
`Esc`, `Enter` or `Ctrl g` leave it, just like zellij.

## Notifications

omawsl can tell you when a Claude Code or GitHub Copilot CLI session in Herdr is **done** -
your turn - or **needs you** (a permission prompt or a question), with a sound. It asks on
first run, when you pick Herdr, and you can change it any time:

    omawsl notifications           # choose interactively
    omawsl notifications sound
    omawsl notifications off

For Claude Code, "done" means the whole session is idle: no subagent, background shell,
monitor or scheduled wakeup still running. A turn that ends with "I'll wait for the subagent"
doesn't alert you. For Copilot CLI, "done" means the main agent finished its turn. A subagent
finishing never alerts, but Copilot doesn't say whether a background shell is still running.

How it works:

- The alerts come from the agents' own hooks, not from Herdr. Herdr decides "done" by
  watching the screen, so it alerts every time Claude ends a turn to wait for background work
  (herdrdev/herdr#5004, and #1217 - background shells and monitors read as idle by design).
  omawsl therefore turns Herdr's own sound and popups off (`[ui.sound] enabled = false`,
  `[ui.toast] delivery = "off"`) for every choice.
- omawsl adds three hooks for `bin/omawsl-claude-notify` (Stop, Notification, and
  PreToolUse for AskUserQuestion) to `~/.claude/settings.json`. Your own hooks there are left
  alone; `omawsl notifications off` and uninstalling Herdr remove only omawsl's.
- For Copilot CLI, omawsl writes its own `~/.copilot/hooks/omawsl.json` (two hooks for
  `bin/omawsl-copilot-notify`: agentStop and notification), only if Copilot is installed or
  you picked it. `omawsl notifications off` and uninstalling Herdr delete that file. Your own
  hook files there are never touched.
- **Sound** installs `pulseaudio-utils` and `sound-theme-freedesktop` - the one step that
  asks for your sudo password, once per machine - and plays Ubuntu's own sounds with
  `paplay`, through WSLg. Everything happens inside Linux, nothing on the Windows side.
- **No Windows popup.** omawsl never starts Windows programs from WSL, and a popup would
  need one. To see which agent it was, look at the sidebar: its symbol shows who's done or
  blocked.

Good to know:

- **Claude Code and GitHub Copilot CLI only.** Other agents in Herdr (Codex, Antigravity)
  don't get alerts.
- Copilot not installed when you chose notifications? Run `omawsl notifications` again after
  installing it.
- You're alerted for every session, including the one you're looking at.
- Sound needs WSLg (Windows 11, or Windows 10 with WSL from the Microsoft Store).
- No sound? Some managed laptops turn WSLg off, and with it WSL's audio. Then the sidebar is
  the only signal.
- Claude Code installed but never started yet? Run `omawsl notifications` again after its
  first start - the hooks need its `~/.claude` folder.

## Claude Code in Herdr

- **What each agent is doing**: the sidebar (`Ctrl g b` to show or hide it) lists every
  agent; under each Claude agent sits your note, then the short task summary zellij showed
  in the pane frame.
- **Agent notes**: Claude names a session from its first prompt, so the summary can be
  vague. Press `Ctrl g p c` in the agent's pane to write a short note - what it's for,
  what you're waiting on. It starts from the current note so you can edit it; clear it
  and press Enter to remove it.
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
