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

This design went through a grilling pass after the initial draft; several details below (arch
handling, init placement, using starship's own official presets, migration theme continuity, doctor
visibility) were corrected or added as a result — see inline notes.

## Components

### 1. `install/terminal/apps-terminal.sh` — install the binary

```bash
# omawsl_starship_asset
# starship's GitHub releases publish a glibc ("gnu") build for x86_64 but
# only a musl build for aarch64 (confirmed against the current release's
# asset list - no aarch64-unknown-linux-gnu asset exists). musl binaries
# are statically linked, so the aarch64 musl build runs fine on Ubuntu's
# glibc userspace regardless - this is exactly why upstream only ships
# musl for non-x86_64 Linux targets.
omawsl_starship_asset() {
  case "$(uname -m)" in
    aarch64) echo "starship-aarch64-unknown-linux-musl.tar.gz" ;;
    *) echo "starship-x86_64-unknown-linux-gnu.tar.gz" ;;
  esac
}

omawsl_starship_install_steps() {
  local asset
  asset="$(omawsl_starship_asset)"
  curl -fsSL "https://github.com/starship/starship/releases/latest/download/${asset}" | tar -xz -C /tmp starship
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
documented for lazydocker/zellij/lazygit. The tarball contains a flat `starship` binary, no
subdirectory (confirmed against the actual release asset).

`omawsl_install_starship` and `omawsl_install_starship_config` (below) are added to
`omawsl_install_terminal_apps`'s unconditional call list, alongside `omawsl_install_zellij` /
`omawsl_install_zellij_config` — starship is core, not a Phase-4-style picker item in `items.sh`.

### 2. `configs/starship-plain.toml` — the only shipped default config

Only **one** static file, not two. Starship's real zero-config default (`format = '$all'`, no config
file present at all) already is "starship's fuller informative default" — directory, git
branch/status, and every language module (Node.js, Ruby, Python, Go, PHP, Rust, Java, Elixir among
them) auto-activating per-directory with no format string to write or maintain. So the Nerd Font /
icon case ships **no file** — `~/.config/starship.toml` is simply never created for it, and starship
falls through to its built-in default.

The Cascadia Mono / no-Nerd-Font case ships starship's own official **"No Nerd Fonts Preset"**
(`starship preset no-nerd-font`) verbatim as `configs/starship-plain.toml`, generated once at
authoring time via `starship preset no-nerd-font -o configs/starship-plain.toml` and committed as a
static file, same as every other config in `configs/`. Using the official preset instead of a
hand-rolled equivalent means the "no icons" case is upstream-maintained, not omawsl's own to keep in
sync with starship's evolving default module set.

`omawsl_install_starship_config` copies `configs/starship-plain.toml` to
`~/.config/starship-plain.toml`, copy-if-absent — same idempotent shape as
`omawsl_install_zellij_config`, so a hand-edited config is never clobbered by a later `omawsl
update`. It does *not* create `~/.config/starship.toml` — absence is the correct default state for
Nerd Font mode. This matches how zellij/btop also start on their own stock (non-omawsl) colors before
any `omawsl theme` call — starship starts on its own stock (non-omawsl) *and* un-themed-by-omawsl
look before one too.

### 3. `configs/bashrc` — remove the static `PS1` block, add starship init at end of file

Remove the current lines 40-55 (`OMAWSL_FONT_MODE` read + static `PS1=` assignment) entirely from
their current position. Starship's own README explicitly instructs placing its init line at the
*end* of `.bashrc` (github.com/starship/starship#6093 documents that hooks registered after
starship's break its `PROMPT_COMMAND` chain) — since `zoxide`/`mise` also mutate `PROMPT_COMMAND`
and `PATH`/env for the current directory, starship must run *after* them so its language-version
modules read the already-updated environment on every render, not a one-render-stale value. New
block goes immediately before the final `exec zellij` guard (which must stay the literal last thing
in the file):

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

Nerd Font / unset `OMAWSL_FONT_MODE` leaves `STARSHIP_CONFIG` unset, so starship reads
`~/.config/starship.toml` if present (a theme was applied - Component 4) or falls through to its
built-in default (never themed yet - Component 2). The `command -v starship` fallback keeps today's
exact prompt intact if the binary is somehow missing, so a broken/offline install never leaves the
user with a broken shell.

### 4. `bin/omawsl-sub/theme.sh` — wire into the theme system

Each `themes/<name>/` directory gains `starship.toml` + `starship-plain.toml` (20 files total across
10 themes) — hand-authored, matching this repo's existing convention for every other per-theme file
(btop/zellij/neovim/vscode/windows-terminal are all static, no generator tooling anywhere in the
repo). Each is built from the same two official presets as Component 2 (default `$all` format and
the no-nerd-font preset respectively) with an explicit `format = '$all'` line plus a
`[palettes.<name>]` block mapping that theme's existing bg/fg/red/green/blue/yellow/magenta/orange/
cyan/black/white hex values (already present in every `themes/<name>/zellij.kdl`) onto starship's
palette keys — starship's palette feature remaps the named colors (`red`, `green`, `blue`, etc.) that
the official presets' module styles already reference, so no per-module style rewriting is needed,
just the one palette block per file.

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
adapter (`starship/starship` repo `tag_name`, e.g. `v1.26.0` - a plain semver tag, same shape
`omawsl_orphan_extract_semver` already handles) — same shape as the existing lazydocker adapter. Its
`apply_update` case calls the unguarded `omawsl_starship_install_steps` from Component 1, matching
how zellij's forced-update path already works.

### 6. `bin/omawsl-sub/doctor.sh` — missing-install visibility

Unlike zellij (never promised as universal, just always installed in practice), starship is
explicitly meant to be on every machine after this ships, so a silently failed migration install
(offline box, corporate proxy blocking GitHub) needs to surface somewhere. Add a bespoke check
(`command -v starship`) following the same non-`items.sh`-loop shape as the existing docker-daemon-
proxy pending-config check, reporting something like "Starship: not installed (prompt falling back to
legacy PS1) - re-run `omawsl migrate`" when missing.

### 7. `migrations/<timestamp>.sh` — bring existing installs along, preserving theme continuity

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$OMAWSL_ROOT_DIR/install/terminal/apps-terminal.sh"
# shellcheck source=../bin/omawsl-sub/theme.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/theme.sh"

omawsl_install_starship
omawsl_install_starship_config

# Preserve visual consistency for anyone who already picked a real omawsl
# theme (zellij is always-on and is theme.sh's first, always-patched
# target, so its config is the single reliable source of "what theme is
# currently active" - there's no separate state file for it). A config
# that was never themed still has zellij's own stock `theme "..."` value,
# which omawsl_theme_is_valid correctly rejects, so this only fires for
# machines that actually ran `omawsl theme <name>` before.
zellij_config="$HOME/.config/zellij/config.kdl"
if [[ -f "$zellij_config" ]]; then
  active_theme="$(grep -oP '(?<=theme ")[^"]+' "$zellij_config" | head -n1)"
  if [[ -n "$active_theme" ]] && omawsl_theme_is_valid "$active_theme"; then
    omawsl_theme_apply "$active_theme"
  fi
fi
```

No copy step needed for `configs/bashrc` itself — it's sourced directly from the `$OMAWSL_HOME`
checkout (`install/lib.sh`'s `omawsl_ensure_bashrc_source_line`), so `omawsl update`'s `git pull`
already delivers Component 3's new logic; the migration only needs to install the binary, seed the
default plain config, and (if applicable) re-apply the user's already-chosen theme so their prompt
doesn't visually clash with the rest of their already-themed setup.

Calling the full `omawsl_theme_apply` here (not just copying the two starship files) is deliberate -
it's idempotent and keeps this migration resilient to future per-theme additions, at the cost of
redundantly re-copying zellij/btop/neovim/vscode/opencode/Windows-Terminal files that are already
correct. Given this migration only runs once per machine, that's a non-issue.

### 8. No uninstall script

Matches zellij's existing precedent: always-on core terminal tools aren't individually removable via
`uninstall/`, so starship doesn't get one either.

## Data flow

```
Fresh install:  apps-terminal.sh → install binary + starship-plain.toml (copy-if-absent) ─┐
                                                                                             │
Existing install: omawsl update → git pull (refreshes bashrc) ──────────────────────────┐ │
                                 → omawsl_migrate → install binary + starship-plain.toml  │ │
                                   (if absent) → re-apply last-active theme, if any ──────┤ │
                                                                                            ▼ ▼
                                                    every new shell: bashrc picks STARSHIP_CONFIG
                                                    per OMAWSL_FONT_MODE (or none = built-in
                                                    default), `eval "$(starship init bash)"` LAST
                                                                     ▲
omawsl theme <name>: overwrite ~/.config/starship{,-plain}.toml ────┘

doctor: reports missing starship independently of the above
```

## Error handling

- `starship` binary missing (failed/offline install, or a checkout mid-migration) → `configs/bashrc`
  falls back to today's exact `PS1` logic, never leaves an unset/broken prompt; `doctor` surfaces it
  so it doesn't stay invisible indefinitely (Component 6).
- `OMAWSL_FONT_MODE` unset (install predates the font-mode choice entirely) → same as today: treated
  as the Nerd Font case, uses starship's built-in default or the active theme's icon config.
- `omawsl theme <name>` run before starship config files exist yet → `cp` creates
  `~/.config/starship.toml`/`starship-plain.toml` fresh; no guard needed since this path always
  overwrites already.
- Migration re-run (`omawsl migrate` called twice, or `starship` already present from a fresh
  install) → `omawsl_install_starship`'s `command -v` guard and `omawsl_install_starship_config`'s
  copy-if-absent both no-op cleanly; re-applying the active theme is itself idempotent.
- Migration's zellij-config theme detection finds a value that isn't a real omawsl theme name (stock
  zellij default, or a theme name from some future omawsl version this migration predates) →
  `omawsl_theme_is_valid` rejects it, migration silently skips theme re-application and leaves the
  un-themed defaults from Component 2 in place.

## Testing

- `tests/a_shell_test.bats`: extend/replace the 3 existing `PS1`/`OMAWSL_FONT_MODE` tests —
  `STARSHIP_CONFIG` unset for Nerd Font/unset, set to the plain-file path for Cascadia Mono, and a
  "starship not on PATH → legacy PS1 fallback" case. Also assert the starship init line runs after
  the zoxide/mise `eval` lines in the rendered file (ordering regression guard).
- New `tests/theme_starship_test.bats` (paralleling `tests/theme_files_test.bats`): `omawsl theme
  <name>` deploys that theme's `starship.toml`/`starship-plain.toml` to `~/.config/`, for a couple of
  representative theme names.
- `tests/orphan_tools_test.bats` (or equivalent): `starship` slug reports installed/not-installed and
  version-check correctly, same assertions already used for zellij/lazydocker.
- New/extended doctor test: reports starship missing when `command -v starship` fails, silent when
  present.
- New migration test: given a `~/.config/zellij/config.kdl` with a valid omawsl theme name already
  patched in, the migration re-applies that theme's starship files; given a stock/default zellij
  config, it leaves the plain Component-2 defaults in place instead.
- Manual end-to-end check on a real WSL2 box per the project's stated verification convention (see
  `docs/superpowers/plans/roadmap.md`'s per-phase entries): both font modes, at least one theme
  switch, and one full `omawsl update` from a pre-starship checkout that already had a theme applied.

## Non-scope / explicitly deferred

- No first-run choice, no opt-out toggle — this ships as an unconditional default per the design
  discussion; a later "disable starship" escape hatch is a separate future issue if requested.
- No fish/zsh/PowerShell integration — omawsl ships bash only (`docs/config-safety.md`).
- No generator/templating tooling for the 20 per-theme files — hand-authored, matching this repo's
  existing per-theme-file convention; revisit only if that convention itself changes.
- Per-user starship.toml customization tooling (e.g. a `omawsl starship` subcommand) beyond the
  copy-if-absent default and theme-driven overwrite described above.
