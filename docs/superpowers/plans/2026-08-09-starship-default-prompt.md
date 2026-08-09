# Starship as the Default Prompt Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace omawsl's hand-rolled `PS1` with [Starship](https://starship.rs), installed and enabled unconditionally for fresh and existing installs, themed per omawsl's 10 color themes, with an official no-icon variant for non-Nerd-Font users.

**Architecture:** A prebuilt Starship binary is installed the same way zellij/lazydocker already are (direct GitHub release, no piped installer). `configs/bashrc` picks between starship's true zero-config default (Nerd Font mode) and an official "no-nerd-font" preset (Cascadia Mono mode) via `$STARSHIP_CONFIG`, with the exact legacy `PS1` logic as a fallback if the binary is missing. `bin/omawsl-sub/theme.sh` gains two more per-theme files (icon + plain, palette-recolored) copied on every `omawsl theme <name>` call. A migration brings existing installs current and re-applies whatever theme they'd already genuinely picked.

**Tech Stack:** Bash (all existing conventions), bats for tests, `curl`/`tar`/`sudo install` for the binary, TOML for starship's own config format.

## Global Constraints

- Bash only — omawsl ships no fish/zsh/PowerShell integration (`docs/config-safety.md`).
- No first-run choice, no opt-out — starship is an unconditional default per the approved design.
- No generator/templating tooling committed to the repo for the 20 per-theme files — hand-authored static files, matching every other per-theme file in this repo (btop/zellij/neovim/vscode/windows-terminal).
- Direct-from-GitHub-release binary installs only, never a piped upstream install script — matches lazydocker/zellij/lazygit/fastfetch precedent.
- Install-time config deploys are copy-if-absent (never clobber a hand-edited file); `omawsl theme <name>` deploys are unconditional overwrites (explicit user action).
- Every new/changed function gets bats coverage in the existing suite's file for that area — no new top-level test-running mechanism.
- Full design rationale: `docs/superpowers/specs/2026-08-09-starship-default-prompt-design.md`.

---

## Task 1: Install the starship binary and its default plain-mode config

**Files:**
- Modify: `install/terminal/apps-terminal.sh`
- Create: `configs/starship-plain.toml`
- Test: `tests/apps_terminal_test.bats`

**Interfaces:**
- Produces: `omawsl_starship_asset()` (echoes the correct release asset filename for the current arch), `omawsl_starship_install_steps()` (unguarded install, reused by Task 4 and Task 6), `omawsl_install_starship()` (guarded), `omawsl_install_starship_config()` (copy-if-absent config deploy). All added to `omawsl_install_terminal_apps`'s unconditional call list.

- [ ] **Step 1: Write the failing tests**

Open `tests/apps_terminal_test.bats`. In its `setup()`, add `starship` to the existing `stub_hide_command` call so these tests are deterministic regardless of whether the test host happens to have starship installed:

```bash
  stub_hide_command lazydocker zellij lazygit fastfetch starship
```

Then add these tests (anywhere after the existing zellij tests is fine):

```bash
@test "omawsl_starship_asset picks the gnu build for x86_64" {
  uname() { echo "x86_64"; }
  export -f uname
  [ "$(omawsl_starship_asset)" = "starship-x86_64-unknown-linux-gnu.tar.gz" ]
}

@test "omawsl_starship_asset picks the musl build for aarch64 (starship publishes no aarch64-gnu build)" {
  uname() { echo "aarch64"; }
  export -f uname
  [ "$(omawsl_starship_asset)" = "starship-aarch64-unknown-linux-musl.tar.gz" ]
}

@test "installs starship via its official GitHub release when not already present" {
  run omawsl_install_starship
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://github.com/starship/starship/releases/latest/download/starship-"*"-unknown-linux-"*".tar.gz"* ]]
  [[ "$(stub_calls)" == *"sudo install -m 0755 /tmp/starship /usr/local/bin/starship"* ]]
}

@test "skips starship when already installed" {
  stub_command starship
  run omawsl_install_starship
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"starship-"*"-unknown-linux-"* ]]
}

@test "deploys configs/starship-plain.toml to ~/.config/starship-plain.toml" {
  run omawsl_install_starship_config
  [ "$status" -eq 0 ]
  diff "$HOME/.config/starship-plain.toml" "$REPO_ROOT/configs/starship-plain.toml"
}

@test "does not overwrite an existing starship-plain.toml" {
  mkdir -p "$HOME/.config"
  echo 'palette = "my-custom-theme"' > "$HOME/.config/starship-plain.toml"
  run omawsl_install_starship_config
  [ "$status" -eq 0 ]
  [[ "$(cat "$HOME/.config/starship-plain.toml")" == 'palette = "my-custom-theme"' ]]
}

@test "omawsl_install_terminal_apps installs starship and deploys its default plain config" {
  run omawsl_install_terminal_apps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo install -m 0755 /tmp/starship /usr/local/bin/starship"* ]]
  diff "$HOME/.config/starship-plain.toml" "$REPO_ROOT/configs/starship-plain.toml"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/apps_terminal_test.bats`
Expected: FAIL — `omawsl_starship_asset`/`omawsl_install_starship`/`omawsl_install_starship_config` not defined, and `configs/starship-plain.toml` doesn't exist yet.

- [ ] **Step 3: Create `configs/starship-plain.toml`**

This is starship's own official "No Nerd Fonts Preset" (`starship preset no-nerd-font`), fetched verbatim from `starship/starship`'s `docs/public/presets/toml/no-nerd-font.toml` — it only overrides symbols for the 5 modules that otherwise default to Nerd-Font-only glyphs; everything else stays on starship's built-in `$all` default:

```toml
"$schema" = 'https://starship.rs/config-schema.json'

[azure]
symbol = "☁️ "

[battery]
full_symbol = "• "
charging_symbol = "⇡ "
discharging_symbol = "⇣ "
unknown_symbol = "❓ "
empty_symbol = "❗ "

[erlang]
symbol = "ⓔ "

[nodejs]
symbol = "[⬢](bold green) "

[pulumi]
symbol = "🧊 "
```

- [ ] **Step 4: Implement `omawsl_starship_asset`, `omawsl_starship_install_steps`, `omawsl_install_starship`, `omawsl_install_starship_config` in `install/terminal/apps-terminal.sh`**

Insert after `omawsl_install_fastfetch` (around line 197) and before `omawsl_install_zellij_config`:

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

# omawsl_starship_install_steps
# The actual install command, no guard - same split rationale as
# omawsl_zellij_install_steps above. Reused unguarded by
# bin/omawsl-sub/orphan-tools.sh's forced-update path and by the
# starship migration.
omawsl_starship_install_steps() {
  local asset
  asset="$(omawsl_starship_asset)"
  curl -fsSL "https://github.com/starship/starship/releases/latest/download/${asset}" | tar -xz -C /tmp starship
  sudo install -m 0755 /tmp/starship /usr/local/bin/starship
  rm -f /tmp/starship
}

# omawsl_install_starship
# No Ubuntu package exists for starship - installs the official prebuilt
# binary release directly from GitHub rather than starship's own
# `curl -sS https://starship.rs/install.sh | sh`, so the exact steps stay
# auditable here instead of delegating to an unseen remote script.
omawsl_install_starship() {
  if command -v starship &>/dev/null; then
    return 0
  fi
  omawsl_starship_install_steps
}

# omawsl_install_starship_config
# Deploys omawsl's own configs/starship-plain.toml (starship's own
# official no-nerd-font preset - Cascadia Mono users' plain-mode config)
# to starship's real config location, copy-if-absent like
# omawsl_install_zellij_config above. No equivalent deploy for the
# Nerd Font/icon case: absence of ~/.config/starship.toml is itself the
# correct un-themed default (starship's real, literal zero-config
# built-in look) until `omawsl theme <name>` writes a themed one
# (Task 3).
omawsl_install_starship_config() {
  local config_file="$HOME/.config/starship-plain.toml"
  if [[ -f "$config_file" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$config_file")"
  cp "$SCRIPT_DIR/../../configs/starship-plain.toml" "$config_file"
}
```

- [ ] **Step 5: Wire both into `omawsl_install_terminal_apps`**

In the same file, update the function (around line 31-42) to call both, alongside the existing zellij/btop calls:

```bash
omawsl_install_terminal_apps() {
  sudo apt-get update -qq
  sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop jq bash-completion

  omawsl_install_lazydocker
  omawsl_install_zellij
  omawsl_install_lazygit
  omawsl_install_fastfetch
  omawsl_install_starship
  omawsl_install_zellij_config
  omawsl_install_btop_config
  omawsl_install_starship_config
  omawsl_install_cli
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bats tests/apps_terminal_test.bats`
Expected: PASS, all tests including the pre-existing ones.

- [ ] **Step 7: Commit**

```bash
git add install/terminal/apps-terminal.sh configs/starship-plain.toml tests/apps_terminal_test.bats
git commit -m "feat: install starship binary and default plain-mode config"
```

---

## Task 2: Switch `configs/bashrc` from the static PS1 to starship

**Files:**
- Modify: `configs/bashrc`
- Test: `tests/a_shell_test.bats`

**Interfaces:**
- Consumes: `omawsl_install_starship_config`'s output path `$HOME/.config/starship-plain.toml` (Task 1).
- Produces: nothing new consumed by later tasks — this is the shell-visible surface only.

- [ ] **Step 1: Write the failing tests**

In `tests/a_shell_test.bats`, replace the 3 existing tests named `"PS1 uses Omakub's icon-only prompt..."`, `"PS1 stays icon-only when OMAWSL_FONT_MODE is Nerd Font"`, and `"PS1 falls back to a plain user@host:path prompt when OMAWSL_FONT_MODE is Cascadia Mono"` (currently lines 321-354) with:

```bash
@test "STARSHIP_CONFIG is unset (starship's real built-in default) when OMAWSL_FONT_MODE is unset and starship is installed" {
  export HOME="$BATS_TEST_TMPDIR/home_no_font_choice_starship"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/starship"
  chmod +x "$HOME/.local/bin/starship"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo "STARSHIP_CONFIG=${STARSHIP_CONFIG:-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"STARSHIP_CONFIG=unset"* ]]
}

@test "STARSHIP_CONFIG is unset when OMAWSL_FONT_MODE is Nerd Font and starship is installed" {
  export HOME="$BATS_TEST_TMPDIR/home_nerd_font_starship"
  mkdir -p "$HOME/.local/state/omawsl" "$HOME/.local/bin"
  printf 'OMAWSL_FONT_MODE="Nerd Font (enhanced)"\n' > "$HOME/.local/state/omawsl/choices.env"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/starship"
  chmod +x "$HOME/.local/bin/starship"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo "STARSHIP_CONFIG=${STARSHIP_CONFIG:-unset}"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"STARSHIP_CONFIG=unset"* ]]
}

@test "STARSHIP_CONFIG points at the plain preset when OMAWSL_FONT_MODE is Cascadia Mono and starship is installed" {
  export HOME="$BATS_TEST_TMPDIR/home_cascadia_starship"
  mkdir -p "$HOME/.local/state/omawsl" "$HOME/.local/bin"
  printf 'OMAWSL_FONT_MODE="Cascadia Mono (zero install)"\n' > "$HOME/.local/state/omawsl/choices.env"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/starship"
  chmod +x "$HOME/.local/bin/starship"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo "$STARSHIP_CONFIG"'
  [ "$status" -eq 0 ]
  [[ "$output" == "$HOME/.config/starship-plain.toml" ]]
}

@test "falls back to the legacy icon-only PS1 when starship is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_no_starship"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command starship
  run bash -i -c 'echo "$PS1"'
  [ "$status" -eq 0 ]
  [[ "$output" != *'\u@\h'* ]]
  [[ "$output" == *'\[\e]0;\w\a\]'* ]]
}

@test "falls back to the legacy Cascadia Mono PS1 when starship is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_no_starship_cascadia"
  mkdir -p "$HOME/.local/state/omawsl"
  printf 'OMAWSL_FONT_MODE="Cascadia Mono (zero install)"\n' > "$HOME/.local/state/omawsl/choices.env"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command starship
  run bash -i -c 'echo "$PS1"'
  [ "$status" -eq 0 ]
  [[ "$output" == *'\u@\h:\w\$ '* ]]
  [[ "$output" == *'\[\e]0;\w\a\]'* ]]
}

@test "starship init runs after zoxide/mise activation in configs/bashrc, not before" {
  local file="$REPO_ROOT/configs/bashrc"
  local zoxide_line mise_line starship_line
  zoxide_line="$(grep -n 'zoxide init bash' "$file" | cut -d: -f1)"
  mise_line="$(grep -n 'mise activate bash' "$file" | cut -d: -f1)"
  starship_line="$(grep -n 'starship init bash' "$file" | cut -d: -f1)"
  [ -n "$zoxide_line" ]
  [ -n "$mise_line" ]
  [ -n "$starship_line" ]
  [ "$starship_line" -gt "$zoxide_line" ]
  [ "$starship_line" -gt "$mise_line" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/a_shell_test.bats`
Expected: FAIL — `configs/bashrc` still sets a static `PS1`, never reads/sets `STARSHIP_CONFIG`, and has no `starship init bash` line at all.

- [ ] **Step 3: Remove the old static prompt block from `configs/bashrc`**

Delete these lines (currently 40-55):

```bash
# Omakub-parity icon-only prompt: a single Nerd Font glyph in the prompt
# itself, path shown in the terminal tab/window title instead of inline.
# Falls back to a plain user@host:path prompt when OMAWSL_FONT_MODE (set at
# install time - docs/windows-setup.md#fonts) is the zero-install Cascadia
# Mono option: that glyph renders as a tofu box without a matching Nerd
# Font, confirmed on a real corporate machine without one installed.
# Missing/unset (e.g. an install that predates this choice) keeps today's
# icon-only default rather than silently changing existing prompts.
OMAWSL_FONT_MODE="$(grep -m1 '^OMAWSL_FONT_MODE=' "${OMAWSL_STATE_DIR:-$HOME/.local/state/omawsl}/choices.env" 2>/dev/null | cut -d'"' -f2)"
if [[ "$OMAWSL_FONT_MODE" == "Cascadia Mono"* ]]; then
  PS1='\u@\h:\w\$ '
else
  PS1=$' '
fi
PS1="\[\e]0;\w\a\]$PS1"
unset OMAWSL_FONT_MODE
```

- [ ] **Step 4: Insert the starship block at the end of the file, before the zellij auto-launch guard**

Find the comment block that currently starts with `# Omakub parity: every new interactive shell drops straight into zellij` (now around line 150 after Step 3's deletion). Insert immediately **before** it:

```bash
# Starship (design spec docs/superpowers/specs/2026-08-09-starship-default-prompt-design.md):
# starship's own README says to add its init line at the END of .bashrc,
# after any other tool that also hooks PROMPT_COMMAND (zoxide/mise above) -
# starship/starship#6093 documents hooks registered after starship's own
# breaking the chain. Placed last (but still before the zellij exec guard
# below, which replaces this shell process outright) so starship's
# language-version modules read the already-updated PATH/env from those
# tools' own hooks, not a stale value from before they ran.
OMAWSL_FONT_MODE="$(grep -m1 '^OMAWSL_FONT_MODE=' "${OMAWSL_STATE_DIR:-$HOME/.local/state/omawsl}/choices.env" 2>/dev/null | cut -d'"' -f2)"
if command -v starship &>/dev/null; then
  if [[ "$OMAWSL_FONT_MODE" == "Cascadia Mono"* ]]; then
    export STARSHIP_CONFIG="$HOME/.config/starship-plain.toml"
  fi
  eval "$(starship init bash)"
else
  # Pre-starship fallback - offline/failed install, or a checkout that
  # predates this feature and hasn't finished migrating yet (Task 6).
  # Exact byte-for-byte copy of the old static PS1 logic this replaces.
  if [[ "$OMAWSL_FONT_MODE" == "Cascadia Mono"* ]]; then
    PS1='\u@\h:\w\$ '
  else
    PS1=$' '
  fi
  PS1="\[\e]0;\w\a\]$PS1"
fi
unset OMAWSL_FONT_MODE
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bats tests/a_shell_test.bats`
Expected: PASS, all tests including the unrelated pre-existing ones (EDITOR/VISUAL, INPUTRC, zellij auto-launch, etc. — Step 3/4 only touch the prompt block).

- [ ] **Step 6: Commit**

```bash
git add configs/bashrc tests/a_shell_test.bats
git commit -m "feat: switch the default prompt from a static PS1 to starship"
```

---

## Task 3: Wire starship into the 10-theme color system

**Files:**
- Create: `themes/<name>/starship.toml` and `themes/<name>/starship-plain.toml` for all 10 themes (20 files)
- Modify: `bin/omawsl-sub/theme.sh`
- Modify: `tests/theme_files_test.bats`
- Modify: `tests/omawsl_cli_test.bats`

**Interfaces:**
- Consumes: each theme's existing 11-color palette (bg/fg/red/green/blue/yellow/magenta/orange/cyan/black/white), already present in `themes/<name>/zellij.kdl`.
- Produces: `~/.config/starship.toml` and `~/.config/starship-plain.toml` deployed by `omawsl_theme_apply <name>` — consumed by Task 6's migration.

- [ ] **Step 1: Write the failing tests**

In `tests/theme_files_test.bats`, update the `"every ported theme has all 5 required files"` test to require 7 files:

```bash
@test "every ported theme has all 7 required files" {
  for name in catppuccin everforest gruvbox kanagawa matte-black nord osaka-jade ristretto rose-pine tokyo-night; do
    for f in neovim.lua zellij.kdl btop.theme vscode.sh windows-terminal-scheme.json starship.toml starship-plain.toml; do
      [ -f "$REPO_ROOT/themes/$name/$f" ] || { echo "missing themes/$name/$f"; return 1; }
    done
  done
}
```

Add a regression check for the hex values at the end of the same file:

```bash
@test "tokyo-night starship.toml palette matches its zellij.kdl hex values" {
  local f="$REPO_ROOT/themes/tokyo-night/starship.toml"
  grep -q 'red = "#F93357"' "$f"
  grep -q 'green = "#9ECE6A"' "$f"
  grep -q 'blue = "#7AA2F7"' "$f"
}
```

In `tests/omawsl_cli_test.bats`, add after the existing `"omawsl_theme_apply copies the zellij/btop theme files..."` test:

```bash
@test "omawsl_theme_apply copies the theme's starship configs into ~/.config" {
  run omawsl_theme_apply "tokyo-night"
  [ "$status" -eq 0 ]
  diff "$HOME/.config/starship.toml" "$REPO_ROOT/themes/tokyo-night/starship.toml"
  diff "$HOME/.config/starship-plain.toml" "$REPO_ROOT/themes/tokyo-night/starship-plain.toml"
}

@test "omawsl_theme_apply overwrites an existing ~/.config/starship.toml unconditionally" {
  mkdir -p "$HOME/.config"
  echo 'palette = "whatever"' > "$HOME/.config/starship.toml"
  run omawsl_theme_apply "rose-pine"
  [ "$status" -eq 0 ]
  diff "$HOME/.config/starship.toml" "$REPO_ROOT/themes/rose-pine/starship.toml"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/theme_files_test.bats tests/omawsl_cli_test.bats`
Expected: FAIL — the 20 new theme files don't exist yet, and `omawsl_theme_apply` doesn't copy them.

- [ ] **Step 3: Generate the 20 per-theme files**

Write this script to a scratch path (e.g. `/tmp/gen-starship-themes.sh`) — it's a one-time authoring aid, not committed to the repo (per the "no generator tooling" constraint; only its output, the 20 static files, gets committed):

```bash
#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/tuna/omawsl"

write_starship_theme_files() {
  local name="$1" red="$2" green="$3" blue="$4" yellow="$5" magenta="$6" orange="$7" cyan="$8" black="$9" white="${10}" bg="${11}" fg="${12}"
  local dir="$ROOT/themes/$name"

  cat > "$dir/starship.toml" <<EOF
# omawsl theme integration (design spec
# docs/superpowers/specs/2026-08-09-starship-default-prompt-design.md) -
# no format override, so starship's real \$all default module set stays
# intact; only the named colors its built-in module styles reference get
# remapped to this theme's own palette.
palette = "$name"

[palettes.$name]
red = "$red"
green = "$green"
blue = "$blue"
yellow = "$yellow"
magenta = "$magenta"
purple = "$magenta"
orange = "$orange"
cyan = "$cyan"
black = "$black"
white = "$white"
bg = "$bg"
fg = "$fg"
EOF

  cat > "$dir/starship-plain.toml" <<EOF
# omawsl theme integration, no-Nerd-Font variant - same palette override
# as starship.toml, layered onto starship's own official no-nerd-font
# preset (configs/starship-plain.toml) instead of the icon default.
"\$schema" = 'https://starship.rs/config-schema.json'

palette = "$name"

[palettes.$name]
red = "$red"
green = "$green"
blue = "$blue"
yellow = "$yellow"
magenta = "$magenta"
purple = "$magenta"
orange = "$orange"
cyan = "$cyan"
black = "$black"
white = "$white"
bg = "$bg"
fg = "$fg"

[azure]
symbol = "☁️ "

[battery]
full_symbol = "• "
charging_symbol = "⇡ "
discharging_symbol = "⇣ "
unknown_symbol = "❓ "
empty_symbol = "❗ "

[erlang]
symbol = "ⓔ "

[nodejs]
symbol = "[⬢](bold green) "

[pulumi]
symbol = "🧊 "
EOF
}

write_starship_theme_files catppuccin  "#e78284" "#a6d189" "#8caaee" "#e5c890" "#f4b8e4" "#ef9f76" "#99d1db" "#292c3c" "#c6d0f5" "#626880" "#c6d0f5"
write_starship_theme_files everforest  "#e67e80" "#a7c080" "#7fbbb3" "#dbbc7f" "#d699b6" "#FF9E64" "#83c092" "#4b565c" "#d3c6aa" "#2b3339" "#d3c6aa"
write_starship_theme_files gruvbox     "#cc241d" "#98971a" "#3c8588" "#d79921" "#b16286" "#d65d0e" "#689d6a" "#3c3836" "#fbf1c7" "#282828" "#d5c4a1"
write_starship_theme_files kanagawa    "#C34043" "#76946A" "#7E9CD8" "#FF9E3B" "#957FB8" "#FFA066" "#7FB4CA" "#16161D" "#DCD7BA" "#1F1F28" "#DCD7BA"
write_starship_theme_files matte-black "#D35F5F" "#FFC107" "#e68e0d" "#b91c1c" "#D35F5F" "#FFA066" "#bebebe" "#333333" "#bebebe" "#121212" "#bebebe"
write_starship_theme_files nord        "#BF616A" "#A3BE8C" "#81A1C1" "#EBCB8B" "#B48EAD" "#D08770" "#88C0D0" "#3B4252" "#E5E9F0" "#2E3440" "#D8DEE9"
write_starship_theme_files osaka-jade  "#FF5345" "#549e6a" "#509475" "#459451" "#D2689C" "#E5C736" "#2DD5B7" "#23372B" "#F6F5DD" "#111c18" "#C1C497"
write_starship_theme_files ristretto   "#fd6883" "#adda78" "#f38d70" "#f9cc6c" "#a8a9eb" "#FFA066" "#85dacc" "#2c2525" "#e6d9db" "#2c2525" "#e6d9db"
write_starship_theme_files rose-pine   "#b4637a" "#286983" "#56949f" "#ea9d34" "#907aa9" "#fe640b" "#d7827e" "#f2e9e1" "#575279" "#faf4ed" "#575279"
write_starship_theme_files tokyo-night "#F93357" "#9ECE6A" "#7AA2F7" "#E0AF68" "#BB9AF7" "#FF9E64" "#2AC3DE" "#383E5A" "#C0CAF5" "#1A1B26" "#A9B1D6"

echo "Generated starship.toml + starship-plain.toml for 10 themes."
```

Run it: `bash /tmp/gen-starship-themes.sh`, then delete the script (`rm /tmp/gen-starship-themes.sh`) — only the 20 generated files under `themes/*/` get added to git.

- [ ] **Step 4: Wire the two copies into `omawsl_theme_apply` in `bin/omawsl-sub/theme.sh`**

Add these two lines right before the existing `source "$theme_dir/vscode.sh"` line inside `omawsl_theme_apply`:

```bash
  cp "$theme_dir/starship.toml" "$HOME/.config/starship.toml"
  cp "$theme_dir/starship-plain.toml" "$HOME/.config/starship-plain.toml"

  # shellcheck source=/dev/null
  source "$theme_dir/vscode.sh"
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bats tests/theme_files_test.bats tests/omawsl_cli_test.bats`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add themes/*/starship.toml themes/*/starship-plain.toml bin/omawsl-sub/theme.sh tests/theme_files_test.bats tests/omawsl_cli_test.bats
git commit -m "feat: recolor starship to match omawsl's 10 color themes"
```

---

## Task 4: Register starship in the orphan-tools update registry

**Files:**
- Modify: `bin/omawsl-sub/orphan-tools.sh`
- Test: `tests/omawsl_orphan_tools_test.bats`

**Interfaces:**
- Consumes: `omawsl_starship_install_steps` (Task 1).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing tests**

Add to `tests/omawsl_orphan_tools_test.bats`:

```bash
@test "omawsl_orphan_tool_slugs includes starship" {
  run omawsl_orphan_tool_slugs
  [ "$status" -eq 0 ]
  [[ "$output" == *"starship"* ]]
  [ "$(omawsl_orphan_tool_slugs | wc -l)" -eq 9 ]
}

@test "omawsl_orphan_tool_label returns Starship directly" {
  [ "$(omawsl_orphan_tool_label starship)" = "Starship" ]
}

@test "omawsl_orphan_tool_installed checks starship via command -v" {
  stub_hide_command starship
  run omawsl_orphan_tool_installed starship
  [ "$status" -ne 0 ]
  stub_command starship
  run omawsl_orphan_tool_installed starship
  [ "$status" -eq 0 ]
}

@test "omawsl_orphan_tool_version_installed extracts starship's version" {
  starship() { echo "starship 1.26.0"; }
  export -f starship
  [ "$(omawsl_orphan_tool_version_installed starship)" = "1.26.0" ]
}

@test "omawsl_orphan_tool_version_latest resolves starship via the GitHub releases API" {
  stub_command_output_for curl "api.github.com/repos/starship/starship" '{"tag_name": "v1.99.0"}'
  [ "$(omawsl_orphan_tool_version_latest starship)" = "1.99.0" ]
}

@test "omawsl_orphan_tool_apply_update reinstalls starship via its install steps" {
  omawsl_starship_install_steps() { echo "starship-reinstalled" >> "$STUB_LOG"; }
  export -f omawsl_starship_install_steps
  run omawsl_orphan_tool_apply_update starship
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"starship-reinstalled"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/omawsl_orphan_tools_test.bats`
Expected: FAIL — `starship` isn't a recognized slug anywhere in `orphan-tools.sh` yet.

- [ ] **Step 3: Add the `starship` slug to every case statement in `bin/omawsl-sub/orphan-tools.sh`**

```bash
omawsl_orphan_tool_slugs() {
  printf '%s\n' zellij lazydocker starship opencode claude codex antigravity gh-copilot aws
}
```

```bash
omawsl_orphan_tool_label() {
  case "$1" in
    zellij) echo "Zellij" ;;
    lazydocker) echo "LazyDocker" ;;
    starship) echo "Starship" ;;
    opencode|claude|codex|antigravity|gh-copilot|aws) omawsl_item_label "$1" ;;
    *) return 1 ;;
  esac
}
```

```bash
omawsl_orphan_tool_installed() {
  local slug="$1"
  case "$slug" in
    zellij) command -v zellij &>/dev/null ;;
    lazydocker) command -v lazydocker &>/dev/null ;;
    starship) command -v starship &>/dev/null ;;
    opencode) command -v opencode &>/dev/null ;;
    claude) command -v claude &>/dev/null ;;
    codex) command -v codex &>/dev/null ;;
    antigravity) command -v agy &>/dev/null ;;
    gh-copilot) command -v copilot &>/dev/null ;;
    aws) command -v aws &>/dev/null ;;
    *) return 1 ;;
  esac
}
```

```bash
omawsl_orphan_tool_version_installed() {
  local slug="$1"
  case "$slug" in
    zellij) omawsl_orphan_extract_semver "$(zellij --version 2>/dev/null || true)" ;;
    lazydocker) omawsl_orphan_extract_semver "$(lazydocker --version 2>/dev/null || true)" ;;
    starship) omawsl_orphan_extract_semver "$(starship --version 2>/dev/null || true)" ;;
    opencode) omawsl_orphan_extract_semver "$(opencode --version 2>/dev/null || true)" ;;
    claude) omawsl_orphan_extract_semver "$(claude --version 2>/dev/null || true)" ;;
    codex) omawsl_orphan_extract_semver "$(codex --version 2>/dev/null || true)" ;;
    antigravity) omawsl_orphan_extract_semver "$(agy --version 2>/dev/null || true)" ;;
    gh-copilot) omawsl_orphan_extract_semver "$(copilot --version 2>/dev/null || true)" ;;
    aws) omawsl_orphan_extract_semver "$(aws --version 2>/dev/null || true)" ;;
    *) return 1 ;;
  esac
}
```

```bash
omawsl_orphan_tool_version_latest() {
  local slug="$1"
  case "$slug" in
    zellij) omawsl_orphan_latest_from_github zellij-org/zellij ;;
    lazydocker) omawsl_orphan_latest_from_github jesseduffield/lazydocker ;;
    starship) omawsl_orphan_latest_from_github starship/starship ;;
    opencode) omawsl_orphan_latest_from_github anomalyco/opencode ;;
    claude) omawsl_orphan_latest_from_github anthropics/claude-code ;;
    codex) omawsl_orphan_latest_from_npm "@openai/codex" ;;
    antigravity) echo "" ;;
    gh-copilot) omawsl_orphan_latest_from_npm "@github/copilot" ;;
    aws) omawsl_orphan_latest_from_github_tags aws/aws-cli ;;
    *) return 1 ;;
  esac
}
```

```bash
omawsl_orphan_tool_apply_update() {
  local slug="$1"
  local label; label="$(omawsl_orphan_tool_label "$slug")"
  local ok=1
  case "$slug" in
    zellij) omawsl_zellij_install_steps || ok=0 ;;
    lazydocker) omawsl_lazydocker_install_steps || ok=0 ;;
    starship) omawsl_starship_install_steps || ok=0 ;;
    opencode) omawsl_opencode_install_steps || ok=0 ;;
    claude) omawsl_claude_cli_install_steps || ok=0 ;;
    codex) omawsl_codex_cli_install_steps || ok=0 ;;
    antigravity) omawsl_antigravity_cli_install_steps || ok=0 ;;
    gh-copilot) omawsl_gh_copilot_install_steps || ok=0 ;;
    aws) omawsl_aws_cli_install_steps || ok=0 ;;
    *) echo "omawsl: unknown orphan tool slug '$slug'" >&2; return 1 ;;
  esac
  if [[ "$ok" -eq 0 ]]; then
    echo "omawsl: failed to update $label - skipping, continuing with the rest."
  else
    echo "omawsl: updated $label."
  fi
}
```

(`apps-terminal.sh`, which defines `omawsl_starship_install_steps`, is already sourced at the top of this file — no new `source` line needed.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/omawsl_orphan_tools_test.bats`
Expected: PASS, all tests including pre-existing ones for the other 8 slugs.

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/orphan-tools.sh tests/omawsl_orphan_tools_test.bats
git commit -m "feat: check starship for updates via the orphan-tools registry"
```

---

## Task 5: Doctor visibility for a missing starship install

**Files:**
- Modify: `bin/omawsl-sub/doctor.sh`
- Test: `tests/omawsl_doctor_test.bats`

**Interfaces:**
- Produces: `omawsl_doctor_starship_missing()`, consumed only by `omawsl_doctor` in this same file.

- [ ] **Step 1: Write the failing tests**

Add to `tests/omawsl_doctor_test.bats`:

```bash
@test "omawsl_doctor reports starship missing and how to fix it" {
  stub_hide_command starship
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"[PENDING] Starship not installed"* ]]
  [[ "$output" == *"omawsl migrate"* ]]
}

@test "omawsl_doctor stays silent about starship when it is installed" {
  stub_command starship
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" != *"Starship"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/omawsl_doctor_test.bats`
Expected: FAIL — `omawsl_doctor` never mentions starship at all yet.

- [ ] **Step 3: Add `omawsl_doctor_starship_missing` and call it from `omawsl_doctor`**

Add this function right after `omawsl_doctor_docker_proxy_stale`:

```bash
# omawsl_doctor_starship_missing
# Unlike zellij (never promised universal, just always installed in
# practice), starship is explicitly meant to be on every machine after
# design spec docs/superpowers/specs/2026-08-09-starship-default-prompt-design.md
# ships, so a silently failed install (offline box, corp proxy blocking
# GitHub) needs to surface somewhere - doctor is that somewhere.
omawsl_doctor_starship_missing() {
  ! command -v starship &>/dev/null
}
```

In `omawsl_doctor`'s body, add this block after the existing Docker `if/elif` chain (at the very end of the function, before its closing `}`):

```bash
  if omawsl_doctor_starship_missing; then
    echo
    echo "Starship:"
    echo "  [PENDING] Starship not installed - prompt is using the legacy fallback. Re-run: omawsl migrate"
  fi
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/omawsl_doctor_test.bats`
Expected: PASS, all tests including pre-existing ones.

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/doctor.sh tests/omawsl_doctor_test.bats
git commit -m "feat: doctor reports a missing starship install"
```

---

## Task 6: Migrate existing installs, preserving theme continuity

**Files:**
- Create: `migrations/1786305600.sh`
- Create: `tests/migration_1786305600_test.bats`

**Interfaces:**
- Consumes: `omawsl_install_starship`, `omawsl_install_starship_config` (Task 1); `omawsl_theme_is_valid`, `omawsl_theme_apply` (Task 3/`bin/omawsl-sub/theme.sh`, pre-existing).

**Important correctness detail found while researching this task:** `configs/zellij.kdl` (the file `omawsl_install_zellij_config` deploys at install time, before anyone ever runs `omawsl theme`) already ships with `theme "tokyo-night"` as its stock reference line — it is **not** a placeholder that `omawsl_theme_is_valid` would reject. That reference alone is *not* proof the user ever actually ran `omawsl theme <name>`: only `omawsl_theme_apply` ever creates the real theme file at `~/.config/zellij/themes/<name>.kdl`, which is what zellij actually needs to render that theme. So the migration must check **both** that the referenced name is valid **and** that its theme file actually exists — checking the reference alone would wrongly theme starship for every install that never touched theming at all, which is the opposite of what preserving continuity means here.

- [ ] **Step 1: Write the failing tests**

Create `tests/migration_1786305600_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  stub_command sudo
  stub_command tar
  stub_hide_command starship
}

@test "installs starship and the default plain config when starship isn't already present" {
  run bash "$REPO_ROOT/migrations/1786305600.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo install -m 0755 /tmp/starship /usr/local/bin/starship"* ]]
  diff "$HOME/.config/starship-plain.toml" "$REPO_ROOT/configs/starship-plain.toml"
}

@test "skips the starship install when it's already present" {
  stub_command starship
  run bash "$REPO_ROOT/migrations/1786305600.sh"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"/usr/local/bin/starship"* ]]
}

@test "no-ops the theme re-apply step cleanly when zellij was never installed/configured at all" {
  run bash "$REPO_ROOT/migrations/1786305600.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/starship.toml" ]
}

@test "leaves the plain un-themed defaults in place for an install that never actually ran 'omawsl theme', even though config.kdl still names the stock tokyo-night reference" {
  mkdir -p "$HOME/.config/zellij"
  cp "$REPO_ROOT/configs/zellij.kdl" "$HOME/.config/zellij/config.kdl"
  run bash "$REPO_ROOT/migrations/1786305600.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/starship.toml" ]
}

@test "re-applies the theme when the user genuinely ran 'omawsl theme' before (its real theme file exists)" {
  mkdir -p "$HOME/.config/zellij/themes"
  cp "$REPO_ROOT/configs/zellij.kdl" "$HOME/.config/zellij/config.kdl"
  sed -i 's/theme ".*"/theme "rose-pine"/g' "$HOME/.config/zellij/config.kdl"
  cp "$REPO_ROOT/themes/rose-pine/zellij.kdl" "$HOME/.config/zellij/themes/rose-pine.kdl"
  run bash "$REPO_ROOT/migrations/1786305600.sh"
  [ "$status" -eq 0 ]
  diff "$HOME/.config/starship.toml" "$REPO_ROOT/themes/rose-pine/starship.toml"
  diff "$HOME/.config/starship-plain.toml" "$REPO_ROOT/themes/rose-pine/starship-plain.toml"
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/migration_1786305600_test.bats`
Expected: FAIL — `migrations/1786305600.sh` doesn't exist yet.

- [ ] **Step 3: Create `migrations/1786305600.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=../install/terminal/apps-terminal.sh
source "$OMAWSL_ROOT_DIR/install/terminal/apps-terminal.sh"
# shellcheck source=../bin/omawsl-sub/theme.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/theme.sh"

# Starship as the default prompt (design spec
# docs/superpowers/specs/2026-08-09-starship-default-prompt-design.md):
# installs the binary and the un-themed plain-mode config for existing
# installs, same as a fresh install's apps-terminal.sh already does.
omawsl_install_starship
omawsl_install_starship_config

# omawsl_starship_migrate_active_theme
# Preserves visual consistency for anyone who already picked a real
# omawsl theme. zellij is always-on and is theme.sh's first, always-
# patched target, so its config is the closest thing to a single source
# of truth for "what theme is currently active" - there's no separate
# state file for it. config.kdl's `theme "..."` reference alone isn't
# enough, though: configs/zellij.kdl ships with `theme "tokyo-night"`
# baked in from a fresh install, before any real theme file has ever been
# copied - so it names a *valid* theme even for someone who never ran
# `omawsl theme`. The real signal that it genuinely ran is that
# ~/.config/zellij/themes/<name>.kdl actually exists, since only
# omawsl_theme_apply ever creates it.
omawsl_starship_migrate_active_theme() {
  local zellij_config="$HOME/.config/zellij/config.kdl"
  [[ -f "$zellij_config" ]] || return 0
  local active_theme
  active_theme="$(grep -oP '(?<=theme ")[^"]+' "$zellij_config" | head -n1)"
  [[ -n "$active_theme" ]] || return 0
  omawsl_theme_is_valid "$active_theme" || return 0
  [[ -f "$HOME/.config/zellij/themes/$active_theme.kdl" ]] || return 0
  omawsl_theme_apply "$active_theme"
}

omawsl_starship_migrate_active_theme
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/migration_1786305600_test.bats`
Expected: PASS.

- [ ] **Step 5: Run the full suite once**

Run: `bats tests/`
Expected: PASS across the whole suite — confirms nothing in Tasks 1-6 regressed an unrelated area (e.g. `omawsl_migrate_test.bats`'s pending-migration discovery, which scans `migrations/*.sh` automatically and needs no separate registration).

- [ ] **Step 6: Commit**

```bash
git add migrations/1786305600.sh tests/migration_1786305600_test.bats
git commit -m "feat: migrate existing installs onto starship, preserving their active theme"
```

---

## Manual End-to-End Verification (after all 6 tasks)

Once the full suite is green, verify on a real WSL2 box per this project's established convention (`docs/superpowers/plans/roadmap.md`):

1. Fresh install (`bash boot.sh` or `install.sh` in a clean WSL2 distro): confirm starship renders on first shell open, with no `~/.config/starship.toml` present (built-in default) and `~/.config/starship-plain.toml` present but unused.
2. Run `omawsl theme tokyo-night`: confirm the prompt recolors, and `~/.config/starship.toml`/`starship-plain.toml` now match `themes/tokyo-night/`.
3. Simulate an existing install: revert `configs/bashrc` to the pre-Task-2 state, open a shell to confirm the legacy PS1, then re-apply and run `omawsl migrate` — confirm starship appears without re-running the full installer.
4. Set `OMAWSL_FONT_MODE` to Cascadia Mono in `choices.env`, open a new shell: confirm no Nerd Font glyphs appear (emoji/plain symbols only).
5. `omawsl doctor` with starship's binary manually removed (`sudo rm /usr/local/bin/starship`): confirm the `[PENDING] Starship not installed` line appears, and that a new shell falls back to the legacy PS1 without error.
6. `omawsl update`: confirm starship appears in the orphan-tools update picker with a real installed/latest version comparison.
