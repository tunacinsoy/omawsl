# omawsl — Design Spec

Date: 2026-07-05
Status: Approved for planning

## 1. Purpose

omawsl is a single-script installer that turns a fresh WSL2 Ubuntu install into a fully
configured development environment, providing the same experience that
[Omakub](https://github.com/basecamp/omakub) provides for bare-metal Ubuntu. It exists to give
a seamless transition path from an existing native-Ubuntu Omakub setup to WSL2 on Windows 11,
without hand-reassembling dotfiles and tools.

Reference architecture: verified against the actual `basecamp/omakub` repository
(`install.sh`, `boot.sh`, `install/terminal/*.sh`, `configs/`, `migrations/`) as of this writing.
Unless a decision below explicitly diverges from it, omawsl mirrors Omakub's proven structure
and conventions.

## 2. Scope

**In scope:**
- Fully automated WSL/Linux-side setup: shell, terminal tools, editors, language runtimes,
  cloud CLIs, containerized databases.
- Documented (not automated) Windows-side setup: Windows Terminal profile/theme, font,
  optional winget helper script.
- Idempotent re-runs and forward compatibility with Ubuntu releases after 24.04.

**Out of scope (explicitly excluded):**
- 37signals commercial products (HEY, Basecamp).
- The Windows desktop-app layer: Spotify, Signal, and Linux-desktop-only concepts that don't
  apply to WSL (GNOME, Tactile, Ulauncher). WSL has no desktop environment of its own, so unlike
  Omakub there is no `desktop.sh` at all — not disabled, simply absent.
- Any automatic Windows-side software installation (winget, PowerShell package installs)
  triggered by the WSL installer. See §7.
- Typora. Not a 37signals product and not named in the original exclusion list, but deliberately
  dropped: there are many alternative markdown editors, and the user's own workflow keeps
  markdown in a private repo rather than a dedicated third-party app.
- `defaults/xcompose` — X11 compose-key mappings for typing special characters via key
  sequences. This is a desktop/X11 input-method feature; Windows owns keyboard input for a WSL
  session, so there is no WSL-side equivalent to configure.
- `applications/` (Omakub's `About.sh`, `Activity.sh`, `Basecamp.sh`, `Docker.sh`, `HEY.sh`,
  `Neovim.sh`, `Omakub.sh`, `WhatsApp.sh` + `icons/`) — these generate GNOME dock/app-launcher
  shortcuts. Out of scope entirely under the no-desktop-layer exclusion above (and the
  Basecamp/HEY ones doubly so, under the 37signals exclusion).
- Omakub's broader post-install editor catalog (Doom Emacs, RubyMine, Windsurf, Zed, reachable
  via its `install-dev-editor.sh` menu) — omawsl's editor scope is deliberately the four named
  (VS Code, Neovim, opencode, Cursor), not an open catalog.

**Exhaustiveness check — every top-level concern in upstream Omakub, and its omawsl
disposition:**

| Omakub concern | omawsl disposition |
|---|---|
| `boot.sh`, `install.sh`, `install/check-version.sh` | Ported (rebranded banner, floor-only version check) |
| `install/desktop.sh` | Dropped — no desktop layer on WSL |
| `install/identification.sh` | Ported (§6) |
| `install/first-run-choices.sh` | Ported and extended (§6) |
| `install/terminal.sh` + `install/terminal/*.sh` | Ported, extended with `cloud-tools.sh`, `app-vscode.sh`, `app-opencode.sh`, `app-cursor.sh`, `app-claude-cli.sh`, `app-codex-cli.sh`, `app-gemini-cli.sh`, `app-gh-copilot.sh` |
| `configs/` (bashrc, inputrc, zellij.kdl, btop.conf, fastfetch.jsonc, vscode.json, neovim/) | Ported |
| `configs/alacritty*` | Dropped — Windows Terminal replaces Alacritty |
| `configs/typora/`, `configs/ulauncher.*` | Dropped — see exclusions above |
| `configs/xcompose`, `defaults/xcompose` | Dropped — X11 input-method feature, N/A on WSL |
| `defaults/bash` | Folded into `configs/bashrc` — no separate artifact needed |
| `applications/` | Dropped entirely — GNOME dock/launcher integration, see exclusions above |
| `themes/` | Ported, all 10 themes (§11) |
| `migrations/` | Ported (§8) |
| `uninstall/` | Ported, scoped to what omawsl actually installs (§14) |
| `bin/omakub` + `bin/omakub-sub/*` (menu, theme, migrate, update, install-dev-editor, font, manual, header, uninstall) | Ported as `bin/omawsl` subcommands: `theme`, `migrate`, `update`, `doctor`, `uninstall` (§14). No interactive full-screen menu shell (`menu.sh`) — omawsl favors direct subcommands over a persistent TUI menu, since the whole install is meant to be a single unattended run rather than an ongoing control-panel experience. `font.sh`/`manual.sh` have no WSL-side equivalent (font install is a Windows-side doc step, §13; `README.md` covers what `manual.sh` would show). |

No Omakub concern is unaccounted for: everything is either ported (possibly adapted), or
explicitly excluded with a stated reason above.

## 3. Target environment & assumptions

- Fresh WSL2 Ubuntu install (26.04 baseline, but the version guard is floor-only — see §8 — so
  later releases pass automatically).
- User already has a username/password set and is looking at a bash prompt at time 0.
- Only bash + coreutils are guaranteed present; `git`/`curl` may not be installed yet.
- Some target machines sit behind a corporate firewall where installing software on the Windows
  host requires an IT ticket; others are personal machines with no such restriction. This drives
  §6 and §7.

## 4. Bootstrap

```
curl -fsSL https://raw.githubusercontent.com/tunacinsoy/omawsl/master/boot.sh | bash
```

`boot.sh` (mirrors Omakub's `boot.sh`):
1. Banner + confirmation prompt. The banner is an **omawsl-branded ASCII art logo**, not
   Omakub's — this is purely cosmetic but deliberate: it's the first thing a user sees, and it
   should read as omawsl's own tool, not a reskinned fork. The same banner is reused by
   `bin/omawsl` (via a shared `header.sh`-equivalent) so the identity is consistent across the
   initial install and later CLI use.
2. `sudo apt-get update` and install `git` if missing.
3. Clone `https://github.com/tunacinsoy/omawsl` into `~/.local/share/omawsl` — **but first check
   whether that directory already exists** (e.g. a prior run was interrupted, or the user is
   re-bootstrapping). If it does, `git -C ~/.local/share/omawsl pull` instead of cloning fresh;
   a plain re-clone into a non-empty directory would fail outright.
4. Support an `OMAWSL_REF` env var to check out a specific branch/tag instead of `master`
   (for testing changes before merge).
5. Exec `install.sh` from the clone.

## 5. Orchestration flow

`install.sh` runs, in order:

1. **`install/check-version.sh`** — verifies Ubuntu (floor-only version check, see §8),
   x86_64/arm64 architecture, and that we are actually inside **WSL2 specifically** (not WSL1 —
   see §8's WSL-generation check). Hard-fails with a clear message otherwise.
2. **`install/terminal/required/app-gum.sh`** — bootstraps `gum` itself. This must run *before*
   `first-run-choices.sh`, since every prompt in that script depends on `gum choose`/`gum
   confirm` already being available. (An earlier draft of this spec nested this step inside
   `install/terminal.sh`, which runs *after* `first-run-choices.sh` — that ordering would have
   made every first-run prompt fail on a fresh machine where `gum` isn't preinstalled. Fixed
   here: `app-gum.sh` is invoked directly by `install.sh` ahead of the prompts, in addition to
   still being idempotently sourced again as part of `install/terminal.sh`'s normal pass.)
3. **`install/first-run-choices.sh`** — every interactive prompt happens here, up front, via
   `gum`. Results are exported as `OMAWSL_*` env vars so the remainder of the run is
   unattended. See §6.
4. **`install/terminal.sh`** — sources every script under `install/terminal/*.sh` in a fixed
   order. Each script is idempotent and consults the `OMAWSL_*` flags where relevant.
5. On successful completion, write `~/.local/state/omawsl/version` with the repo's current
   `version` timestamp (see §8) — this is what keeps a fresh install from later thinking every
   historical migration is still pending.
6. Final summary, printed with a pointer to `docs/windows-setup.md` for the manual
   Windows-side steps.

## 6. First-run choices

All prompts live in `install/first-run-choices.sh`, mirroring Omakub's
`OMAKUB_FIRST_RUN_*` convention with an `OMAWSL_` prefix:

| Prompt | Type | Options | Default | Env var |
|---|---|---|---|---|
| Connectivity | single-select | "Corporate / restricted network", "Personal / unrestricted" | none | `OMAWSL_NETWORK_MODE` |
| Editors & AI tooling | multi-select | VS Code, Neovim, opencode, Cursor, Claude Code CLI, Codex CLI, GitHub Copilot CLI, Gemini CLI | none selected | `OMAWSL_EDITORS` |
| Languages & cloud tools | multi-select | Ruby on Rails, Node.js, Go, PHP, Python, Elixir, Rust, Java, Terraform, Azure CLI | none selected | `OMAWSL_LANGUAGES` |
| Storage | multi-select | MySQL, Redis, PostgreSQL | none selected | `OMAWSL_STORAGE` |

**`OMAWSL_NETWORK_MODE` — reserved flag, no consumer yet.** This is intentional, not dead
code: it is captured now because future omawsl versions are expected to need it (e.g. gating a
raw `curl | bash` binary install behind a "corporate networks may block this" fallback path).
It is asked at first run and stored so that behavior can become network-mode-aware later
without a breaking change to the prompt flow. As of this version, no install step branches on
it.

Selecting nothing in any of the three multi-selects is a valid, expected state, not an error —
`select-dev-language.sh`, `select-dev-storage.sh`, and every `app-*.sh` editor/tool script must
no-op cleanly (skip their body, no partial writes) when their corresponding `OMAWSL_*` var is
empty, rather than assuming at least one option was picked.

Downstream scripts do simple membership checks against these vars, e.g.:

```bash
[[ "$OMAWSL_LANGUAGES" == *"Rust"* ]] && mise use --global rust@latest
```

The one prompt outside this file is `install/identification.sh` (matching Omakub's real
filename and behavior — not a conditional `set-git.sh` as an earlier draft of this spec had
it): it always prompts for full name and email at first run, pre-filled from `getent passwd`
and any existing `git config` as defaults, exported as `OMAWSL_USER_NAME`/`OMAWSL_USER_EMAIL`
and used to set `git config --global user.name`/`user.email`.

## 7. Directory structure

```
omawsl/
├── boot.sh
├── install.sh
├── version
├── install/
│   ├── check-version.sh
│   ├── first-run-choices.sh
│   ├── terminal.sh
│   └── terminal/
│       ├── required/
│       │   └── app-gum.sh
│       ├── identification.sh
│       ├── a-shell.sh
│       ├── apps-terminal.sh
│       ├── app-btop.sh
│       ├── app-fastfetch.sh
│       ├── app-lazygit.sh
│       ├── app-lazydocker.sh
│       ├── app-github-cli.sh
│       ├── app-zellij.sh
│       ├── app-vscode.sh
│       ├── app-neovim.sh
│       ├── app-opencode.sh
│       ├── app-cursor.sh
│       ├── app-claude-cli.sh
│       ├── app-codex-cli.sh
│       ├── app-gemini-cli.sh
│       ├── app-gh-copilot.sh
│       ├── mise.sh
│       ├── select-dev-language.sh
│       ├── cloud-tools.sh
│       ├── select-dev-storage.sh
│       ├── docker.sh
│       └── libraries.sh
├── configs/
│   ├── bashrc
│   ├── inputrc
│   ├── zellij.kdl
│   ├── btop.conf
│   ├── fastfetch.jsonc
│   └── vscode.json
├── windows/
│   ├── windows-terminal.json
│   ├── fonts/
│   └── setup.ps1
├── themes/
│   ├── catppuccin/ … tokyo-night/   # 10 themes, ported from Omakub
│   │   ├── windows-terminal-scheme.json   # replaces Omakub's alacritty.toml
│   │   ├── neovim.lua
│   │   ├── zellij.kdl
│   │   ├── btop.theme
│   │   └── vscode.sh                       # also targets Cursor's settings.json if installed
│   └── set-vscode-theme.sh                 # shared helper, ported from Omakub
├── migrations/
├── uninstall/
│   ├── dev-language.sh   # removes one mise-managed language/tool by name
│   ├── storage.sh        # removes a storage container by name
│   ├── docker.sh         # removes docker-ce + containers/images/volumes it created
│   ├── app-vscode.sh
│   ├── app-neovim.sh
│   ├── app-opencode.sh
│   ├── app-cursor.sh
│   ├── app-claude-cli.sh
│   ├── app-codex-cli.sh
│   ├── app-gemini-cli.sh
│   └── app-gh-copilot.sh
├── bin/
│   └── omawsl
└── docs/
    ├── windows-setup.md
    └── superpowers/specs/
```

Notes:
- No `configs/alacritty` — Windows Terminal is the terminal emulator on this stack, so an
  Alacritty config has no consumer.
- `windows/` is documentation and optional assets only. Nothing under it is ever invoked by
  `install.sh`.
- Each `install/terminal/*.sh` is self-contained and idempotent: `apt install` no-ops on
  already-installed packages, `cp` deterministically overwrites configs, `mise use` re-pins
  versions harmlessly, and container creation is guarded by a name-existence check.

## 8. Idempotency, versioning, migrations

- **Idempotent by construction:** every install step uses primitives that are safe to
  re-run (see §7 notes). `set -e` is set in every script; no step is written such that an
  expected no-op counts as a failure.
- **Version guard is floor-only:** `check-version.sh` checks `VERSION_ID >= 24.04` with no
  ceiling, so later Ubuntu releases (26.04, 28.04, ...) pass without a code change. This is
  what satisfies the "compatible with later Ubuntu versions" requirement. Unlike Omakub's actual
  implementation (which shells out to `bc` for the floating-point comparison), this check is
  done in pure bash/POSIX arithmetic on the major/minor parts — `bc` is not guaranteed present
  on a minimal fresh image, and this is the very first gate in the whole run, before anything
  has been `apt install`ed yet. Depending on an uninstalled tool to decide whether to start
  installing tools is a chicken-and-egg risk not worth taking.
- **WSL-generation guard:** in addition to confirming we're inside WSL at all, `check-version.sh`
  specifically distinguishes WSL2 from WSL1 (e.g. via kernel version / `/proc/version`) and
  hard-fails with an "upgrade to WSL2" message on WSL1. A WSL1 instance could otherwise pass a
  looser "are we in WSL" check but has no systemd support and a fundamentally different
  networking model — the Docker approach in §9 assumes WSL2 throughout.
- **Migrations for omawsl's own breaking changes:** a `version` file at repo root holds a
  timestamp identifying the current omawsl version, matching Omakub's convention.
  `migrations/<timestamp>.sh` scripts hold one-off fixes for changes introduced by omawsl
  itself between releases (e.g. a config file that moved, a renamed mise tool). `bin/omawsl`
  compares the user's last-applied migration timestamp (stored under
  `~/.local/state/omawsl/version`) against `migrations/`, and runs only the ones newer than
  that. `install.sh` writes this state file itself on successful completion (§5, step 5) — a
  fresh install already reflects current desired state, so without this the first-ever
  `bin/omawsl migrate` would otherwise treat every historical migration as still pending.
- Re-running the installer is always safe: either re-run `install.sh` top to bottom (idempotent
  by construction), or run `bin/omawsl migrate` for just the pending migrations.
- **Error handling:** `install/terminal/*.sh` scripts are sourced (not sub-shelled) by
  `install/terminal.sh`, so a failure stops the whole run immediately rather than continuing
  with a partially-configured system. On failure, the script name and a "fix the issue and
  re-run install.sh" message are printed — no automatic rollback, matching Omakub's own
  fix-and-re-run philosophy rather than a transactional model.

## 9. Docker

Docker Engine is installed **natively inside WSL, unconditionally** — this is not gated by
`OMAWSL_NETWORK_MODE`. Rationale: `docker-ce` via `apt` is Apache-2.0 licensed and free
regardless of company size, sidestepping Docker Desktop's paid-subscription threshold for
larger companies entirely — not just the "IT ticket to install Windows software" concern.
Functionally, WSL2's automatic localhost port-forwarding means containers are reachable from
the Windows side exactly as they would be under Docker Desktop, so there's no seamlessness
gap for typical dev workloads (`docker compose up`, exposed ports, volumes).

`docker.sh` behavior:

```bash
# 1. Ensure WSL systemd support is on (idempotent: no-op if already set)
if ! grep -q "^systemd=true" /etc/wsl.conf 2>/dev/null; then
  printf '[boot]\nsystemd=true\n' | sudo tee -a /etc/wsl.conf >/dev/null
  NEEDS_RESTART=1
fi

# 2. Install docker-ce via apt (idempotent)
# ... standard Docker apt repo + install steps ...
sudo usermod -aG docker "$USER"
# Group membership changes don't apply to the *current* shell session — tell the user now,
# so `docker ps` failing with a permission error right after install doesn't look like a bug:
gum style --foreground 3 "Open a new terminal (or run 'newgrp docker') before using Docker without sudo."

# 3. A script running inside the live WSL instance cannot restart the WSL VM itself.
#    If systemd support was just enabled, stop here with clear instructions;
#    re-running install.sh afterward picks up cleanly since step 1 becomes a no-op.
if [[ "$NEEDS_RESTART" == "1" ]]; then
  gum style --foreground 3 "WSL systemd support was just enabled. Run 'wsl --shutdown' from Windows (PowerShell/cmd), reopen this terminal, then re-run install.sh to finish Docker setup."
  exit 0
fi
```

Note: because `install/terminal/*.sh` scripts are *sourced* by `install/terminal.sh` (§8), this
`exit 0` deliberately terminates the entire `install.sh` run, not just `docker.sh` — that is
intentional here, not an oversight: the remaining steps have no useful work to do until after
the WSL VM restart, and the user's shell session is about to be torn down by `wsl --shutdown`
anyway. Re-running `install.sh` afterward resumes cleanly since step 1 becomes a no-op and
every later step is idempotent regardless of whether it previously ran.

Docker Desktop is not offered as an interactive choice. `docs/windows-setup.md` carries a
one-line note that Docker Desktop + WSL integration is a fine alternative *if the user's
organization already provides a license for it*, but it is not part of the automated flow.

A corporate proxy/TLS-inspecting firewall that blocks package mirrors or container registries
would affect this path the same way it would affect Docker Desktop — that risk is orthogonal
to the native-vs-Desktop choice and is not specifically mitigated by this design.

## 10. Editor tooling

All eight are optional, selected via `OMAWSL_EDITORS` — no default is forced on the user,
including VS Code, to stay neutral and let the picker reflect actual intent rather than an
assumed default:

- `app-vscode.sh` — checks for the `code` CLI via Win32 interop. **If VS Code isn't installed
  on the Windows side yet** (a real, expected case — omawsl never auto-installs Windows
  software, see §2), this is not a failure: the script still drops `.vscode/extensions.json`
  and `configs/vscode.json` (inert until VS Code exists, and pick up automatically once it
  does), skips the one step that needs the live `code` binary (installing the Remote-WSL
  extension via `code --install-extension`), prints a message pointing at
  `docs/windows-setup.md`, and lets the rest of the install continue. The same detect-and-defer
  shape already used for Docker Desktop (§9) and the Windows Terminal theme sync (§11).
- `app-neovim.sh` — Neovim + a LazyVim-based config, matching Omakub's actual approach. Purely
  WSL-side, no Windows dependency, always installable regardless of what's on the Windows side.
- `app-opencode.sh` — the opencode.ai terminal AI coding agent CLI. Purely WSL-side.
- `app-cursor.sh` — Cursor is a Windows-side GUI app (a VS Code fork). Same detect-and-defer
  treatment as `app-vscode.sh`: check for its CLI/interop, configure what can be configured
  (shared settings.json keys, per §11) if present, otherwise skip gracefully with a
  `docs/windows-setup.md` pointer.
- `app-claude-cli.sh`, `app-codex-cli.sh`, `app-gemini-cli.sh` — Claude Code CLI, OpenAI Codex
  CLI, Gemini CLI. Purely WSL-side terminal tools. Each installs via its own official standalone
  installer where one exists; where the only distribution channel is npm, the script uses a
  private `mise`-managed Node runtime internally to install it, rather than depending on
  whether the user separately picked Node.js in the language picker (§12) — that picker is
  about the user's own project runtime, not an implementation detail of an unrelated tool.
- `app-gh-copilot.sh` — GitHub Copilot CLI, installed as a `gh` extension
  (`gh extension install github/gh-copilot`). Depends only on `gh` itself, which
  `app-github-cli.sh` already installs unconditionally regardless of any picker, so there's no
  cross-picker dependency gap here. Actual usability still depends on the user having an
  authenticated `gh` session and an active Copilot subscription — that's a runtime concern
  documented in the README, not an install-time failure.

Each of these scripts is skipped entirely if its editor/tool wasn't selected — no partial setup,
no extension/config writes for tools the user didn't ask for.

## 11. Theming

Omakub ships 10 built-in themes (catppuccin, everforest, gruvbox, kanagawa, matte-black, nord,
osaka-jade, ristretto, rose-pine, tokyo-night) as `themes/<name>/` folders, each holding
per-tool files (`alacritty.toml`, `neovim.lua`, `zellij.kdl`, `btop.theme`, `vscode.sh`, plus
GNOME-only files we drop: `gnome.sh`, `tophat.sh`, `background.jpg`). A `bin/omakub theme`
command lets the user pick one via `gum choose`, then copies/patches each tool's config to
match. There's no daemon or reload signal — each tool just picks up its config file on next
launch. This mechanism is directly portable to WSL, verified against the actual upstream
scripts (`bin/omakub-sub/theme.sh`, `themes/set-vscode-theme.sh`).

omawsl ports all 10 themes as `themes/<name>/` folders, with one substitution and one addition:

- **Alacritty → Windows Terminal.** Instead of `alacritty.toml`, each theme folder carries a
  `windows-terminal-scheme.json` fragment (a `schemes` entry in Windows Terminal's own format).
  Community exports of these color schemes already exist for all 10 theme names and will be
  sourced/adapted rather than hand-derived from the Alacritty TOML.
- **VS Code theme step also covers Cursor**, since Cursor reads the same `workbench.colorTheme`
  settings key and supports most VS Code extensions — `vscode.sh` becomes a shared step
  parameterized by target settings.json path (VS Code's and/or Cursor's, whichever is
  installed).
- `neovim.lua`, `zellij.kdl`, `btop.theme` are ported as-is (or lightly adapted) from upstream.
- `opencode` theming is best-effort: if opencode.ai's CLI exposes a theme/color setting at
  implementation time, it's wired in the same way; if not, it's skipped rather than forcing a
  workaround, since it has no direct Omakub precedent to port.

`bin/omawsl theme <name>` applies the theme across every installed component:

```bash
# WSL-side (same pattern as Omakub, for whichever tools were actually installed):
cp themes/$NAME/zellij.kdl        ~/.config/zellij/themes/$NAME.kdl   # + sed-patch active theme ref
cp themes/$NAME/btop.theme        ~/.config/btop/themes/$NAME.theme   # + sed-patch btop.conf
cp themes/$NAME/neovim.lua        ~/.config/nvim/lua/plugins/theme.lua   # only if neovim installed
source themes/$NAME/vscode.sh     # code --install-extension + sed-patch settings.json, per installed target (VS Code / Cursor)

# Windows-side (new for omawsl):
# Merge themes/$NAME/windows-terminal-scheme.json into Windows Terminal's settings.json
# via the /mnt/c mount, and set it as the active profile's colorScheme.
# This is a pure local JSON edit — no download, no install, no admin rights — so it's
# automated even in corporate/restricted mode. If the settings.json path can't be found or
# isn't writable (e.g. Windows Terminal not yet installed), skip with a message pointing to
# docs/windows-setup.md rather than failing the whole command.
```

Two implementation risks worth calling out explicitly, since this step touches a file the user
depends on for their whole terminal experience:

- **Don't assume the Windows username matches `$USER`.** The settings.json path is
  `/mnt/c/Users/<Windows username>/...`, and it's common for the WSL Linux username and the
  Windows account name to differ. The Windows profile path must be resolved dynamically (e.g.
  via `cmd.exe /c echo %USERPROFILE%` or `wslpath`), never assembled by assuming the two
  usernames match.
- **Prefer `jq` over `sed` for this specific edit, and always back up first.** Omakub's own
  `vscode.sh` uses a blind `sed` substitution, which is fine for a single-line
  `"workbench.colorTheme": "..."` key — but Windows Terminal's `schemes` array is a nested
  JSON structure where a naive `sed` is much more likely to corrupt the file. Use `jq` if
  available (fall back to the documented manual step if not, rather than risking a `sed`
  edit on a structure it's not suited for), and copy `settings.json` to `settings.json.bak`
  before writing, since a corrupted settings.json breaks the user's whole terminal, not just
  the theme.

Because bat/eza/ripgrep/git-diff colors follow the terminal's own ANSI palette rather than
having separate per-tool theme files, syncing the Windows Terminal color scheme is what makes
those feel themed too — matching how Alacritty's palette does the same job in upstream Omakub.

## 12. Languages, cloud tools, storage

- **Languages/tools** (`select-dev-language.sh` + `cloud-tools.sh`), all via `mise` where
  supported: Ruby on Rails, Node.js, Go, PHP, Python, Elixir, Rust, Java (Omakub's full list,
  unchanged) plus Terraform and Azure CLI (new for omawsl). Nothing is pre-selected by
  default — a public tool should not surprise-install anything the user didn't explicitly ask
  for.
- **Terraform and Azure CLI each require adding their own third-party apt repository and GPG
  key** (HashiCorp's and Microsoft's respectively) — separate from Ubuntu's own mirrors, and
  reachable/blockable independently of them. Because every script in this flow runs under
  `set -e`, a single unreachable third-party repo here could otherwise cascade into failing
  every *later* `apt install` step in the run, not just this one tool. `cloud-tools.sh` must
  isolate these repo-add + `apt-get update` failures (e.g. check the exit code explicitly,
  report just that tool as failed, and continue) rather than letting one blocked mirror take
  down unrelated steps like Docker or the terminal app installs that run afterward.
- **Storage** (`select-dev-storage.sh`): MySQL, Redis, PostgreSQL as Docker containers. Unlike
  Omakub (which pre-selects MySQL+Redis), nothing is pre-selected here — to stay maximally
  generic and not bias the picker toward any one storage solution.

## 13. Windows-side deliverables (manual, except theme sync)

- `docs/windows-setup.md` — step-by-step walkthrough: install Windows Terminal (Store, or "ask
  IT" note if blocked), install a Nerd Font from `windows/fonts/` (no admin rights needed),
  merge `windows/windows-terminal.json` into Windows Terminal's `settings.json`, set the WSL
  profile as default. Includes the Docker Desktop alternative note from §9 and the Cursor note
  from §10.
- `windows/setup.ps1` — optional, reviewed-before-run helper for winget installs, for
  personal/unrestricted machines where the user wants one command instead of following the doc
  by hand. Never invoked automatically by `install.sh` or `boot.sh`.
- No clipboard/X-server setup is needed: WSL2 + WSLg handle clipboard and GUI app interop
  automatically on Windows 11. The doc notes this works out of the box.
- There is no ordering dependency between the Windows-side doc and the WSL installer — they
  are independent tracks. The one exception: if a user manually opts into the Docker Desktop
  alternative, they need to complete that Windows-side install themselves before `docker`
  becomes available via interop; this is a documented manual choice, not something omawsl
  detects or blocks on.
- **Exception:** `bin/omawsl theme <name>` (§11) *does* automatically edit Windows Terminal's
  settings.json across the `/mnt/c` mount. This is treated as categorically different from the
  "no automatic Windows-side installs" rule — it's a local JSON edit to an already-installed
  app, no network call, no admin rights — and it skips gracefully (falling back to the
  documented manual step) if the file can't be found or written.

## 14. Post-install CLI (`bin/omawsl`)

- `bin/omawsl update` — **self-update**: `git pull` inside `~/.local/share/omawsl`, then runs
  pending `migrations/*.sh` automatically. This is a deliberate improvement over upstream: in
  real Omakub, "Update > omakub" only runs `migrate.sh` — the `git pull` itself is never
  automated anywhere in its own tooling and is left as an implicit manual step. Combining pull +
  migrate into one omawsl command removes that gap. If the clone has local modifications (e.g.
  someone hand-edited a config file directly inside `~/.local/share/omawsl` instead of through
  a proper mechanism), `git pull` would conflict — detect a dirty working tree first and warn
  with guidance rather than letting `git pull` fail confusingly or silently discard those edits.
- `bin/omawsl migrate` — runs pending migrations only, without pulling (e.g. if the repo was
  already updated manually, or for testing a specific migration in isolation).
- `bin/omawsl theme <name>` — applies one of the 10 ported themes across every installed
  component; see §11. Validates `<name>` against the known `themes/` subdirectories and errors
  clearly on a typo/unknown name rather than silently no-op'ing.
- `bin/omawsl uninstall <name>` — removes one installed component (a language/tool, a storage
  container, Docker itself, or an optional editor) via the matching `uninstall/*.sh` script.
  Scoped to exactly what omawsl can install (§7's `uninstall/` tree) — not a general
  system-wide uninstaller. Uninstalling something that was never installed is a no-op with an
  informational message, not an error.
- `bin/omawsl doctor` (or `status`) — reports what's installed/configured; doubles as a manual
  smoke test after install and a quick way to verify state without re-reading every script.

**Division of responsibility (omawsl vs. apt/mise/docker):** `bin/omawsl` owns exactly two
things — omawsl's own scripts/configs (`update`, `migrate`), and re-running or removing what
*it* installed (`theme`, `uninstall`). It does **not** wrap or replace `sudo apt update && sudo
apt upgrade`, `mise upgrade`, or `docker image pull` — those remain the user's own commands for
keeping installed packages, language versions, and container images current, exactly as in
upstream Omakub (confirmed: its own `update.sh` does not touch apt, mise, or docker upgrades
either). This keeps a clean boundary: omawsl updates *itself*; the underlying package managers
update *what it installed*. There is no dual/competing update path for the same thing.

## 15. Testing & verification

- No CI/hardware exists in this environment to run a real WSL instance, so verification is
  manual: after implementation, test on an actual fresh WSL2 Ubuntu instance (or a disposable
  one via `wsl --install -d Ubuntu` + `wsl --unregister` to reset), running the real `boot.sh`
  one-liner end to end.
- Each `install/terminal/*.sh` script should be runnable in isolation (source it directly with
  the relevant `OMAWSL_*` vars pre-set) for faster iteration than a full fresh-VM run every
  time.
- `bin/omawsl doctor` serves as the repeatable smoke test after any install or migration run.

## 16. Documentation requirements

`README.md` must include an explicit **"What omawsl deliberately excludes"** section (not just
a features list) so a new user has a clear, accurate picture of what to expect and doesn't
assume gaps are oversights. It should name, at minimum: 37signals commercial products (HEY,
Basecamp), the Win11/GNOME desktop-app layer (Spotify, Signal, GNOME, Tactile, Ulauncher,
Typora), and any automatic Windows-side software installation — each with the one-line reason
already established in §2. This list should stay in sync with §2 as the source of truth if the
scope ever changes.
