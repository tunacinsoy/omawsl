# Windows-side setup

omawsl never installs anything on the Windows side automatically - Windows software installs
can require an IT ticket on a locked-down corporate machine, and a local JSON edit is a very
different risk profile than a network install. This doc is the one place all of that manual
setup lives; every "you'll need to do something on Windows" message elsewhere in omawsl (the
pre-install checklist, an editor's detect-and-defer message, `bin/omawsl doctor`) links back
here instead of repeating these steps.

<a id="quick-reference"></a>
## Quick reference

| If you picked... | You'll need | Steps |
|---|---|---|
| (always) Windows Terminal itself | Install it, set the WSL profile as default | [#windows-terminal](#windows-terminal) |
| (always) A readable font with icon glyphs | Pick Nerd Font (enhanced) or Cascadia Mono (zero-install) | [#fonts](#fonts) |
| Docker backend: Docker Desktop for Windows | Install Docker Desktop, enable WSL integration | [#docker-desktop](#docker-desktop) |
| Editors & AI tooling: VS Code | Install VS Code, enable the WSL extension | [#vscode](#vscode) |
| Editors & AI tooling: Cursor | Install Cursor, connect to this WSL distro once | [#cursor](#cursor) |
| Editors & AI tooling: GitHub Copilot CLI | Run `gh auth login` before `install.sh` | [#github-copilot-cli](#github-copilot-cli) |
| After running `bin/omawsl theme` | Nothing - the color sync happens automatically | [#windows-terminal-theme](#windows-terminal-theme) |

<a id="windows-terminal"></a>
## Windows Terminal

1. Install Windows Terminal from the Microsoft Store. If Store access is blocked on a
   corporate machine, ask your IT team to install it (or provide the winget/MSIX package) -
   there's no way around a genuine software-install restriction from inside WSL.
2. Open Windows Terminal's Settings (`Ctrl+,`), and under **Startup**, set **Default profile**
   to your WSL distro (usually named "Ubuntu"). This makes new tabs/windows open straight into
   WSL instead of PowerShell.

<a id="fonts"></a>
## Fonts

Two complete options - pick based on your own machine's restrictions, not a "correct" answer:

- **Nerd Font (enhanced).** Full icon-glyph rendering wherever a tool requests one - the most
  directly testable example already installed by `install.sh` is `eza --icons`, which prints a
  file-type icon before every entry. (`fastfetch`'s output does *not* depend on this - this repo
  doesn't ship a custom fastfetch config, so its default output is plain text either way.) See
  `windows/fonts/README.md` for where to download the font (not vendored in this repo - see that
  file for why) and its exact font family name. Once installed, merge
  `windows/windows-terminal.json` into your Windows Terminal `settings.json` (open Settings,
  click "Open JSON file", merge the `profiles.defaults` and `actions` keys from that file into
  your own - don't just paste over the whole file).
- **Cascadia Mono (zero install).** Nothing to install - Cascadia Mono ships bundled with
  Windows Terminal already. Merge `windows/windows-terminal-fallback.json` instead, the same
  way. Icon glyphs (e.g. from `eza --icons`) render as boxes/tofu instead of icons; everything
  else (text, colors, layout) is fully readable and functional. This trade-off is real, not a
  bug to report.

`install.sh` also asks which of these two you set up, so the shell prompt itself (not just
`eza`) matches: picking Cascadia Mono there falls back to a plain `user@host:path` prompt
instead of Omakub's single-glyph one, which would otherwise render as a tofu box without a
matching Nerd Font.

**Both files also fix a real keybinding collision, not just the font.** Omakub's zellij
keybindings (`configs/zellij.kdl`) bind `Alt+Left/Down/Up/Right` for pane focus - the same four
chords Windows Terminal binds by default for moving focus between *its own* split panes. Since
Windows Terminal owns the keystroke first, it swallows these four chords before zellij (running
inside it) ever sees them. Both JSON files unbind Windows Terminal's default so the keystroke
passes through to zellij - confirmed working on a real Windows Terminal + zellij session (every
other zellij binding was checked too and has no collision). This is independent of which font
option you pick, so it's included in both files identically.

<a id="docker-desktop"></a>
## Docker Desktop

Only needed if you chose "Docker Desktop for Windows" at the first-run picker instead of the
default Engine-only option.

1. Install Docker Desktop from https://www.docker.com/products/docker-desktop/ (Store access
   isn't required for this one - it's a direct installer). On a corporate machine, check
   whether your org already has a license before installing; Docker Desktop's free tier has
   company-size limits that Engine-only (the default) doesn't.
2. In Docker Desktop's Settings → Resources → WSL Integration, enable integration for this
   distro specifically.
3. Back in your WSL terminal, confirm it worked: `docker ps` should return an (possibly empty)
   table, not a "command not found" or connection error.

<a id="vscode"></a>
## VS Code

1. Install VS Code from https://code.visualstudio.com/ (Store, or the direct installer - both
   work; ask IT if Windows software installs are locked down).
2. Install the "WSL" extension (`ms-vscode-remote.remote-wsl`) from the Extensions view, or let
   `install.sh` install it for you automatically once `code` is reachable.
3. Open a folder from inside WSL with `code .` to connect for the first time, or use the
   Remote-WSL "Connect to WSL" command from VS Code's command palette on Windows.
4. Verify: `code --version` from your WSL terminal should print a version, not
   "command not found".

If you run `install.sh` before doing this, nothing fails - the shared settings file still
deploys (it's inert until VS Code connects), and only the one step needing the live `code` CLI
is skipped, with a reminder to come back to it.

<a id="cursor"></a>
## Cursor

1. Install Cursor from https://cursor.com/ on Windows.
2. Connect it to this WSL distro once, the same way you'd connect VS Code (Cursor is a VS Code
   fork and uses the same Remote-WSL-style connection flow).
3. Verify: `cursor --version` from your WSL terminal should print a version.

Cursor shares the same baseline `configs/vscode.json` settings VS Code gets - deployed
automatically regardless of whether `cursor` is reachable yet. Unlike VS Code, omawsl doesn't
attempt an extension install for Cursor: Cursor has its own extension distribution, and
Microsoft's marketplace commonly blocks non-VS-Code products from installing
Microsoft-published extensions, so this repo only deploys what's clearly specified.

<a id="github-copilot-cli"></a>
## GitHub Copilot CLI

Installing GitHub Copilot CLI runs `gh extension install github/gh-copilot`, which needs an
authenticated `gh` session - something a fresh machine doesn't have yet. If you're going to
pick "GitHub Copilot CLI" in the Editors & AI tooling picker, run this **before** `install.sh`:

```bash
gh auth login
```

If you skip this and pick it anyway, nothing else in `install.sh` is affected - the failure is
isolated and reported, not fatal to the rest of the run - but the extension itself won't
install until you run `gh auth login` yourself and then either
`gh extension install github/gh-copilot` or re-run `install.sh`.

<a id="windows-terminal-theme"></a>
## Windows Terminal theme

Unlike everything else on this page, this one **is** automatic: `bin/omawsl theme <name>`
edits your real Windows Terminal `settings.json` directly (the one exception to "omawsl never
touches Windows-side files automatically" - it's a local JSON edit to an already-installed app,
no network call, no admin rights). It always backs up `settings.json` first
(`settings.json.bak`) and skips gracefully - printing this same pointer instead of failing -
if `jq` isn't available or `settings.json` can't be found or parsed. Nothing to do here by
hand unless that skip message shows up, in which case merge the theme's
`themes/<name>/windows-terminal-scheme.json` into your `schemes` array yourself and set it as
`profiles.defaults.colorScheme`.

## Clipboard and GUI apps

No setup needed here - WSL2 + WSLg handle clipboard sharing and Linux GUI app interop with
Windows automatically on Windows 11.
