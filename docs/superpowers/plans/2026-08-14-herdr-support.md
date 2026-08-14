# Herdr Support Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Herdr (herdrdev/herdr, a terminal multiplexer for AI coding agents) as a tenth entry in omawsl's "Editors & AI tooling" picker, fully wired through install, uninstall, doctor, and orphan-tool update tracking - following the exact template the Antigravity CLI addition established.

**Architecture:** One new install script (`install/terminal/app-herdr.sh`) and one new uninstall script (`uninstall/app-herdr.sh`), both shaped identically to `app-claude-cli.sh`/`app-antigravity-cli.sh`. Every other change is a one-line-per-file addition to an existing registry, dispatch table, or picker list - no new subsystem, no new abstraction.

**Tech Stack:** Bash (`set -euo pipefail`), bats for tests, `gum` for interactive pickers, `curl` for the official installer.

## Global Constraints

- Install command: `curl -fsSL https://herdr.dev/install.sh | bash` (piped through `bash`, matching this repo's existing convention for Claude Code CLI/opencode/Antigravity CLI - not the `sh` from Herdr's own docs).
- Herdr's installer places the binary at `$HOME/.local/bin/herdr` - already on `$PATH`, no PATH wiring needed.
- Idempotency guard for install: `command -v herdr`.
- Uninstall removes exactly `$HOME/.local/bin/herdr` and `$HOME/.config/herdr` (Herdr's XDG config/session-state directory).
- Picker label is exactly `"Herdr"` (bare, no "CLI" suffix) everywhere it appears (picker option, `items.sh` label, orphan-tool label).
- Orphan-tool slug is `herdr`; installed-version via `herdr --version` through the existing `omawsl_orphan_extract_semver` helper; latest-version via the existing `omawsl_orphan_latest_from_github` helper against `herdrdev/herdr`.
- No Windows-side dependency - do not touch `install/windows-prereq-checklist.sh` or `docs/windows-setup.md`.
- Every new/modified test uses the existing `tests/helpers/stubs.bash` stubbing helpers; no test may hit the real network.
- Follow TDD: write the failing test, watch it fail, then write the minimal implementation.

---

### Task 1: Herdr install script

**Files:**
- Create: `install/terminal/app-herdr.sh`
- Test: `tests/app_herdr_test.bats`

**Interfaces:**
- Produces: `omawsl_herdr_install_steps()` (no args, no guard - re-runs the curl installer unconditionally) and `omawsl_install_herdr()` (no args, guarded: checks `OMAWSL_EDITORS` for `"Herdr"`, then `command -v herdr`). Both consumed by Task 4 (`install/terminal.sh`), Task 5 (`bin/omawsl-sub/install.sh`), and Task 6 (`bin/omawsl-sub/orphan-tools.sh`).
- Consumes: `omawsl_list_has` (from `install/lib.sh`, already sourced by every `app-*.sh` script).

- [ ] **Step 1: Write the failing test**

Create `tests/app_herdr_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-herdr.sh"
  stub_command curl
}

@test "no-ops entirely when Herdr isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_herdr
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "installs via the official installer when not already present" {
  export OMAWSL_EDITORS="Herdr"
  stub_hide_command herdr
  run omawsl_install_herdr
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://herdr.dev/install.sh"* ]]
}

@test "no-ops when already installed" {
  export OMAWSL_EDITORS="Herdr"
  stub_command herdr
  run omawsl_install_herdr
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "omawsl_herdr_install_steps runs unconditionally, even if herdr is already installed" {
  stub_command herdr
  run omawsl_herdr_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"herdr.dev/install.sh"* ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/app_herdr_test.bats`
Expected: FAIL - `install/terminal/app-herdr.sh: No such file or directory`

- [ ] **Step 3: Write the minimal implementation**

Create `install/terminal/app-herdr.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_herdr_install_steps
# The actual install command, no guard - same split rationale as
# omawsl_claude_cli_install_steps/omawsl_antigravity_cli_install_steps.
# Herdr (herdrdev/herdr) is a terminal multiplexer for AI coding agents -
# ships its own native curl installer (confirmed via herdr.dev/install.sh),
# which places the binary at $HOME/.local/bin/herdr (already on PATH,
# same as Claude Code CLI's own installer) - no npm/mise involved.
omawsl_herdr_install_steps() {
  curl -fsSL https://herdr.dev/install.sh | bash
}

# omawsl_install_herdr
# Herdr - purely WSL-side, no Windows dependency, same shape as
# app-claude-cli.sh. Idempotent via a command -v guard on `herdr`, the
# binary the installer places on PATH.
omawsl_install_herdr() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Herdr"; then
    return 0
  fi

  if command -v herdr &>/dev/null; then
    return 0
  fi

  omawsl_herdr_install_steps
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_herdr
fi
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/app_herdr_test.bats`
Expected: PASS (4 tests)

- [ ] **Step 5: Commit**

```bash
git add install/terminal/app-herdr.sh tests/app_herdr_test.bats
git commit -m "feat: add app-herdr.sh (Herdr install script)"
```

---

### Task 2: Herdr uninstall script

**Files:**
- Create: `uninstall/app-herdr.sh`
- Modify: `tests/uninstall_ai_cli_test.bats`

**Interfaces:**
- Produces: `omawsl_uninstall_herdr()` (no args, no guard). Consumed by Task 5 (`bin/omawsl-sub/uninstall.sh`).
- Consumes: nothing beyond `install/lib.sh` (sourced for consistency with the other `uninstall/app-*.sh` scripts, even though this function doesn't call any of its helpers).

- [ ] **Step 1: Write the failing test**

Modify `tests/uninstall_ai_cli_test.bats` - add the new source line to `setup()` and a new `@test` block:

```bash
setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/app-claude-cli.sh"
  source "$REPO_ROOT/uninstall/app-codex-cli.sh"
  source "$REPO_ROOT/uninstall/app-antigravity-cli.sh"
  source "$REPO_ROOT/uninstall/app-herdr.sh"
}
```

Add at the end of the file:

```bash

@test "omawsl_uninstall_herdr removes the binary and its config dir" {
  mkdir -p "$HOME/.local/bin" "$HOME/.config/herdr"
  touch "$HOME/.local/bin/herdr"
  run omawsl_uninstall_herdr
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.local/bin/herdr" ]
  [ ! -d "$HOME/.config/herdr" ]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/uninstall_ai_cli_test.bats`
Expected: FAIL - `uninstall/app-herdr.sh: No such file or directory`

- [ ] **Step 3: Write the minimal implementation**

Create `uninstall/app-herdr.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_herdr
# Inverse of install/terminal/app-herdr.sh. Herdr's own installer places
# the binary at $HOME/.local/bin/herdr; its session/config state lives
# under $HOME/.config/herdr (session.json, per-named-session
# subdirectories, optional pane history - confirmed via herdr.dev's own
# config-reference docs). Removing both is a complete uninstall - Herdr's
# own CLI has no built-in self-uninstall subcommand to defer to.
omawsl_uninstall_herdr() {
  rm -f "$HOME/.local/bin/herdr"
  rm -rf "$HOME/.config/herdr"
  echo "omawsl: Herdr removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_herdr
fi
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/uninstall_ai_cli_test.bats`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add uninstall/app-herdr.sh tests/uninstall_ai_cli_test.bats
git commit -m "feat: add uninstall/app-herdr.sh"
```

---

### Task 3: Register the `herdr` slug in items.sh

**Files:**
- Modify: `bin/omawsl-sub/items.sh`
- Modify: `tests/omawsl_uninstall_command_test.bats`

**Interfaces:**
- Consumes: nothing new.
- Produces: `omawsl_item_category herdr` → `"editor"`, `omawsl_item_label herdr` → `"Herdr"`, `herdr` present in `omawsl_item_slugs editor`'s output. Consumed by Task 5 (`bin/omawsl-sub/install.sh`, `bin/omawsl-sub/uninstall.sh`) and Task 6 (`bin/omawsl-sub/orphan-tools.sh`'s label reuse).

- [ ] **Step 1: Write the failing test**

In `tests/omawsl_uninstall_command_test.bats`, update the three registry tests:

```bash
@test "omawsl_item_category classifies every known slug correctly" {
  [[ "$(omawsl_item_category go)" == "language" ]]
  [[ "$(omawsl_item_category terraform)" == "language" ]]
  [[ "$(omawsl_item_category azure)" == "cloud" ]]
  [[ "$(omawsl_item_category aws)" == "cloud" ]]
  [[ "$(omawsl_item_category gcp)" == "cloud" ]]
  [[ "$(omawsl_item_category vscode)" == "editor" ]]
  [[ "$(omawsl_item_category gh-copilot)" == "editor" ]]
  [[ "$(omawsl_item_category herdr)" == "editor" ]]
  [[ "$(omawsl_item_category mysql)" == "storage" ]]
  [[ "$(omawsl_item_category docker)" == "docker" ]]
  ! omawsl_item_category not-a-real-slug
}

@test "omawsl_item_label maps every slug to its exact picker label" {
  [[ "$(omawsl_item_label ruby)" == "Ruby on Rails" ]]
  [[ "$(omawsl_item_label vscode)" == "VS Code" ]]
  [[ "$(omawsl_item_label gh-copilot)" == "GitHub Copilot CLI" ]]
  [[ "$(omawsl_item_label herdr)" == "Herdr" ]]
  [[ "$(omawsl_item_label postgresql)" == "PostgreSQL" ]]
  [[ "$(omawsl_item_label azure)" == "Azure CLI" ]]
  [[ "$(omawsl_item_label aws)" == "AWS CLI" ]]
  [[ "$(omawsl_item_label gcp)" == "GCP CLI" ]]
}

@test "omawsl_item_slugs lists all 9 language slugs, 3 cloud slugs, 9 editor slugs, 3 storage slugs" {
  [[ "$(omawsl_item_slugs language | wc -l)" -eq 9 ]]
  [[ "$(omawsl_item_slugs language)" != *"azure"* ]]
  [[ "$(omawsl_item_slugs cloud | wc -l)" -eq 3 ]]
  [[ "$(omawsl_item_slugs cloud)" == *"azure"* ]]
  [[ "$(omawsl_item_slugs cloud)" == *"aws"* ]]
  [[ "$(omawsl_item_slugs cloud)" == *"gcp"* ]]
  [[ "$(omawsl_item_slugs editor | wc -l)" -eq 9 ]]
  [[ "$(omawsl_item_slugs editor)" == *"herdr"* ]]
  [[ "$(omawsl_item_slugs storage | wc -l)" -eq 3 ]]
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/omawsl_uninstall_command_test.bats`
Expected: FAIL - the three tests above fail (`herdr` not classified as `editor`, `omawsl_item_label herdr` prints nothing, editor slug count is 8 not 9)

- [ ] **Step 3: Write the minimal implementation**

In `bin/omawsl-sub/items.sh`, modify `omawsl_item_category`:

```bash
    vscode|neovim|opencode|cursor|claude|codex|gh-copilot|antigravity|herdr) echo "editor" ;;
```

Modify `omawsl_item_label` - add this line right after the `antigravity) echo "Antigravity CLI" ;;` line:

```bash
    herdr) echo "Herdr" ;;
```

Modify `omawsl_item_slugs` - update the `editor)` line:

```bash
    editor) printf '%s\n' vscode neovim opencode cursor claude codex gh-copilot antigravity herdr ;;
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/omawsl_uninstall_command_test.bats`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/items.sh tests/omawsl_uninstall_command_test.bats
git commit -m "feat: register the herdr slug in items.sh"
```

---

### Task 4: Wire Herdr into the picker and the boot-time terminal script sequence

**Files:**
- Modify: `install/first-run-choices.sh`
- Modify: `install/terminal.sh`
- Modify: `tests/terminal_test.bats`

**Interfaces:**
- Consumes: `omawsl_install_herdr` (Task 1, sourced by `install/terminal.sh`).
- Produces: `"Herdr"` now appears as a selectable option in the `OMAWSL_EDITORS` picker, and `install/terminal.sh` runs `terminal/app-herdr.sh` as the last step of a fresh install.

- [ ] **Step 1: Write the failing test**

In `tests/terminal_test.bats`, update the expected order in the `"runs every terminal script in the documented fixed order"` test:

```bash
  actual_order="$(echo "$output" | grep "^omawsl: running" | sed 's/^omawsl: running //')"
  expected_order="terminal/required/app-gum.sh
terminal/identification.sh
terminal/a-shell.sh
terminal/apps-terminal.sh
terminal/docker.sh
terminal/libraries.sh
terminal/mise.sh
terminal/select-dev-language.sh
terminal/cloud-tools.sh
terminal/cloud-clis.sh
terminal/select-dev-storage.sh
terminal/app-vscode.sh
terminal/app-neovim.sh
terminal/app-opencode.sh
terminal/app-cursor.sh
terminal/app-claude-cli.sh
terminal/app-codex-cli.sh
terminal/app-gh-copilot.sh
terminal/app-antigravity-cli.sh
terminal/app-herdr.sh"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/terminal_test.bats`
Expected: FAIL - `actual_order` is missing the trailing `terminal/app-herdr.sh` line

- [ ] **Step 3: Write the minimal implementation**

In `install/first-run-choices.sh`, update the `OMAWSL_EDITORS` prompt:

```bash
  OMAWSL_EDITORS="$(omawsl_prompt_multi "Editors & AI tooling (space to select, enter to confirm)" \
    "VS Code" "Neovim" "opencode" "Cursor" \
    "Claude Code CLI" "Codex CLI" "GitHub Copilot CLI" "Antigravity CLI" "Herdr")"
```

In `install/terminal.sh`, add `"terminal/app-herdr.sh"` as the last entry of `OMAWSL_TERMINAL_SCRIPTS`:

```bash
  "terminal/app-antigravity-cli.sh"
  "terminal/app-herdr.sh"
)
```

And add the matching entry to the `SCRIPT_FUNCTIONS` map, right after the Antigravity CLI line:

```bash
    ["terminal/app-antigravity-cli.sh"]="omawsl_install_antigravity_cli"
    ["terminal/app-herdr.sh"]="omawsl_install_herdr"
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/terminal_test.bats tests/first_run_choices_test.bats`
Expected: PASS (both files)

- [ ] **Step 5: Commit**

```bash
git add install/first-run-choices.sh install/terminal.sh tests/terminal_test.bats
git commit -m "feat: add Herdr to the editors picker and boot-time terminal sequence"
```

---

### Task 5: Wire Herdr into `omawsl install`/`omawsl uninstall`/`omawsl doctor`

**Files:**
- Modify: `bin/omawsl-sub/install.sh`
- Modify: `bin/omawsl-sub/uninstall.sh`
- Modify: `bin/omawsl-sub/doctor.sh`
- Modify: `tests/omawsl_install_command_test.bats`
- Modify: `tests/install_test.bats`

**Interfaces:**
- Consumes: `omawsl_install_herdr`/`omawsl_herdr_install_steps` (Task 1), `omawsl_uninstall_herdr` (Task 2), `omawsl_item_label`/`omawsl_item_category` for `herdr` (Task 3).
- Produces: `omawsl install editor herdr`, `omawsl uninstall herdr`, and `omawsl doctor` all recognize `herdr`.

- [ ] **Step 1: Write the failing test**

In `tests/omawsl_install_command_test.bats`, update `setup()`'s hide list and add a new test:

```bash
  stub_hide_command docker terraform az gcloud aws code cursor claude codex agy opencode copilot herdr
```

Add at the end of the file:

```bash

@test "omawsl install editor herdr - installs herdr directly and merges it into OMAWSL_EDITORS" {
  stub_command curl
  run omawsl_install_command editor herdr
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "Herdr" ]]
  [[ "$(stub_calls)" == *"curl -fsSL https://herdr.dev/install.sh"* ]]
}
```

Also add `herdr` to the hide list in `tests/install_test.bats`'s `setup()`:

```bash
  stub_hide_command docker terraform az gcloud aws lazydocker zellij lazygit fastfetch starship code cursor claude codex agy opencode copilot herdr
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/omawsl_install_command_test.bats`
Expected: FAIL - `omawsl install editor herdr` reports `'herdr' isn't in the 'editor' category` or the install loop never calls `omawsl_install_herdr` (function doesn't exist in `bin/omawsl-sub/install.sh`'s sourced scope yet)

- [ ] **Step 3: Write the minimal implementation**

In `bin/omawsl-sub/install.sh`, inside `omawsl_install_apply_editor`, add `app-herdr` to the sourcing loop:

```bash
  for f in app-vscode app-neovim app-opencode app-cursor app-claude-cli app-codex-cli app-gh-copilot app-antigravity-cli app-herdr; do
```

And add the isolated call, right after the Antigravity CLI line:

```bash
  omawsl_install_antigravity_cli || echo "omawsl: failed to install Antigravity CLI - skipping, continuing with the rest." >&2
  omawsl_install_herdr || echo "omawsl: failed to install Herdr - skipping, continuing with the rest." >&2
```

In `bin/omawsl-sub/uninstall.sh`, add a `herdr)` case in `omawsl_uninstall_dispatch`, right after the `antigravity)` block:

```bash
    herdr)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-herdr.sh"
      omawsl_uninstall_herdr
      ;;
```

In `bin/omawsl-sub/doctor.sh`, add a `herdr)` case to `omawsl_doctor_editor_installed`, right after the `gh-copilot)` line:

```bash
    gh-copilot) command -v copilot &>/dev/null ;;
    herdr) command -v herdr &>/dev/null ;;
    *) return 1 ;;
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/omawsl_install_command_test.bats tests/omawsl_uninstall_command_test.bats tests/omawsl_doctor_test.bats tests/install_test.bats`
Expected: PASS (all four files)

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/install.sh bin/omawsl-sub/uninstall.sh bin/omawsl-sub/doctor.sh \
        tests/omawsl_install_command_test.bats tests/install_test.bats
git commit -m "feat: wire herdr into omawsl install/uninstall/doctor dispatch"
```

---

### Task 6: Register Herdr as an orphan tool (`omawsl update` tracking)

**Files:**
- Modify: `bin/omawsl-sub/orphan-tools.sh`
- Modify: `tests/omawsl_orphan_tools_test.bats`

**Interfaces:**
- Consumes: `omawsl_herdr_install_steps` (Task 1), `omawsl_item_label herdr` (Task 3), `omawsl_orphan_extract_semver`/`omawsl_orphan_latest_from_github` (already defined earlier in this same file).
- Produces: `herdr` is a full 10th entry across `omawsl_orphan_tool_slugs`, `omawsl_orphan_tool_label`, `omawsl_orphan_tool_installed`, `omawsl_orphan_tool_version_installed`, `omawsl_orphan_tool_version_latest`, and `omawsl_orphan_tool_apply_update`.

- [ ] **Step 1: Write the failing test**

In `tests/omawsl_orphan_tools_test.bats`, update the slug-count test:

```bash
@test "omawsl_orphan_tool_slugs lists all 10 orphan tools" {
  run omawsl_orphan_tool_slugs
  [ "$status" -eq 0 ]
  [[ "$output" == *"zellij"* ]]
  [[ "$output" == *"lazydocker"* ]]
  [[ "$output" == *"starship"* ]]
  [[ "$output" == *"opencode"* ]]
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *"codex"* ]]
  [[ "$output" == *"antigravity"* ]]
  [[ "$output" == *"gh-copilot"* ]]
  [[ "$output" == *"aws"* ]]
  [[ "$output" == *"herdr"* ]]
  [ "$(omawsl_orphan_tool_slugs | wc -l)" -eq 10 ]
}
```

Update the label-reuse test:

```bash
@test "omawsl_orphan_tool_label returns Zellij/LazyDocker directly and reuses items.sh for the rest" {
  [ "$(omawsl_orphan_tool_label zellij)" = "Zellij" ]
  [ "$(omawsl_orphan_tool_label lazydocker)" = "LazyDocker" ]
  [ "$(omawsl_orphan_tool_label codex)" = "$(omawsl_item_label codex)" ]
  [ "$(omawsl_orphan_tool_label gh-copilot)" = "GitHub Copilot CLI" ]
  [ "$(omawsl_orphan_tool_label aws)" = "AWS CLI" ]
  [ "$(omawsl_orphan_tool_label herdr)" = "Herdr" ]
}
```

Update the exists-check test:

```bash
@test "every function omawsl_orphan_tool_apply_update dispatches to actually exists" {
  for fn in omawsl_zellij_install_steps omawsl_lazydocker_install_steps \
            omawsl_starship_install_steps omawsl_opencode_install_steps \
            omawsl_claude_cli_install_steps omawsl_codex_cli_install_steps \
            omawsl_antigravity_cli_install_steps omawsl_gh_copilot_install_steps \
            omawsl_aws_cli_install_steps omawsl_herdr_install_steps; do
    declare -F "$fn" >/dev/null || { echo "missing function: $fn"; return 1; }
  done
}
```

Add four new dedicated tests, next to the Starship equivalents at the end of the file:

```bash

@test "omawsl_orphan_tool_installed checks herdr via command -v" {
  stub_hide_command herdr
  run omawsl_orphan_tool_installed herdr
  [ "$status" -ne 0 ]
  stub_command herdr
  run omawsl_orphan_tool_installed herdr
  [ "$status" -eq 0 ]
}

@test "omawsl_orphan_tool_version_installed extracts herdr's version" {
  herdr() { echo "herdr 0.8.0"; }
  export -f herdr
  [ "$(omawsl_orphan_tool_version_installed herdr)" = "0.8.0" ]
}

@test "omawsl_orphan_tool_version_latest resolves herdr via the GitHub releases API" {
  stub_command_output_for curl "api.github.com/repos/herdrdev/herdr" '{"tag_name": "v0.9.0"}'
  [ "$(omawsl_orphan_tool_version_latest herdr)" = "0.9.0" ]
}

@test "omawsl_orphan_tool_apply_update reinstalls herdr via its install steps" {
  omawsl_herdr_install_steps() { echo "herdr-reinstalled" >> "$STUB_LOG"; }
  export -f omawsl_herdr_install_steps
  run omawsl_orphan_tool_apply_update herdr
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"herdr-reinstalled"* ]]
}
```

Now widen the hermeticity hide-lists so the other `omawsl_orphan_tools_*` tests still see a clean "nothing installed" baseline now that `herdr` is a real 10th tool that could theoretically be present on the host running the suite. Using an editor with find-and-replace-all, change every occurrence of the exact string `stub_hide_command zellij lazydocker opencode claude codex agy gh copilot` (2 occurrences, in the `omawsl_orphan_tools_installed_slugs` test and the "no-ops cleanly" test) to `stub_hide_command zellij lazydocker opencode claude codex agy gh copilot herdr`; change the one occurrence of `stub_hide_command zellij lazydocker opencode claude codex agy gh copilot starship` (in the "offers to recover a missing starship" test) to `stub_hide_command zellij lazydocker opencode claude codex agy gh copilot starship herdr`; and change every occurrence of the exact string `stub_hide_command lazydocker opencode claude codex agy gh copilot` (3 occurrences, in the "skips the picker", "shows the picker, pre-selecting", and "still shows the picker when a tool is unknown" tests) to `stub_hide_command lazydocker opencode claude codex agy gh copilot herdr`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/omawsl_orphan_tools_test.bats`
Expected: FAIL - the updated/new tests fail (`herdr` absent from `omawsl_orphan_tool_slugs`, `omawsl_orphan_tool_label herdr` empty, `omawsl_herdr_install_steps` undefined, etc.)

- [ ] **Step 3: Write the minimal implementation**

In `bin/omawsl-sub/orphan-tools.sh`, add a source line for the new install script, right after the `app-gh-copilot.sh` source line near the top of the file:

```bash
# shellcheck source=../../install/terminal/app-gh-copilot.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-gh-copilot.sh"
# shellcheck source=../../install/terminal/app-herdr.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-herdr.sh"
```

Update `omawsl_orphan_tool_slugs` (and its preceding comment):

```bash
# omawsl_orphan_tool_slugs
# All 10 orphan-tool slugs, in a fixed display order.
omawsl_orphan_tool_slugs() {
  printf '%s\n' zellij lazydocker starship opencode claude codex antigravity gh-copilot aws herdr
}
```

Update `omawsl_orphan_tool_label`:

```bash
    opencode|claude|codex|antigravity|gh-copilot|aws|herdr) omawsl_item_label "$1" ;;
```

Update `omawsl_orphan_tool_installed`:

```bash
    aws) command -v aws &>/dev/null ;;
    herdr) command -v herdr &>/dev/null ;;
    *) return 1 ;;
```

Update `omawsl_orphan_tool_version_installed`:

```bash
    aws) omawsl_orphan_extract_semver "$(aws --version 2>/dev/null || true)" ;;
    herdr) omawsl_orphan_extract_semver "$(herdr --version 2>/dev/null || true)" ;;
    *) return 1 ;;
```

Update `omawsl_orphan_tool_version_latest`:

```bash
    aws) omawsl_orphan_latest_from_github_tags aws/aws-cli ;;
    herdr) omawsl_orphan_latest_from_github herdrdev/herdr ;;
    *) return 1 ;;
```

Update `omawsl_orphan_tool_apply_update`:

```bash
    aws) omawsl_aws_cli_install_steps || ok=0 ;;
    herdr) omawsl_herdr_install_steps || ok=0 ;;
    *) echo "omawsl: unknown orphan tool slug '$slug'" >&2; return 1 ;;
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/omawsl_orphan_tools_test.bats`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/orphan-tools.sh tests/omawsl_orphan_tools_test.bats
git commit -m "feat: track herdr as an orphan tool for omawsl update"
```

---

### Task 7: Update documentation

**Files:**
- Modify: `README.md`
- Modify: `docs/updating.md`
- Modify: `tests/docs_updating_test.bats`

**Interfaces:**
- Consumes: nothing (pure documentation).
- Produces: nothing consumed by later tasks - this is the last content task.

- [ ] **Step 1: Write the failing test**

In `tests/docs_updating_test.bats`, update the tool-list test:

```bash
@test "docs/updating.md lists all 8 orphan tools by name" {
  for tool in Zellij LazyDocker opencode "Claude Code CLI" "Codex CLI" "Antigravity CLI" "GitHub Copilot CLI" Herdr; do
    grep -qF "$tool" "$DOC" || { echo "missing tool: $tool"; return 1; }
  done
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bats tests/docs_updating_test.bats`
Expected: FAIL - `missing tool: Herdr`

- [ ] **Step 3: Write the minimal implementation**

In `docs/updating.md`, update the "The rest" section - change the count and append `Herdr` to the bullet list:

```markdown
## The rest: `omawsl update`

Ten tools have no update command of their own - no apt package, no mise tool, nothing to
run yourself. `omawsl update` checks each one that's currently installed against its real
latest release, then offers a picker (pre-checked for anything outdated) to bring them
current:

- Zellij
- LazyDocker
- Starship
- opencode
- Claude Code CLI
- Codex CLI
- Antigravity CLI
- GitHub Copilot CLI
- AWS CLI
- Herdr
```

In `README.md`, update the "What you get" paragraph's editors/AI-tooling list:

```markdown
CLI, containerized storage (MySQL, Redis, PostgreSQL), and your choice of editors/AI tooling
(VS Code, Neovim, opencode, Cursor, Claude Code CLI, Codex CLI, GitHub Copilot CLI, Antigravity CLI, Herdr).
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/docs_updating_test.bats tests/readme_test.bats`
Expected: PASS (both files)

- [ ] **Step 5: Commit**

```bash
git add README.md docs/updating.md tests/docs_updating_test.bats
git commit -m "docs: mention Herdr in README and docs/updating.md"
```

---

### Task 8: Full-suite verification

**Files:** none (verification only)

**Interfaces:** none

- [ ] **Step 1: Run the entire bats suite**

Run: `bats tests/`
Expected: PASS - every test file in `tests/` passes, including all seven files touched in Tasks 1-7 plus every untouched file (regression check).

- [ ] **Step 2: Grep-verify no stray reference was missed**

Run: `grep -rln "Antigravity CLI" --include="*.sh" --include="*.bats" --include="*.md" . | xargs grep -L "Herdr"`

Expected: the output is exactly the files that legitimately don't need a Herdr counterpart (e.g. `docs/superpowers/plans/*.md`, `docs/superpowers/specs/*.md`, `migrations/*.sh` covering the unrelated gh-copilot migration). If any file in `install/`, `uninstall/`, `bin/omawsl-sub/`, `README.md`, or `docs/updating.md` shows up, go back and add the missing `herdr`/`Herdr` reference following that file's existing pattern for Antigravity CLI.

- [ ] **Step 3: Commit (only if Step 2 found and fixed something)**

```bash
git add -A
git commit -m "fix: add missed herdr reference found during full-suite verification"
```
