# AI CLI Autopilot Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make all five AI CLI tools offered by omawsl (Claude Code CLI, Codex CLI, GitHub Copilot CLI, Antigravity CLI, opencode) start in autopilot mode by default, unconditionally, with a one-time informational notice instead of a prompt — closing issue #25 and retiring the Copilot-only opt-in prompt from issue #2.

**Architecture:** Replace the single `omawsl_prompt_copilot_autopilot_if_needed` function (which prompted via `gum choose` and persisted an answer) with a new `omawsl_notice_ai_autopilot_if_needed` function that only prints informational text — no `gum`, no persisted choice. Both existing call sites (fresh install, `omawsl install editor ...` retrofit) swap in the new function unchanged in shape. `configs/bashrc` grows from one choice-gated alias to five unconditional, independently `command -v`-gated aliases. The dead choice-clearing line in the Copilot uninstall script is deleted.

**Tech Stack:** Bash, bats (test framework), gum (interactive prompts — not used by the new function, but still used elsewhere in the touched files).

**Spec:** `docs/superpowers/specs/2026-08-14-ai-cli-autopilot-mode-design.md`

## Global Constraints

- Exact flags per tool, copied verbatim from the spec:
  - Claude Code CLI (`claude`): `--dangerously-skip-permissions`
  - Codex CLI (`codex`): `--dangerously-bypass-approvals-and-sandbox`
  - GitHub Copilot CLI (`copilot`): `--autopilot --allow-all`
  - Antigravity CLI (`agy`): `--dangerously-skip-permissions`
  - opencode (`opencode`): `--auto`
- Notice line format (exact, one line per newly-picked tool): `omawsl: <label> starts in autopilot mode by default (<flag>) - auto-approves all tool use, no confirmation.`
- No `choices.env` key, no CLI flag, no env var may gate any of the five aliases — they are unconditional once the binary is on PATH.
- No persisted state anywhere for this feature — the "one-time per machine" property comes entirely from the `picked_csv`/`existing_csv` diff against the already-persisted `OMAWSL_EDITORS`.
- Every alias stays independently gated on its own `command -v <tool> &>/dev/null` check — never a combined check.

---

## Task 1: `install/lib.sh` — replace the prompt function with the notice function

**Files:**
- Modify: `install/lib.sh:256-279` (the `omawsl_prompt_copilot_autopilot_if_needed` function and its doc comment)
- Test: `tests/lib_test.bats:244-286` (the five existing tests for the old function)

**Interfaces:**
- Produces: `omawsl_notice_ai_autopilot_if_needed <picked_csv> <existing_csv>` — prints one line to stdout per label present in `picked_csv` but absent from `existing_csv`, for each of the five fixed AI-CLI labels. Always returns 0. No stdin interaction, no side effects beyond stdout.
- Consumes: `omawsl_list_has <csv> <item>` (already defined at `install/lib.sh:28-31`, unchanged).

- [ ] **Step 1: Write the failing tests**

Replace lines 244-286 of `tests/lib_test.bats` (the five `omawsl_prompt_copilot_autopilot_if_needed` tests) with:

```bash
@test "omawsl_notice_ai_autopilot_if_needed prints a notice naming the tool and its flag when newly picked" {
  run omawsl_notice_ai_autopilot_if_needed "Claude Code CLI" ""
  [ "$status" -eq 0 ]
  [ "$output" = "omawsl: Claude Code CLI starts in autopilot mode by default (--dangerously-skip-permissions) - auto-approves all tool use, no confirmation." ]
}

@test "omawsl_notice_ai_autopilot_if_needed prints nothing when the tool isn't in the picked list" {
  run omawsl_notice_ai_autopilot_if_needed "VS Code" ""
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "omawsl_notice_ai_autopilot_if_needed prints nothing when the tool was already selected before" {
  run omawsl_notice_ai_autopilot_if_needed "Codex CLI" "Codex CLI"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "omawsl_notice_ai_autopilot_if_needed prints one line per newly-picked tool, in a single call" {
  run omawsl_notice_ai_autopilot_if_needed "Claude Code CLI,Codex CLI,GitHub Copilot CLI,Antigravity CLI,opencode" ""
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 5 ]
  [[ "$output" == *"omawsl: Claude Code CLI starts in autopilot mode by default (--dangerously-skip-permissions)"* ]]
  [[ "$output" == *"omawsl: Codex CLI starts in autopilot mode by default (--dangerously-bypass-approvals-and-sandbox)"* ]]
  [[ "$output" == *"omawsl: GitHub Copilot CLI starts in autopilot mode by default (--autopilot --allow-all)"* ]]
  [[ "$output" == *"omawsl: Antigravity CLI starts in autopilot mode by default (--dangerously-skip-permissions)"* ]]
  [[ "$output" == *"omawsl: opencode starts in autopilot mode by default (--auto)"* ]]
}

@test "omawsl_notice_ai_autopilot_if_needed only notices newly-picked tools, not ones already existing, in a mixed call" {
  run omawsl_notice_ai_autopilot_if_needed "Claude Code CLI,Codex CLI" "Codex CLI"
  [ "$status" -eq 0 ]
  [ "$output" = "omawsl: Claude Code CLI starts in autopilot mode by default (--dangerously-skip-permissions) - auto-approves all tool use, no confirmation." ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/lib_test.bats -f "omawsl_notice_ai_autopilot_if_needed"`
Expected: FAIL — `omawsl_notice_ai_autopilot_if_needed: command not found` (function doesn't exist yet).

- [ ] **Step 3: Replace the function in `install/lib.sh`**

Replace lines 256-279 (the `omawsl_prompt_copilot_autopilot_if_needed` doc comment and function body) with:

```bash
# omawsl_notice_ai_autopilot_if_needed <picked_csv> <existing_csv>
# Prints a one-time informational notice for each of the five AI CLI tools
# newly selected this run (present in picked_csv, absent from existing_csv) -
# see docs/superpowers/specs/2026-08-14-ai-cli-autopilot-mode-design.md.
# Replaces omawsl_prompt_copilot_autopilot_if_needed entirely: all five tools
# start in autopilot mode unconditionally now, so there is nothing to ask and
# nothing to persist - this exists purely so someone isn't surprised days
# later that one of these tools behaves differently than they remember.
# Named per-tool rather than a static list of all five, so the notice never
# implies a tool the user didn't just pick is already being auto-approved.
# No persisted state anywhere: the picked_csv/existing_csv diff alone gives
# the "one-time per machine" property, since once a label lands in the
# persisted OMAWSL_EDITORS it counts as "existing" on every later run.
omawsl_notice_ai_autopilot_if_needed() {
  local picked="$1" existing="$2"
  local label flag
  while IFS='|' read -r label flag; do
    omawsl_list_has "$picked" "$label" || continue
    omawsl_list_has "$existing" "$label" && continue
    echo "omawsl: $label starts in autopilot mode by default ($flag) - auto-approves all tool use, no confirmation."
  done <<'AI_CLI_FLAGS'
Claude Code CLI|--dangerously-skip-permissions
Codex CLI|--dangerously-bypass-approvals-and-sandbox
GitHub Copilot CLI|--autopilot --allow-all
Antigravity CLI|--dangerously-skip-permissions
opencode|--auto
AI_CLI_FLAGS
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/lib_test.bats -f "omawsl_notice_ai_autopilot_if_needed"`
Expected: PASS (5 tests, 0 failures)

- [ ] **Step 5: Run the full lib test file to confirm nothing else broke**

Run: `bats tests/lib_test.bats`
Expected: PASS (all tests, 0 failures)

- [ ] **Step 6: Commit**

```bash
git add install/lib.sh tests/lib_test.bats
git commit -m "feat: replace Copilot autopilot prompt with a notice for all five AI CLIs"
```

---

## Task 2: `install/first-run-choices.sh` — fresh-install call site

**Files:**
- Modify: `install/first-run-choices.sh:34`
- Test: `tests/first_run_choices_test.bats:62-93`

**Interfaces:**
- Consumes: `omawsl_notice_ai_autopilot_if_needed <picked_csv> <existing_csv>` (Task 1).

- [ ] **Step 1: Write the failing tests**

Replace lines 62-93 of `tests/first_run_choices_test.bats` (the two `prompts for copilot autopilot mode...` tests) with:

```bash
@test "prints an autopilot notice for each newly-picked AI CLI, one per tool" {
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Engine only, inside WSL (recommended)"
  gum_stub_respond $'Claude Code CLI\nCodex CLI\nGitHub Copilot CLI\nAntigravity CLI\nopencode'
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Nerd Font (enhanced)"

  run omawsl_first_run_choices

  [ "$status" -eq 0 ]
  [[ "$output" == *"omawsl: Claude Code CLI starts in autopilot mode by default"* ]]
  [[ "$output" == *"omawsl: Codex CLI starts in autopilot mode by default"* ]]
  [[ "$output" == *"omawsl: GitHub Copilot CLI starts in autopilot mode by default"* ]]
  [[ "$output" == *"omawsl: Antigravity CLI starts in autopilot mode by default"* ]]
  [[ "$output" == *"omawsl: opencode starts in autopilot mode by default"* ]]
}

@test "does not print an autopilot notice when no AI CLI is selected" {
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Engine only, inside WSL (recommended)"
  gum_stub_respond "VS Code"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Nerd Font (enhanced)"

  run omawsl_first_run_choices

  [ "$status" -eq 0 ]
  [[ "$output" != *"autopilot mode"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/first_run_choices_test.bats -f "autopilot notice"`
Expected: FAIL — first test's output won't contain the notice lines (old prompt path still active and errors, since `omawsl_prompt_copilot_autopilot_if_needed` still exists at this point... note: Task 1 already replaced it, so this will instead fail with "command not found" for `omawsl_prompt_copilot_autopilot_if_needed" at first-run-choices.sh:34, OR simply produce no notice output). Confirm the failure message names the missing behavior, not an unrelated error.

- [ ] **Step 3: Update the call site**

In `install/first-run-choices.sh:34`, replace:

```bash
  omawsl_prompt_copilot_autopilot_if_needed "$OMAWSL_EDITORS" ""
```

with:

```bash
  omawsl_notice_ai_autopilot_if_needed "$OMAWSL_EDITORS" ""
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/first_run_choices_test.bats`
Expected: PASS (all tests, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add install/first-run-choices.sh tests/first_run_choices_test.bats
git commit -m "feat: swap the fresh-install Copilot prompt for the all-tools autopilot notice"
```

---

## Task 3: `bin/omawsl-sub/install.sh` — retrofit call site

**Files:**
- Modify: `bin/omawsl-sub/install.sh:38`
- Test: `tests/omawsl_install_command_test.bats:103-120`

**Interfaces:**
- Consumes: `omawsl_notice_ai_autopilot_if_needed <picked_csv> <existing_csv>` (Task 1).

- [ ] **Step 1: Write the failing tests**

Replace lines 103-120 of `tests/omawsl_install_command_test.bats` (the two `omawsl install editor gh-copilot` tests) with:

```bash
@test "omawsl install editor gh-copilot - prints an autopilot notice since newly added" {
  stub_command gh
  stub_hide_command copilot
  run omawsl_install_command editor gh-copilot
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "GitHub Copilot CLI" ]]
  [[ "$output" == *"omawsl: GitHub Copilot CLI starts in autopilot mode by default (--autopilot --allow-all)"* ]]
}

@test "omawsl install editor gh-copilot - does not reprint the notice when GitHub Copilot CLI is already installed" {
  stub_command gh
  stub_command copilot
  omawsl_save_choice OMAWSL_EDITORS "GitHub Copilot CLI"
  run omawsl_install_command editor gh-copilot
  [ "$status" -eq 0 ]
  [[ "$output" != *"autopilot mode"* ]]
}

@test "omawsl install editor vscode - does not print an autopilot notice for a non-AI-CLI editor" {
  run omawsl_install_command editor vscode
  [ "$status" -eq 0 ]
  [[ "$output" != *"autopilot mode"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/omawsl_install_command_test.bats -f "autopilot notice"`
Expected: FAIL — first test's `$output` doesn't contain the notice text (call site still invokes the old/removed function).

- [ ] **Step 3: Update the call site**

In `bin/omawsl-sub/install.sh:38`, replace:

```bash
  omawsl_prompt_copilot_autopilot_if_needed "$picked" "$existing"
```

with:

```bash
  omawsl_notice_ai_autopilot_if_needed "$picked" "$existing"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/omawsl_install_command_test.bats`
Expected: PASS (all tests, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/install.sh tests/omawsl_install_command_test.bats
git commit -m "feat: swap the omawsl-install retrofit Copilot prompt for the autopilot notice"
```

---

## Task 4: `configs/bashrc` — five unconditional aliases

**Files:**
- Modify: `configs/bashrc:156-173` (replace the choice-gated Copilot block with four unconditional aliases: claude, codex, copilot, agy)
- Modify: `configs/bashrc:186-190` (append the opencode alias, kept separate — see rationale in Step 3)
- Test: `tests/a_shell_test.bats:318-374`

**Interfaces:** None — this task only wires up shell aliases; no bash functions are consumed or produced for other tasks to use.

**Important implementation note (found during investigation, not spelled out in the spec):** `claude`, `codex`, `copilot`, and `agy` all install to `$HOME/.local/bin`, which is already exported at `configs/bashrc:146-148` — well before the old Copilot block at line 156. `opencode`, however, can install to `$HOME/.opencode/bin` instead (its own installer script; `install/terminal/app-opencode.sh` checks both `command -v opencode` and `-x "$HOME/.opencode/bin/opencode"`), and that directory isn't added to `$PATH` until `configs/bashrc:188-190` — after the old Copilot block. Copying the spec's five-line snippet verbatim into one place at line 156 would make `command -v opencode` fail for anyone who only has it via `$HOME/.opencode/bin`, silently skipping the alias. The opencode alias must live after its own PATH export instead.

- [ ] **Step 1: Write the failing tests**

Replace lines 318-374 of `tests/a_shell_test.bats` (the four `copilot is...`/`copilot alias is...` tests keyed off `OMAWSL_COPILOT_AUTOPILOT`) with:

```bash
@test "claude is aliased to autopilot mode (--dangerously-skip-permissions) when claude is on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_claude"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/claude"
  chmod +x "$HOME/.local/bin/claude"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias claude'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias claude='claude --dangerously-skip-permissions'"* ]]
}

@test "claude is not aliased when claude is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_no_claude"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command claude
  run bash -i -c 'alias claude'
  [ "$status" -ne 0 ]
}

@test "codex is aliased to autopilot mode (--dangerously-bypass-approvals-and-sandbox) when codex is on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_codex"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/codex"
  chmod +x "$HOME/.local/bin/codex"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias codex'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias codex='codex --dangerously-bypass-approvals-and-sandbox'"* ]]
}

@test "codex is not aliased when codex is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_no_codex"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command codex
  run bash -i -c 'alias codex'
  [ "$status" -ne 0 ]
}

@test "copilot is unconditionally aliased to autopilot+allow-all mode when copilot is on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_copilot"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/copilot"
  chmod +x "$HOME/.local/bin/copilot"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias copilot'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias copilot='copilot --autopilot --allow-all'"* ]]
}

@test "copilot is not aliased when copilot is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_no_copilot"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command copilot
  run bash -i -c 'alias copilot'
  [ "$status" -ne 0 ]
}

@test "copilot alias is defined even though copilot is only reachable via \$HOME/.local/bin, added later in the same file (PATH-ordering regression guard)" {
  export HOME="$BATS_TEST_TMPDIR/home_copilot_path_order"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/copilot"
  chmod +x "$HOME/.local/bin/copilot"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias copilot'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias copilot='copilot --autopilot --allow-all'"* ]]
}

@test "agy is aliased to autopilot mode (--dangerously-skip-permissions) when agy is on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_agy"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/agy"
  chmod +x "$HOME/.local/bin/agy"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias agy'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias agy='agy --dangerously-skip-permissions'"* ]]
}

@test "agy is not aliased when agy is not on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_no_agy"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command agy
  run bash -i -c 'alias agy'
  [ "$status" -ne 0 ]
}

@test "opencode is aliased to autopilot mode (--auto) when opencode is on PATH" {
  export HOME="$BATS_TEST_TMPDIR/home_opencode"
  mkdir -p "$HOME/.local/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.local/bin/opencode"
  chmod +x "$HOME/.local/bin/opencode"
  export PATH="$HOME/.local/bin:$PATH"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias opencode'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias opencode='opencode --auto'"* ]]
}

@test "opencode is not aliased when opencode is not installed anywhere" {
  export HOME="$BATS_TEST_TMPDIR/home_no_opencode"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  stub_hide_command opencode
  run bash -i -c 'alias opencode'
  [ "$status" -ne 0 ]
}

@test "opencode is aliased even though it's only reachable via \$HOME/.opencode/bin, whose PATH export comes later in the same file (PATH-ordering regression guard)" {
  export HOME="$BATS_TEST_TMPDIR/home_opencode_path_order"
  mkdir -p "$HOME/.opencode/bin"
  printf '#!/usr/bin/env bash\ntrue\n' > "$HOME/.opencode/bin/opencode"
  chmod +x "$HOME/.opencode/bin/opencode"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'alias opencode'
  [ "$status" -eq 0 ]
  [[ "$output" == *"alias opencode='opencode --auto'"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bats tests/a_shell_test.bats -f "aliased"`
Expected: FAIL for `claude`, `codex`, `agy`, and the plain `opencode`/`copilot` "is aliased" tests (no alias defined yet for any of these under the old choice-gated block); the "is not aliased" tests will spuriously PASS already (nothing is aliased yet) — that's expected and will stay green through Step 3.

- [ ] **Step 3: Replace the Copilot block and add the opencode alias**

In `configs/bashrc`, replace lines 156-173 (the entire `if command -v copilot &>/dev/null; then ... fi` block and its preceding comment) with:

```bash
# All five default to autopilot mode with no opt-out - deliberate departure
# from this file's usual choices.env-gated pattern (see design spec's "Why":
# docs/superpowers/specs/2026-08-14-ai-cli-autopilot-mode-design.md). Each
# alias is independently gated on its own `command -v`, so only tools
# actually installed get aliased, and uninstalling one needs no
# special-casing here - once its binary is gone, `command -v` fails and the
# alias simply isn't set on the next shell. claude/codex/copilot/agy have no
# apt package - they install to $HOME/.local/bin, only reachable after the
# PATH export above. Must not move this block back above that export -
# confirmed as a real bug, same class as the mise ordering issue documented
# above. opencode's alias lives separately, right after its own PATH export
# below - it's the one of these five whose install can land outside
# $HOME/.local/bin (see that section) - not here.
command -v claude &>/dev/null && alias claude="claude --dangerously-skip-permissions"
command -v codex &>/dev/null && alias codex="codex --dangerously-bypass-approvals-and-sandbox"
command -v copilot &>/dev/null && alias copilot="copilot --autopilot --allow-all"
command -v agy &>/dev/null && alias agy="agy --dangerously-skip-permissions"
```

Then, in the same file, append one line right after the existing opencode PATH-export block (currently lines 186-190):

```bash
# opencode's installer places its binary here, not $HOME/.local/bin like
# mise/lazydocker/claude - needs its own PATH entry.
if [ -d "$HOME/.opencode/bin" ]; then
  export PATH="$HOME/.opencode/bin:$PATH"
fi

# Autopilot default, no opt-out (see the claude/codex/copilot/agy block
# above for the full rationale) - split out from that block since opencode
# needs the PATH export immediately above first.
command -v opencode &>/dev/null && alias opencode="opencode --auto"
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/a_shell_test.bats`
Expected: PASS (all tests, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add configs/bashrc tests/a_shell_test.bats
git commit -m "feat: alias all five AI CLIs into autopilot mode unconditionally"
```

---

## Task 5: `uninstall/app-gh-copilot.sh` — drop the dead choice-clearing line

**Files:**
- Modify: `uninstall/app-gh-copilot.sh:8-32` (doc comment) and `:43` (the line itself)
- Test: `tests/uninstall_gh_copilot_test.bats:59-68` (remove), `:90-123` (rewrite)

**Interfaces:** None.

- [ ] **Step 1: Write the failing test**

In `tests/uninstall_gh_copilot_test.bats`:

1. Delete the entire test at lines 59-68 (`omawsl_uninstall_gh_copilot clears the persisted autopilot choice`).

2. Replace the test at lines 90-123 (`omawsl_uninstall_gh_copilot still clears persisted state when gh extension remove fails`) with:

```bash
@test "omawsl_uninstall_gh_copilot still clears the persisted OMAWSL_EDITORS entry when gh extension remove fails" {
  # Invoked via a fresh `bash -c` (not a sourced function call captured by
  # bats' `run`, which runs inside a $(...) command substitution and so
  # does not inherit errexit by default) to match how
  # bin/omawsl-sub/uninstall.sh really calls this: source the script, then
  # call the function directly under `set -euo pipefail` in the same
  # process, where an unguarded failing command genuinely aborts the
  # function.
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  omawsl_save_choice OMAWSL_EDITORS "VS Code,GitHub Copilot CLI,Neovim"

  run bash -c '
    set -euo pipefail
    mise() { return 0; }
    export -f mise
    gh() {
      case "$1 $2" in
        "extension list") echo "gh copilot	github/gh-copilot	v1.2.0" ;;
        "extension remove") return 1 ;;
      esac
      return 0
    }
    export -f gh
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/uninstall/app-gh-copilot.sh"
    omawsl_uninstall_gh_copilot
  '
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "VS Code,Neovim" ]]
}
```

- [ ] **Step 2: Run the tests to verify the rewritten one fails**

Run: `bats tests/uninstall_gh_copilot_test.bats -f "gh extension remove fails"`
Expected: PASS already, actually — the `OMAWSL_EDITORS` assertion doesn't depend on the line being removed. To confirm the *deletion* step is real (not a no-op), instead verify the removed test is gone and everything else still reflects current behavior:

Run: `bats tests/uninstall_gh_copilot_test.bats`
Expected: PASS (the "clears the persisted autopilot choice" test no longer exists to fail or pass; the rewritten test passes because `omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT ""` at line 43 is still present at this point, but the rewritten test never checks that key, so it can't tell either way yet — this step just confirms no test currently *requires* the dead line to stay).

- [ ] **Step 3: Update the doc comment and remove the dead line**

In `uninstall/app-gh-copilot.sh`, replace the doc comment at lines 8-32 with:

```bash
# omawsl_uninstall_gh_copilot
# Inverse of install/terminal/app-gh-copilot.sh: uninstalls the npm global
# package via the same private mise-managed Node runtime it was installed
# with, then removes the $HOME/.local/bin/copilot wrapper. Also removes the
# old deprecated `gh-copilot` gh extension (invoked as `gh copilot ...`),
# for anyone who still has it from before the switch to the standalone
# `@github/copilot` npm package - same repo-slug-column match the old
# uninstall used, since `gh extension list`'s first column is the
# space-separated invocation name ("gh copilot"), not the hyphenated
# "gh-copilot". No-ops the npm step (but still removes the wrapper) if
# mise isn't reachable, since a leftover wrapper pointing at a now-broken
# `mise exec` call is worse than nothing. Also removes "GitHub Copilot CLI"
# from the persisted OMAWSL_EDITORS list directly: this script supports
# direct invocation (footer below, and tests/uninstall_gh_copilot_test.bats
# calls it that way), which bypasses bin/omawsl-sub/uninstall.sh's separate
# omawsl_uninstall_deselect step - without this, a later reinstall would see
# Copilot as "already existing" in OMAWSL_EDITORS and
# omawsl_notice_ai_autopilot_if_needed
# (docs/superpowers/specs/2026-08-14-ai-cli-autopilot-mode-design.md) would
# skip the one-time notice on that reinstall. `gh extension remove` is
# best-effort (`|| true`) for the same reason the npm uninstall above is:
# under `set -euo pipefail`, an unguarded failure there (auth/network/broken
# extension state) would abort the function before the state cleanup below
# ever runs, leaving choices.env stale.
```

Then remove the dead line and its blank-line spacing. Replace:

```bash
  if gh extension list 2>/dev/null | grep -q '^gh-copilot\|^gh copilot'; then
    gh extension remove gh-copilot || true
  fi

  omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT ""

  local editors
```

with:

```bash
  if gh extension list 2>/dev/null | grep -q '^gh-copilot\|^gh copilot'; then
    gh extension remove gh-copilot || true
  fi

  local editors
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bats tests/uninstall_gh_copilot_test.bats`
Expected: PASS (all remaining tests, 0 failures)

- [ ] **Step 5: Commit**

```bash
git add uninstall/app-gh-copilot.sh tests/uninstall_gh_copilot_test.bats
git commit -m "fix: drop dead OMAWSL_COPILOT_AUTOPILOT cleanup from Copilot uninstall"
```

---

## Task 6: `tests/install_test.bats` — fix the broken end-to-end integration test

**Files:**
- Modify: `tests/install_test.bats:53-105` (the `runs the full install end to end and writes version state` test)

**Interfaces:** None — this task only fixes an integration test whose `gum` response queue assumed the old prompt's extra `gum choose` call.

**Context:** This test isn't named in the spec's "Testing" section, but it exercises the full `install.sh` flow with `GitHub Copilot CLI` selected, and its `gum_stub_respond` queue includes an extra response (line 61: `"No - interactive by default (recommended)"`) to answer the old prompt's `gum choose` call. `omawsl_notice_ai_autopilot_if_needed` (Task 1) never calls `gum` at all, so that extra queued response is never consumed — every `gum_stub_respond` call after it silently shifts one slot early, misassigning answers to unrelated prompts (languages/cloud/storage/font). This must be fixed as part of this change or `bats tests/` stops passing cleanly.

- [ ] **Step 1: Confirm the test currently fails after Tasks 1-4**

Run: `bats tests/install_test.bats -f "runs the full install end to end"`
Expected: FAIL — the response meant for `OMAWSL_LANGUAGES` (`$'Go\nTerraform'`) actually gets consumed by the (now nonexistent) autopilot prompt slot, so `OMAWSL_LANGUAGES` ends up wrong and the `grep -q '^OMAWSL_LANGUAGES="Go,Terraform"$'` assertion at line 87 fails.

- [ ] **Step 2: Fix the gum response queue and comment**

In `tests/install_test.bats`, replace lines 56-61:

```bash
  gum_stub_respond $'VS Code\nNeovim\nGitHub Copilot CLI'
  # GitHub Copilot CLI was just picked above, so
  # omawsl_prompt_copilot_autopilot_if_needed (install/lib.sh) fires its own
  # gum choose right after the editors prompt, before languages - answer it
  # here or every response below silently shifts down one slot.
  gum_stub_respond "No - interactive by default (recommended)"
```

with:

```bash
  gum_stub_respond $'VS Code\nNeovim\nGitHub Copilot CLI'
  # GitHub Copilot CLI was just picked above.
  # omawsl_notice_ai_autopilot_if_needed (install/lib.sh) fires right after
  # the editors prompt, before languages, but only prints a notice - it
  # never calls gum, so (unlike the old per-tool opt-in prompt this
  # replaced) there is no extra response to queue here.
```

- [ ] **Step 3: Add an assertion that the notice actually fired (optional but cheap - confirms end-to-end wiring)**

Immediately after line 96 (`[[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @github/copilot"* ]]`), add:

```bash
  [[ "$output" == *"omawsl: GitHub Copilot CLI starts in autopilot mode by default (--autopilot --allow-all)"* ]]
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bats tests/install_test.bats`
Expected: PASS (both tests in the file, 0 failures)

- [ ] **Step 5: Run the entire suite to confirm the whole change set is clean**

Run: `bats tests/`
Expected: PASS (all tests, 0 failures)

- [ ] **Step 6: Commit**

```bash
git add tests/install_test.bats
git commit -m "fix: update end-to-end install test for the no-prompt autopilot notice"
```

---

## Final verification

- [ ] **Step 1: Confirm no remaining references to the retired mechanism**

Run: `grep -rn "omawsl_prompt_copilot_autopilot_if_needed\|OMAWSL_COPILOT_AUTOPILOT" --include="*.sh" --include="*.bats" .`
Expected: no output (both the old function name and the old choice key are gone from all shell scripts and tests).

- [ ] **Step 2: Full suite green**

Run: `bats tests/`
Expected: PASS, 0 failures.

- [ ] **Step 3: Manual smoke-test against real installed binaries (per spec's "Error handling" note)**

For each of `claude`, `codex`, `agy`, `opencode` that's actually installed on the machine running this check, confirm the flag is accepted in the position the alias uses it (bare `<tool> <flag> --help` or equivalent) — the spec explicitly calls out that Codex's flag was confirmed to work before the subcommand, but the other three are assumed rather than verified.
