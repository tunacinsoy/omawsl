# omawsl

A single-script installer that turns a fresh WSL2 Ubuntu install into a fully configured
development environment - the same "one script, done" experience
[Omakub](https://github.com/basecamp/omakub) provides for bare-metal Ubuntu, adapted for
WSL2 on Windows 11.

```bash
curl -fsSL https://raw.githubusercontent.com/tunacinsoy/omawsl/master/boot.sh | bash
```

## Before you begin

`install/windows-prereq-checklist.sh` (part of the installer itself) only reacts *after*
you've already reached a fresh WSL bash prompt and made your picker choices. This section is
what gets you there in the first place - and optionally a little further.

1. **Get to time 0.** If you don't already have WSL2 + Ubuntu installed, open PowerShell as
   Administrator and run:

   ```powershell
   wsl --install -d Ubuntu
   ```

   If that fails or behaves oddly (BIOS virtualization disabled, an old Windows build, etc.),
   Microsoft's own WSL install docs are the authoritative troubleshooting source -
   https://learn.microsoft.com/windows/wsl/install - that's a moving target across Windows
   versions omawsl doesn't try to maintain a parallel copy of.

2. **Optional: prep the Windows side first.** If you already know you'll want VS Code, Cursor,
   or Docker Desktop, installing them *now* means `install.sh`'s pre-install checklist will
   have nothing to flag when you get there. See the quick-reference table at the top of
   [`docs/windows-setup.md`](docs/windows-setup.md#quick-reference) for exactly what each
   picker option needs on the Windows side and the numbered steps for each - the same table
   `install.sh` itself points you to if you skip this and hit it reactively instead.

3. **Run it.** The one-liner at the top of this README. Everything from here is interactive
   (`gum` prompts) and unattended after that.

## What you get

Fully automated on the WSL/Linux side: shell and terminal tooling (zellij, btop, fastfetch,
lazygit, lazydocker, `gh`), Docker (native Engine by default, or Docker Desktop detect-and-defer
if you opt in), your choice of language runtimes and cloud CLIs via `mise` (Ruby on Rails,
Node.js, Go, PHP, Python, Elixir, Rust, Java, Terraform, Azure CLI), containerized storage
(MySQL, Redis, PostgreSQL), and your choice of editors/AI tooling (VS Code, Neovim, opencode,
Cursor, Claude Code CLI, Codex CLI, GitHub Copilot CLI, Gemini CLI). Nothing in any picker is
pre-selected - what you get is exactly what you choose, every time.

Ten ported Omakub themes are available via `bin/omawsl theme <name>`, applied consistently
across zellij, btop, Neovim, VS Code/Cursor, opencode (where it has a matching built-in
preset), and - the one exception to "never auto-touch Windows-side files" - Windows Terminal's
own color scheme, synced automatically.

See [`docs/updating.md`](docs/updating.md) for how to keep everything current - omawsl itself, language runtimes, system packages, and the handful of tools with no native updater of their own.

Documented but never automated: Windows Terminal itself, its font, and the zellij keybinding
fix - see [`docs/windows-setup.md`](docs/windows-setup.md).

## What omawsl deliberately excludes

Not every gap here is an oversight - some are deliberate:

- **37signals commercial products** (HEY, Basecamp) - out of scope for a general dev-environment
  installer.
- **The Windows desktop-app layer** (Spotify, Signal, and Linux-desktop-only concepts like
  GNOME, Tactile, Ulauncher) - WSL has no desktop environment of its own, so there's nothing
  for these to run in.
- **Any automatic Windows-side software installation** (winget, PowerShell package installs)
  triggered by the WSL installer - some target machines sit behind a corporate firewall where
  installing Windows software requires an IT ticket; omawsl never assumes that's not the case.
  See [`docs/windows-setup.md`](docs/windows-setup.md) for the manual (or optionally
  `windows/setup.ps1`-assisted) alternative.
- **Typora** - not a 37signals product, but dropped deliberately: there are many alternative
  markdown editors, and it's not central enough to this tool's scope to carry.
- **X11 compose-key mappings** (`xcompose`) - a desktop/X11 input-method feature; Windows owns
  keyboard input for a WSL session, so there's no WSL-side equivalent to configure.

## Status

omawsl's full CLI is now shipped: `bin/omawsl theme`, `update`, `migrate`,
`install`, `uninstall`, and `doctor`. Run `bin/omawsl` with no arguments for
the full command list.
