# GitHub Copilot CLI Autopilot Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user opt in, during install (or a later retrofit), to having `copilot` always launch with `--autopilot --allow-all`, closing issue #2 without silently changing Copilot CLI's default behavior for everyone who installs it.

**Architecture:** One shared guard-and-prompt helper in `install/lib.sh` (`omawsl_prompt_copilot_autopilot_if_needed`), called from both the fresh-install prompt sequence (`install/first-run-choices.sh`) and the retrofit path (`bin/omawsl-sub/install.sh`'s `omawsl_install_apply_editor`). The answer persists to `choices.env` as `OMAWSL_COPILOT_AUTOPILOT`, read back by `configs/bashrc` on every new shell to decide whether to define the `copilot` alias. Uninstalling GitHub Copilot CLI clears the persisted answer.

**Tech Stack:** Bash, `gum choose` (existing prompt primitive - no new one introduced), bats for tests.

## Global Constraints

- Never change `copilot`'s default behavior for a user who hasn't explicitly opted in - the alias must only exist when `OMAWSL_COPILOT_AUTOPILOT` starts with `"Yes"` (per design spec's "Why" section).
- `configs/bashrc` must never `source` `choices.env` directly - always read persisted values via `grep -m1 '^KEY=' ... | cut -d'"' -f2`, matching the existing `OMAWSL_FONT_MODE` block (`install/lib.sh`'s `omawsl_load_choice` doc comment explains why: a persisted value could contain shell metacharacters unsafe to source).
- Use `gum choose` (via a direct call, matching `omawsl_prompt_single`'s shape) for the prompt - this repo has no `gum confirm` usage anywhere; don't introduce it.
- The prompt must fire at most once per machine: only when GitHub Copilot CLI is newly selected (present in the picked list, absent from the prior list) and no `OMAWSL_COPILOT_AUTOPILOT` value is already persisted.
- Every new alias/behavior in `configs/bashrc` must be gated on `command -v copilot &>/dev/null`, matching every other tool-conditional block in that file.

---

### Task 1: Shared prompt-and-persist helper in `install/lib.sh`

**Files:**
- Modify: `install/lib.sh` (add new function near the other `omawsl_*` choice helpers, e.g. after `omawsl_remove_from_csv`)
- Test: `tests/lib_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has <csv> <item>` (already exists, `install/lib.sh`), `omawsl_load_choice <key>` / `omawsl_save_choice <key> <value>` (already exist, `install/lib.sh`), the `gum` stub from `tests/helpers/stubs.bash`.
- Produces: `omawsl_prompt_copilot_autopilot_if_needed <picked_csv> <existing_csv>` - no return value, side effect only (persists `OMAWSL_COPILOT_AUTOPILOT` via `omawsl_save_choice` when it prompts). Called by Task 2 and Task 3.

- [ ] **Step 1: Add `gum_stub_init` to `tests/lib_test.bats`'s shared `setup()`**

This file's tests don't currently use the `gum` stub queue at all; the new tests below need it.

Edit `tests/lib_test.bats` lines 5-9 from:
```bash
setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
}
```
to:
```bash
setup() {
  stub_init
  gum_stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
}
```

- [ ] **Step 2: Write the failing tests**

Append to `tests/lib_test.bats`:
```bash

@test "omawsl_prompt_copilot_autopilot_if_needed prompts and persists when Copilot CLI is newly picked" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  gum_stub_respond "Yes - autopilot + allow-all"
  omawsl_prompt_copilot_autopilot_if_needed "GitHub Copilot CLI" ""
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "Yes - autopilot + allow-all" ]
  [[ "$(stub_calls)" == *"autopilot mode"* ]]
}

@test "omawsl_prompt_copilot_autopilot_if_needed does not prompt when Copilot CLI is not in the picked list" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_prompt_copilot_autopilot_if_needed "VS Code" ""
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "" ]
  [ -z "$(stub_calls)" ]
}

@test "omawsl_prompt_copilot_autopilot_if_needed does not re-prompt when Copilot CLI was already selected before" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_prompt_copilot_autopilot_if_needed "GitHub Copilot CLI" "GitHub Copilot CLI"
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "" ]
  [ -z "$(stub_calls)" ]
}

@test "omawsl_prompt_copilot_autopilot_if_needed does not re-prompt once an answer is already persisted" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT "No - interactive by default (recommended)"
  omawsl_prompt_copilot_autopilot_if_needed "GitHub Copilot CLI" ""
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "No - interactive by default (recommended)" ]
  [ -z "$(stub_calls)" ]
}
```

- [ ] **Step 3: Run the new tests to verify they fail**

Run: `bats tests/lib_test.bats`
Expected: the 4 new tests FAIL with something like "omawsl_prompt_copilot_autopilot_if_needed: command not found" (function doesn't exist yet). All pre-existing tests in this file still PASS.

- [ ] **Step 4: Implement the helper**

Add to `install/lib.sh`, after the `omawsl_remove_from_csv` function:
```bash

# omawsl_prompt_copilot_autopilot_if_needed <picked_csv> <existing_csv>
# Prompts once for whether `copilot` should always start in autopilot +
# allow-all mode (docs/superpowers/specs/2026-08-09-copilot-autopilot-mode-design.md).
# Only fires when GitHub Copilot CLI is newly selected this run (present in
# picked_csv, absent from existing_csv) and no answer is persisted yet -
# never re-asks on an unrelated `omawsl install` run, and never re-asks once
# already answered. Auto-approving all of an AI agent's tool use is a
# safety-relevant default, not a convenience one, so - unlike every other
# choice in first-run-choices.sh - this one is opt-in rather than always
# asked.
omawsl_prompt_copilot_autopilot_if_needed() {
  local picked="$1" existing="$2"
  omawsl_list_has "$picked" "GitHub Copilot CLI" || return 0
  omawsl_list_has "$existing" "GitHub Copilot CLI" && return 0
  [[ -z "$(omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT)" ]] || return 0

  local answer
  answer="$(gum choose --header "GitHub Copilot CLI: always start in autopilot mode (auto-approves all tool use, no confirmation)?" \
    "No - interactive by default (recommended)" "Yes - autopilot + allow-all")"
  omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT "$answer"
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bats tests/lib_test.bats`
Expected: PASS - all tests in the file, including the 4 new ones.

- [ ] **Step 6: Commit**

```bash
git add install/lib.sh tests/lib_test.bats
git commit -m "feat: add opt-in prompt helper for Copilot CLI autopilot mode"
```

---

### Task 2: Wire the prompt into fresh installs

**Files:**
- Modify: `install/first-run-choices.sh:30-32`
- Test: `tests/first_run_choices_test.bats`

**Interfaces:**
- Consumes: `omawsl_prompt_copilot_autopilot_if_needed <picked_csv> <existing_csv>` (Task 1, `install/lib.sh`).

- [ ] **Step 1: Write the failing tests**

Append to `tests/first_run_choices_test.bats`:
```bash

@test "prompts for copilot autopilot mode when GitHub Copilot CLI is selected, and persists the answer" {
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Engine only, inside WSL (recommended)"
  gum_stub_respond "GitHub Copilot CLI"
  gum_stub_respond "Yes - autopilot + allow-all"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Nerd Font (enhanced)"

  omawsl_first_run_choices

  [ "$OMAWSL_EDITORS" = "GitHub Copilot CLI" ]
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "Yes - autopilot + allow-all" ]
}

@test "does not prompt for copilot autopilot mode when GitHub Copilot CLI is not selected" {
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Engine only, inside WSL (recommended)"
  gum_stub_respond "VS Code"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Nerd Font (enhanced)"

  omawsl_first_run_choices

  [ "$OMAWSL_EDITORS" = "VS Code" ]
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "" ]
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bats tests/first_run_choices_test.bats`
Expected: the first new test FAILS (`OMAWSL_COPILOT_AUTOPILOT` never gets set to "Yes - autopilot + allow-all" because nothing calls the prompt yet, and the extra queued gum response throws off `OMAWSL_LANGUAGES`'s expected value indirectly - the assertion on `$OMAWSL_EDITORS`/persisted choice will fail). The second test PASSES already (nothing to wire for the not-selected case), which is fine - it locks in the no-op behavior going forward.

- [ ] **Step 3: Wire the call in**

Edit `install/first-run-choices.sh`, changing:
```bash
  OMAWSL_EDITORS="$(omawsl_prompt_multi "Editors & AI tooling (space to select, enter to confirm)" \
    "VS Code" "Neovim" "opencode" "Cursor" \
    "Claude Code CLI" "Codex CLI" "GitHub Copilot CLI" "Antigravity CLI")"

  OMAWSL_LANGUAGES="$(omawsl_prompt_multi "Languages & cloud tools" \
```
to:
```bash
  OMAWSL_EDITORS="$(omawsl_prompt_multi "Editors & AI tooling (space to select, enter to confirm)" \
    "VS Code" "Neovim" "opencode" "Cursor" \
    "Claude Code CLI" "Codex CLI" "GitHub Copilot CLI" "Antigravity CLI")"

  omawsl_prompt_copilot_autopilot_if_needed "$OMAWSL_EDITORS" ""

  OMAWSL_LANGUAGES="$(omawsl_prompt_multi "Languages & cloud tools" \
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/first_run_choices_test.bats`
Expected: PASS - all tests in the file, including the 2 new ones and the pre-existing "persists all seven choices" / "selecting nothing" tests (neither selects GitHub Copilot CLI, so the new prompt never fires for them and their existing gum-response queues are unaffected).

- [ ] **Step 5: Commit**

```bash
git add install/first-run-choices.sh tests/first_run_choices_test.bats
git commit -m "feat: ask about Copilot CLI autopilot mode on first install"
```

---

### Task 3: Wire the prompt into the retrofit path (`omawsl install editor`)

**Files:**
- Modify: `bin/omawsl-sub/install.sh:32-38` (`omawsl_install_apply_editor`)
- Test: `tests/omawsl_install_command_test.bats`

**Interfaces:**
- Consumes: `omawsl_prompt_copilot_autopilot_if_needed <picked_csv> <existing_csv>` (Task 1, `install/lib.sh`).

- [ ] **Step 1: Write the failing tests**

Append to `tests/omawsl_install_command_test.bats`:
```bash

@test "omawsl install editor gh-copilot - prompts for autopilot mode since newly added and persists the answer" {
  stub_command gh
  stub_hide_command copilot
  gum_stub_respond "Yes - autopilot + allow-all"
  run omawsl_install_command editor gh-copilot
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "GitHub Copilot CLI" ]]
  [[ "$(omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT)" == "Yes - autopilot + allow-all" ]]
}

@test "omawsl install editor gh-copilot - does not re-prompt when GitHub Copilot CLI is already installed" {
  stub_command gh
  stub_command copilot
  omawsl_save_choice OMAWSL_EDITORS "GitHub Copilot CLI"
  run omawsl_install_command editor gh-copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"autopilot mode"* ]]
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bats tests/omawsl_install_command_test.bats`
Expected: the first new test FAILS (`OMAWSL_COPILOT_AUTOPILOT` stays unset because nothing calls the prompt yet). The second test PASSES already (nothing to wire yet), locking in the no-re-prompt behavior going forward.

- [ ] **Step 3: Wire the call in**

Edit `bin/omawsl-sub/install.sh`, changing `omawsl_install_apply_editor` from:
```bash
omawsl_install_apply_editor() {
  local picked="$1" existing="$2"
  local merged; merged="$(omawsl_merge_csv "$existing" "$picked")"
  export OMAWSL_EDITORS="$merged"
  omawsl_save_choice OMAWSL_EDITORS "$merged"
  local f
```
to:
```bash
omawsl_install_apply_editor() {
  local picked="$1" existing="$2"
  local merged; merged="$(omawsl_merge_csv "$existing" "$picked")"
  export OMAWSL_EDITORS="$merged"
  omawsl_save_choice OMAWSL_EDITORS "$merged"
  omawsl_prompt_copilot_autopilot_if_needed "$picked" "$existing"
  local f
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/omawsl_install_command_test.bats`
Expected: PASS - all tests in the file, including the 2 new ones.

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/install.sh tests/omawsl_install_command_test.bats
git commit -m "feat: ask about Copilot CLI autopilot mode when added via omawsl install"
```

---

### Task 4: The `copilot` alias in `configs/bashrc`

**Files:**
- Modify: `configs/bashrc:121-124`
- Test: `tests/a_shell_test.bats`

**Interfaces:**
- Consumes: `OMAWSL_COPILOT_AUTOPILOT` value persisted to `choices.env` by Task 1/2/3's helper (read directly via `grep`/`cut`, not sourced).

- [ ] **Step 1: Write the failing tests**

Append to `tests/a_shell_test.bats` (after the existing `d/r/lzg/lzd` alias tests, before the `n` function tests):
```bash

@test "copilot is aliased to autopilot+allow-all mode when copilot is on PATH and the autopilot choice is Yes" {
  export HOME="$BATS_TEST_TMPDIR/home_copilot_autopilot_yes"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/state/omawsl"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/copilot"
  chmod +x "$HOME/.local/bin/copilot"
  printf 'OMAWSL_COPILOT_AUTOPILOT="Yes - autopilot + allow-all"\n' > "$HOME/.local/state/omawsl/choices.env"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias copilot'
  [ "$status" -eq 0 ]
  [[ "$output" == "alias copilot='copilot --autopilot --allow-all'" ]]
}

@test "copilot is not aliased when the autopilot choice is No" {
  export HOME="$BATS_TEST_TMPDIR/home_copilot_autopilot_no"
  mkdir -p "$HOME/.local/bin" "$HOME/.local/state/omawsl"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/copilot"
  chmod +x "$HOME/.local/bin/copilot"
  printf 'OMAWSL_COPILOT_AUTOPILOT="No - interactive by default (recommended)"\n' > "$HOME/.local/state/omawsl/choices.env"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias copilot'
  [ "$status" -ne 0 ]
}

@test "copilot is not aliased when no autopilot choice was ever persisted, even though copilot is on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_copilot_no_choice"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/copilot"
  chmod +x "$HOME/.local/bin/copilot"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias copilot'
  [ "$status" -ne 0 ]
}

@test "copilot alias is not defined when copilot is not on PATH, even if the autopilot choice is Yes" {
  export HOME="$BATS_TEST_TMPDIR/home_copilot_missing"
  mkdir -p "$HOME/.local/state/omawsl"
  printf 'OMAWSL_COPILOT_AUTOPILOT="Yes - autopilot + allow-all"\n' > "$HOME/.local/state/omawsl/choices.env"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command copilot
  run bash -i -c 'alias copilot'
  [ "$status" -ne 0 ]
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

Run: `bats tests/a_shell_test.bats`
Expected: the first new test FAILS (`alias copilot` is undefined - status non-zero - since bashrc doesn't define it yet). The other 3 new tests PASS already (there's nothing to define, so "not aliased" already holds), locking in that behavior going forward.

- [ ] **Step 3: Add the alias block**

Edit `configs/bashrc`, changing:
```bash
if command -v lazygit &>/dev/null; then
  alias lzg='lazygit'
fi

if command -v nvim &>/dev/null; then
```
to:
```bash
if command -v lazygit &>/dev/null; then
  alias lzg='lazygit'
fi

# Opt-in only (docs/superpowers/specs/2026-08-09-copilot-autopilot-mode-design.md)
# - auto-approving every tool/path/URL Copilot CLI touches is a
# safety-relevant default, not a convenience one, so this alias only exists
# when the user explicitly chose it during install or `omawsl install`.
OMAWSL_COPILOT_AUTOPILOT="$(grep -m1 '^OMAWSL_COPILOT_AUTOPILOT=' "${OMAWSL_STATE_DIR:-$HOME/.local/state/omawsl}/choices.env" 2>/dev/null | cut -d'"' -f2)"
if command -v copilot &>/dev/null && [[ "$OMAWSL_COPILOT_AUTOPILOT" == "Yes"* ]]; then
  alias copilot="copilot --autopilot --allow-all"
fi
unset OMAWSL_COPILOT_AUTOPILOT

if command -v nvim &>/dev/null; then
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/a_shell_test.bats`
Expected: PASS - all tests in the file, including the 4 new ones.

- [ ] **Step 5: Commit**

```bash
git add configs/bashrc tests/a_shell_test.bats
git commit -m "feat: alias copilot to autopilot+allow-all mode when opted in"
```

---

### Task 5: Clear the persisted choice on uninstall

**Files:**
- Modify: `uninstall/app-gh-copilot.sh`
- Test: `tests/uninstall_gh_copilot_test.bats`

**Interfaces:**
- Consumes: `omawsl_save_choice <key> <value>` (already exists, `install/lib.sh`).

- [ ] **Step 1: Write the failing test**

Append to `tests/uninstall_gh_copilot_test.bats`:
```bash

@test "omawsl_uninstall_gh_copilot clears the persisted autopilot choice" {
  stub_command mise
  stub_command gh
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT "Yes - autopilot + allow-all"
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  run omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT
  [ "$output" = "" ]
}
```

- [ ] **Step 2: Run the new test to verify it fails**

Run: `bats tests/uninstall_gh_copilot_test.bats`
Expected: FAIL - `omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT` still returns `"Yes - autopilot + allow-all"` since nothing clears it yet.

- [ ] **Step 3: Clear the choice in the uninstall function**

Edit `uninstall/app-gh-copilot.sh`, changing:
```bash
  if gh extension list 2>/dev/null | grep -q '^gh-copilot\|^gh copilot'; then
    gh extension remove gh-copilot
  fi

  echo "omawsl: GitHub Copilot CLI removed."
```
to:
```bash
  if gh extension list 2>/dev/null | grep -q '^gh-copilot\|^gh copilot'; then
    gh extension remove gh-copilot
  fi

  omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT ""

  echo "omawsl: GitHub Copilot CLI removed."
```

Also update the function's doc comment (the block above `omawsl_uninstall_gh_copilot() {`) to add one sentence: `Also clears the persisted OMAWSL_COPILOT_AUTOPILOT choice, so a later reinstall re-prompts instead of silently inheriting a stale answer.`

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/uninstall_gh_copilot_test.bats`
Expected: PASS - all tests in the file, including the new one.

- [ ] **Step 5: Commit**

```bash
git add uninstall/app-gh-copilot.sh tests/uninstall_gh_copilot_test.bats
git commit -m "fix: clear persisted Copilot autopilot choice on uninstall"
```

---

## Final Verification

- [ ] Run the full test suite: `bats tests/`
  Expected: PASS, no regressions in any other file.
- [ ] Manually trace the end-to-end flow by reading (not running) the diff: fresh install selects GitHub Copilot CLI → prompt fires (Task 2) → `choices.env` gets `OMAWSL_COPILOT_AUTOPILOT` → next shell start, `configs/bashrc` (Task 4) aliases `copilot` iff `command -v copilot` and the choice is `"Yes"*` → uninstalling (Task 5) clears the choice for next time.
