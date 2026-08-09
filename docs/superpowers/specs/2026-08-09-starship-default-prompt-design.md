# Starship as the default prompt — design

**Date:** 2026-08-09
**Status:** approved
**Scope:** replace `configs/bashrc`'s hand-rolled `PS1` with [Starship](https://starship.rs), installed
and enabled unconditionally (no first-run choice) for both fresh and existing installs, themed per
omawsl's 10 color themes, with a plain-text variant for non-Nerd-Font users — closes issue #5.

## Why

Issue #5: "Let's have starship prompt as default." Today `configs/bashrc` sets a single hand-rolled
`PS1` (a lone Nerd Font glyph, path shown in the terminal tab title instead of inline — the exact
port of Omakub's own `defaults/bash/prompt`, per
`docs/superpowers/specs/2026-07-14-omawsl-aliases-parity-design.md` §5). Starship replaces that with
a real prompt engine (directory, git branch/status, language-version badges) while staying pure
display logic — it only sets `PS1`/`PROMPT_COMMAND`, so it doesn't functionally overlap with
`zoxide`'s or `mise`'s own `PROMPT_COMMAND` hooks already in this file (directory jumping and
runtime-shim activation, respectively); all three follow the same "append, don't clobber
`PROMPT_COMMAND`" convention.

Unlike every other optional tool in this repo, this ships as an unconditional default, not a
first-run choice — reached deliberately in discussion: the fuller prompt is judged a straightforward
improvement worth giving everyone, not a behavior change (like the Copilot autopilot design) that
needs explicit consent. It does still need to respect the one existing piece of related state:
`OMAWSL_FONT_MODE`, the font choice from `docs/windows-setup.md#fonts` that already exists because
the current icon-only `PS1` renders as a tofu box without a Nerd Font. Starship's fuller preset
leans on Nerd Font icons even more (directory/git/language glyphs), so the same Cascadia-Mono
fallback idea carries over as a second, glyph-free starship config.

## Components

### 1. `install/terminal/apps-terminal.sh` — install the binary

`omawsl_starship_install_steps` (no guard, mirrors `omawsl_zellij_install_steps`'s split-function
shape so `bin/omawsl-sub/orphan-tools.sh`'s forced-update path can reuse it):

```bash
omawsl_starship_install_steps() {
  local arch
  arch="$(uname -m)"
  curl -fsSL "https://github.com/starship/starship/releases/latest/download/starship-${arch}-unknown-linux-gnu.tar.gz" | tar -xz -C /tmp
  sudo install -m 0755 /tmp/starship /usr/local/bin/starship
  rm -f /tmp/starship
}

omawsl_install_starship() {
  if command -v starship &>/dev/null; then return 0; fi
  omawsl_starship_install_steps
}
```

Direct prebuilt-binary release, not starship's own `curl -sS https://starship.rs/install.sh | sh`
one-liner — same "auditable explicit steps, not piping an unseen remote script" rationale already
documented for lazydocker/zellij/lazygit.

`omawsl_install_starship` and `omawsl_install_starship_config` (below) are added to
`omawsl_install_terminal_apps`'s unconditional call list, alongside `omawsl_install_zellij` /
`omawsl_install_zellij_config` — starship is core, not a Phase-4-style picker item in `items.sh`.

### 2. `configs/starship.toml`, `configs/starship-plain.toml` — default config

Two static files: an icon-using variant (starship's informative default-style preset: directory,
git branch/status, language-version modules) and a glyph-free variant using text labels instead of
Nerd Font icons in the same modules. `omawsl_install_starship_config` copies both into
`~/.config/starship.toml` / `~/.config/starship-plain.toml`, copy-if-absent — same idempotent shape
as `omawsl_install_zellij_config`, so a hand-edited config is never clobbered by a later
`omawsl update`. This gives every fresh install a working, un-themed prompt immediately, same as
zellij/btop starting on their own stock colors before any `omawsl theme` call.

### 3. `configs/bashrc` — replace the static `PS1` block (current lines 40-55)

```bash
OMAWSL_FONT_MODE="$(grep -m1 '^OMAWSL_FONT_MODE=' "${OMAWSL_STATE_DIR:-$HOME/.local/state/omawsl}/choices.env" 2>/dev/null | cut -d'"' -f2)"
if command -v starship &>/dev/null; then
  if [[ "$OMAWSL_FONT_MODE" == "Cascadia Mono"* ]]; then
    export STARSHIP_CONFIG="$HOME/.config/starship-plain.toml"
  fi
  eval "$(starship init bash)"
else
  # Pre-starship fallback - offline/failed install, or a checkout that
  # predates this feature and hasn't finished migrating yet.
  if [[ "$OMAWSL_FONT_MODE" == "Cascadia Mono"* ]]; then
    PS1='\u@\h:\w\$ '
  else
    PS1=$' '
  fi
  PS1="\[\e]0;\w\a\]$PS1"
fi
unset OMAWSL_FONT_MODE
```

Nerd Font / unset `OMAWSL_FONT_MODE` leaves `STARSHIP_CONFIG` unset, so starship reads its default
`~/.config/starship.toml` path. The `command -v starship` fallback keeps today's exact prompt intact
if the binary is somehow missing, so a broken/offline install never leaves the user with a broken
shell.

### 4. `bin/omawsl-sub/theme.sh` — wire into the theme system

Each `themes/<name>/` directory gains `starship.toml` + `starship-plain.toml`, generated from the
same two base presets in Component 2 with that theme's palette layered in via a `[palettes.<name>]`
block (`palette = "<name>"` + `[palettes.<name>]` mapping starship's semantic color keys to that
theme's existing bg/fg/red/green/blue/yellow/magenta/orange/cyan/black/white hex values — already
present in every `themes/<name>/zellij.kdl`, so no new palette source is needed).

`omawsl_theme_apply` gets two more lines alongside its existing zellij/btop/neovim/vscode copies:

```bash
cp "$theme_dir/starship.toml" "$HOME/.config/starship.toml"
cp "$theme_dir/starship-plain.toml" "$HOME/.config/starship-plain.toml"
```

Unconditional overwrite (no `[[ -f ... ]]` guard) — same as the existing neovim.lua/vscode.sh theme
handling, since this is an explicit user-invoked `omawsl theme <name>` action, not a passive
install-time default.

### 5. `bin/omawsl-sub/orphan-tools.sh` — update-checking

Add `starship` to `omawsl_orphan_tool_slugs`, `omawsl_orphan_tool_label` ("Starship"),
`omawsl_orphan_tool_installed` (`command -v starship`), and a GitHub-releases-API version-check
adapter (`starship/starship` repo `tag_name`) — same shape as the existing lazydocker adapter. Its
`apply_update` case calls the unguarded `omawsl_starship_install_steps` from Component 1, matching
how zellij's forced-update path already works.

### 6. `migrations/<timestamp>.sh` — bring existing installs along

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$OMAWSL_ROOT_DIR/install/terminal/apps-terminal.sh"
omawsl_install_starship
omawsl_install_starship_config
```

No copy step needed for `configs/bashrc` itself — it's sourced directly from the `$OMAWSL_HOME`
checkout (`install/lib.sh`'s `omawsl_ensure_bashrc_source_line`), so `omawsl update`'s `git pull`
already delivers Component 3's new logic; the migration only needs to install the binary and seed
the two default config files, exactly what a fresh install's `apps-terminal.sh` call does.

### 7. No uninstall script

Matches zellij's existing precedent: always-on core terminal tools aren't individually removable via
`uninstall/`, so starship doesn't get one either.

## Data flow

```
Fresh install:  apps-terminal.sh → install binary + default configs ─┐
                                                                       │
Existing install: omawsl update → git pull (refreshes bashrc) ────┐  │
                                 → omawsl_migrate → install binary  │  │
                                   + default configs (if absent) ──┤  │
                                                                     ▼  ▼
                                          every new shell: bashrc picks
                                          STARSHIP_CONFIG per OMAWSL_FONT_MODE,
                                          `eval "$(starship init bash)"`
                                                     ▲
omawsl theme <name>: overwrite ~/.config/starship{,-plain}.toml ─────┘
```

## Error handling

- `starship` binary missing (failed/offline install, or a checkout mid-migration) → `configs/bashrc`
  falls back to today's exact `PS1` logic, never leaves an unset/broken prompt.
- `OMAWSL_FONT_MODE` unset (install predates the font-mode choice entirely) → same as today: treated
  as the Nerd Font case, keeps the icon-using config.
- `omawsl theme <name>` run before starship config files exist yet (e.g. a very old checkout mid
  partial migration) → `cp` creates `~/.config/starship.toml` fresh; no guard needed since this path
  always overwrites already.
- Migration re-run (`omawsl migrate` called twice, or `starship` already present from a fresh
  install) → `omawsl_install_starship`'s `command -v` guard and `omawsl_install_starship_config`'s
  copy-if-absent both no-op cleanly.

## Testing

- `tests/a_shell_test.bats`: extend/replace the 3 existing `PS1`/`OMAWSL_FONT_MODE` tests —
  `STARSHIP_CONFIG` unset (icons) for Nerd Font/unset, set to the plain-file path for Cascadia Mono,
  and a "starship not on PATH → legacy PS1 fallback" case.
- New `tests/theme_starship_test.bats` (paralleling `tests/theme_files_test.bats`): `omawsl theme
  <name>` deploys that theme's `starship.toml`/`starship-plain.toml` to `~/.config/`, for a couple of
  representative theme names.
- `tests/orphan_tools_test.bats` (or equivalent): `starship` slug reports installed/not-installed and
  version-check correctly, same assertions already used for zellij/lazydocker.
- Manual end-to-end check on a real WSL2 box per the project's stated verification convention (see
  `docs/superpowers/plans/roadmap.md`'s per-phase entries): both font modes, at least one theme
  switch, and one full `omawsl update` from a pre-starship checkout.

## Non-scope / explicitly deferred

- No first-run choice, no opt-out toggle — this ships as an unconditional default per the design
  discussion; a later "disable starship" escape hatch is a separate future issue if requested.
- No fish/zsh/PowerShell integration — omawsl ships bash only (`docs/config-safety.md`).
- `bin/omawsl-sub/doctor.sh` reporting — no pending/stale state to detect beyond what the migration
  already resolves unconditionally; not added.
- Per-user starship.toml customization tooling (e.g. a `omawsl starship` subcommand) beyond the
  copy-if-absent default and theme-driven overwrite described above.
