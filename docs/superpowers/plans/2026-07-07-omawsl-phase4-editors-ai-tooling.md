# omawsl Phase 4: Editors & AI Tooling — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add all 8 `OMAWSL_EDITORS` scripts (VS Code, Neovim, opencode, Cursor, Claude Code CLI, Codex CLI, GitHub Copilot CLI, Gemini CLI), extend `windows-prereq-checklist.sh` for the two Windows-side GUI apps (VS Code, Cursor), and fold in six always-on terminal tools (`gh`, `btop`, `fastfetch`, `lazygit`, `lazydocker`, `zellij`) that the design spec calls for but no earlier phase ever scheduled.

**Architecture:** Each of the 8 editor/AI-tool scripts checks its own `OMAWSL_EDITORS` membership and no-ops cleanly if not selected — matching `select-dev-language.sh`'s and `cloud-tools.sh`'s established shape. VS Code and Cursor are Windows-side GUI apps omawsl never auto-installs: each detects its CLI (`code`/`cursor`) via Win32 interop and deploys a shared baseline `configs/vscode.json` to that editor's Remote-WSL "Machine" settings location (inert until the editor first connects, then picked up automatically), skipping only the one step that needs the live CLI binary. Codex CLI and Gemini CLI have no distribution channel besides npm, so each provisions a private `mise`-managed Node runtime (`mise exec node@lts`, independent of whatever the user separately picked in the language picker) and writes a thin wrapper script into `$HOME/.local/bin` that re-resolves through `mise exec` on every invocation — explicit rather than relying on `mise`'s shim mechanism to expose a binary from an ad-hoc npm global install, after Phase 3 found a real bug in that exact class of assumption for Ruby/Rails. The six always-on tools extend `apps-terminal.sh` (four via Ubuntu's own apt repo, confirmed available; two — `lazydocker`, `zellij` — via their own official install methods, each behind a `command -v` idempotency guard).

**Tech Stack:** Bash (`set -euo pipefail`), Ubuntu 26.04's own apt `universe` repo, official installer scripts (`lazydocker`, `opencode`, Claude Code CLI), a direct GitHub release binary download (`zellij`), `mise exec` for npm-only tools (Codex CLI, Gemini CLI), `gh extension install` (GitHub Copilot CLI), LazyVim's official starter template (Neovim), bats-core (already vendored).

## Global Constraints

(Copied verbatim or paraphrased from `docs/superpowers/specs/2026-07-05-omawsl-design.md` §10 and this codebase's own established conventions — every task below implicitly inherits these.)

- **All 8 editor/AI-tool scripts are optional, selected via `OMAWSL_EDITORS`** (already exists, Phase 1's `first-run-choices.sh`) — **no default is forced on**, including VS Code. Each script is skipped entirely if its tool wasn't selected — no partial setup, no config/extension writes for tools the user didn't ask for (§10).
- **VS Code and Cursor are Windows-side GUI apps omawsl never auto-installs.** If the CLI isn't reachable yet, that's not a failure: still deploy what can be deployed (settings), skip only the step needing the live CLI, print a message pointing at `docs/windows-setup.md`, and let the rest of the install continue (§2, §10) — same detect-and-defer shape already used for Docker Desktop (Phase 2).
- **Claude Code CLI, Codex CLI, Gemini CLI are purely WSL-side, no Windows dependency** (§10).
- **Where the only distribution channel is npm** (Codex CLI, Gemini CLI here), use a private `mise`-managed Node runtime internally, **not** dependent on whether the user separately picked Node.js in the language picker — that picker is about the user's own project runtime, not an implementation detail of an unrelated tool (§10).
- **GitHub Copilot CLI depends only on `gh`**, which this phase's `apps-terminal.sh` extension installs unconditionally regardless of any picker — no cross-picker dependency gap (§10). Actual usability still depends on an authenticated `gh` session and an active Copilot subscription — a README-level runtime concern, not an install-time failure.
- **Cursor reads the same `workbench.colorTheme`-style settings keys as VS Code**, so it shares the same baseline `configs/vscode.json` rather than needing its own file (§11).
- Membership checks on `OMAWSL_EDITORS` go through `omawsl_list_has` (comma-delimited, whole-token match), never a bare substring check (§6).
- Every install script must be **runnable in isolation** (§15).
- `install/terminal/*.sh` scripts are **sourced, not sub-shelled**, by `terminal.sh` (§8).
- **Never overwrite a user's existing config** where one might already exist (Neovim's `~/.config/nvim`) — check for it first.
- **A stubbed command sitting on the read side of a real pipe can SIGPIPE the write side** if the stub returns instantly without draining stdin (Phase 2 lesson) — any test piping a stubbed `curl`'s (empty) output into another stubbed command is safe (neither side does real work or has a timing-dependent delay), but don't assume this holds for *unstubbed* downstream commands.
- **This WSL instance's real state keeps drifting further from a "nothing installed" baseline** as manual verification runs accumulate (Docker, Terraform, mise all genuinely installed on it now) — any new test asserting "tool X is not installed" must use the shared `stub_hide_command X` helper (`tests/helpers/stubs.bash`, added in Phase 3) rather than assuming ambient absence, and any new test file whose code under test reads or writes `$HOME`-relative paths must isolate `HOME` to a tmp directory from the start (`export HOME="$BATS_TEST_TMPDIR/home"`) — not after the fact, once this same machine's *own* Phase 4 manual verification run makes it a real problem (exactly what happened to `mise_test.bats` in Phase 3).

---

## Environment Notes for Whoever Runs This Plan

- Same test instance as Phases 1–3: reachable via `wsl.exe -d Ubuntu -- bash -c "..."`, repo at `/mnt/c/Users/tcins/vscode-workspace/omawsl` inside WSL. Every `.bats` file runs the same way:
  ```
  wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/<branch> && tests/.bats-core/bin/bats tests/<file>.bats"
  ```
- **Confirmed available in Ubuntu 26.04's own `universe` apt repo** (checked via `apt-cache policy` against the real test instance): `gh` (2.46.0-4), `btop` (1.4.6-2), `fastfetch` (2.57.1+dfsg-1ubuntu1), `lazygit` (0.57.0+ds1-1). **Confirmed NOT available via apt at all** (empty `apt-cache policy`/`apt list -a`): `lazydocker`, `zellij` — each needs its own install method (see Task 1).
- **`lazydocker`'s official installer** (`https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh`) needs no `sudo`, prompts for nothing, installs to `$HOME/.local/bin/lazydocker` by default, and always re-downloads/reinstalls unconditionally on every invocation (no self-skip) — this plan's own `command -v` guard is what makes it idempotent.
- **`zellij`'s official one-liner** (`bash <(curl -L https://zellij.dev/launch)`) delegates to a remote script whose exact behavior isn't audited here. This plan uses a direct GitHub release download instead (confirmed asset naming via the GitHub API: `zellij-x86_64-unknown-linux-musl.tar.gz` / `zellij-aarch64-unknown-linux-musl.tar.gz`, and `github.com/.../releases/latest/download/<asset>` always resolves to the current release), so every step stays auditable in this repo.
- **Claude Code CLI's installer** (`curl -fsSL https://claude.ai/install.sh | bash`) delegates final placement to the downloaded binary's own `install` subcommand — confirmed no `sudo` needed, writes only under `$HOME`. Modern versions of this installer are assumed to place the `claude` binary under `$HOME/.local/bin` (already on `PATH` via `configs/bashrc`), consistent with the same convention `mise`/`lazydocker` use — **this specific assumption is flagged as unverified** (matching this project's existing pattern for `configs/zellij.kdl` keybinding fidelity and the original `bashrc`/`inputrc` fidelity) and should be confirmed during this phase's own manual verification task.
- **`opencode`'s installer** (`curl -fsSL https://opencode.ai/install | bash`) is documented to install to `$HOME/.opencode/bin/opencode` specifically — **not** `$HOME/.local/bin` like the others — so `configs/bashrc` needs an additional `PATH` entry for it (Task 6).
- **`@openai/codex` and `@google/gemini-cli` are npm-only** — no native binary installer found for either during this plan's research. Each is installed via a private `mise exec node@lts -- npm install -g <package>` call, with an explicit wrapper script written to `$HOME/.local/bin` afterward (see Global Constraints) rather than relying on `mise`'s shim mechanism to expose a binary from that ad-hoc install.
- **VS Code Remote-WSL and Cursor's WSL integration store machine-wide settings** at `$HOME/.vscode-server/data/Machine/settings.json` and `$HOME/.cursor-server/data/Machine/settings.json` respectively — these directories don't exist until the editor has connected to this WSL distro at least once, so pre-creating them with a baseline `settings.json` means it's picked up automatically the first time it does, without needing the live CLI at all.
- **Cursor's extension-install step is deliberately narrower than VS Code's.** The design spec says to "configure what can be configured" for Cursor but doesn't specify installing `ms-vscode-remote.remote-wsl` there — Cursor is a fork with its own extension distribution, and Microsoft's own marketplace commonly blocks non-VS-Code products from installing Microsoft-published extensions. This plan deploys the shared settings file for Cursor but does **not** attempt an extension install for it, unlike VS Code. Flagged as a deliberate scope decision, not an oversight.

## File Structure

```
omawsl/
├── configs/
│   ├── bashrc                              # + $HOME/.opencode/bin PATH entry (Task 6)
│   └── vscode.json                         # NEW (Task 3) - shared VS Code/Cursor baseline settings
├── install/
│   ├── lib.sh                              # + omawsl_code_reachable, omawsl_cursor_reachable (Task 2)
│   ├── windows-prereq-checklist.sh         # + VS Code/Cursor checklist items (Task 2)
│   ├── terminal.sh                         # + 8 new scripts in the dispatch table (Task 11)
│   └── terminal/
│       ├── apps-terminal.sh                # + gh/btop/fastfetch/lazygit/lazydocker/zellij (Task 1)
│       ├── app-vscode.sh                   # NEW (Task 3)
│       ├── app-cursor.sh                   # NEW (Task 4)
│       ├── app-neovim.sh                   # NEW (Task 5)
│       ├── app-opencode.sh                 # NEW (Task 6)
│       ├── app-claude-cli.sh               # NEW (Task 7)
│       ├── app-codex-cli.sh                # NEW (Task 8)
│       ├── app-gemini-cli.sh               # NEW (Task 9)
│       └── app-gh-copilot.sh               # NEW (Task 10)
└── tests/
    ├── apps_terminal_test.bats             # updated (Task 1)
    ├── lib_test.bats                       # + 4 tests (Task 2)
    ├── windows_prereq_checklist_test.bats  # + tests (Task 2)
    ├── app_vscode_test.bats                # NEW (Task 3)
    ├── app_cursor_test.bats                # NEW (Task 4)
    ├── app_neovim_test.bats                # NEW (Task 5)
    ├── app_opencode_test.bats              # NEW (Task 6)
    ├── app_claude_cli_test.bats            # NEW (Task 7)
    ├── app_codex_cli_test.bats             # NEW (Task 8)
    ├── app_gemini_cli_test.bats            # NEW (Task 9)
    ├── app_gh_copilot_test.bats            # NEW (Task 10)
    ├── terminal_test.bats                  # updated fixed-order list (Task 11)
    └── install_test.bats                   # updated end-to-end coverage (Task 12)
```

---

### Task 1: Extend `apps-terminal.sh` with the missing always-on terminal tools

**Files:**
- Modify: `install/terminal/apps-terminal.sh`
- Modify: `tests/apps_terminal_test.bats`

**Interfaces:**
- Modifies: `omawsl_install_terminal_apps` (existing) — now also installs `gh`/`btop`/`fastfetch`/`lazygit` via apt and calls two new functions.
- Produces: `omawsl_install_lazydocker` (no args), `omawsl_install_zellij` (no args).

- [ ] **Step 1: Write the failing tests**

Replace `tests/apps_terminal_test.bats` entirely:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/terminal/apps-terminal.sh"
  stub_command sudo
  stub_command curl
  stub_command tar
  stub_hide_command lazydocker zellij
}

@test "installs the full Omakub-parity terminal tool set via apt, including the newly-folded-in always-on tools" {
  run omawsl_install_terminal_apps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop fastfetch lazygit"* ]]
}

@test "installs lazydocker via its official script when not already present" {
  run omawsl_install_lazydocker
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh"* ]]
}

@test "skips lazydocker when already installed" {
  stub_command lazydocker
  run omawsl_install_lazydocker
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"install_update_linux.sh"* ]]
}

@test "installs zellij via its GitHub release when not already present" {
  run omawsl_install_zellij
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://github.com/zellij-org/zellij/releases/latest/download/zellij-"*"-unknown-linux-musl.tar.gz"* ]]
  [[ "$(stub_calls)" == *"sudo install -m 0755 /tmp/zellij /usr/local/bin/zellij"* ]]
}

@test "skips zellij when already installed" {
  stub_command zellij
  run omawsl_install_zellij
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"unknown-linux-musl"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/apps_terminal_test.bats"
```
Expected: the apt-list test FAILs (missing tools in the expected string); the lazydocker/zellij tests FAIL with "command not found" (functions don't exist yet).

- [ ] **Step 3: Update `install/terminal/apps-terminal.sh`**

Replace the file's contents entirely:

```bash
#!/usr/bin/env bash
set -euo pipefail

# omawsl_install_terminal_apps
# Always-on terminal tooling, no picker gate. Installs via apt where a
# stable Ubuntu package exists (verified against Ubuntu 26.04's own
# universe repo: fzf, ripgrep, bat, eza, zoxide, plocate, apache2-utils,
# fd-find, gh, btop, fastfetch, lazygit all have candidates there), plus
# two tools with no Ubuntu package at all (lazydocker, zellij), each
# installed via its own official method below.
omawsl_install_terminal_apps() {
  sudo apt-get update -qq
  sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop fastfetch lazygit

  omawsl_install_lazydocker
  omawsl_install_zellij
}

# omawsl_install_lazydocker
# No Ubuntu package exists for lazydocker - installs via its official
# script (jesseduffield/lazydocker), which installs to $HOME/.local/bin
# by default (already on PATH via configs/bashrc). The script itself
# always re-downloads/reinstalls unconditionally - this command -v guard
# is what actually makes this idempotent.
omawsl_install_lazydocker() {
  if command -v lazydocker &>/dev/null; then
    return 0
  fi
  curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
}

# omawsl_install_zellij
# No Ubuntu package exists for zellij either. Installs the official
# prebuilt musl binary release directly from GitHub rather than the
# project's own `bash <(curl .../launch)` one-liner, so the exact steps
# stay auditable here instead of delegating to an unseen remote script.
# `/releases/latest/download/<asset>` always resolves to the current
# release, so no separate version-lookup step is needed.
omawsl_install_zellij() {
  if command -v zellij &>/dev/null; then
    return 0
  fi
  local arch
  arch="$(uname -m)"
  curl -fsSL "https://github.com/zellij-org/zellij/releases/latest/download/zellij-${arch}-unknown-linux-musl.tar.gz" | tar -xz -C /tmp
  sudo install -m 0755 /tmp/zellij /usr/local/bin/zellij
  rm -f /tmp/zellij
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_terminal_apps
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/apps_terminal_test.bats"
```
Expected: `5 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal/apps-terminal.sh tests/apps_terminal_test.bats
git commit -m "feat: fold gh/btop/fastfetch/lazygit/lazydocker/zellij into apps-terminal.sh"
```

---

### Task 2: `lib.sh` reachability helpers + `windows-prereq-checklist.sh` VS Code/Cursor items

**Files:**
- Modify: `install/lib.sh`
- Modify: `install/windows-prereq-checklist.sh`
- Modify: `tests/lib_test.bats`
- Modify: `tests/windows_prereq_checklist_test.bats`

**Interfaces:**
- Produces: `omawsl_code_reachable` (exit 0/1), `omawsl_cursor_reachable` (exit 0/1) — used by Tasks 3 and 4's detect-and-defer checks, and by this task's checklist extension.

- [ ] **Step 1: Write the failing tests**

Append to `tests/lib_test.bats`:

```bash

@test "omawsl_code_reachable: true when a code command is present" {
  stub_command code
  run omawsl_code_reachable
  [ "$status" -eq 0 ]
}

@test "omawsl_code_reachable: false when nothing named code is on PATH" {
  run bash -c '
    export PATH=/nonexistent
    source "'"$REPO_ROOT"'/install/lib.sh"
    omawsl_code_reachable
  '
  [ "$status" -eq 1 ]
}

@test "omawsl_cursor_reachable: true when a cursor command is present" {
  stub_command cursor
  run omawsl_cursor_reachable
  [ "$status" -eq 0 ]
}

@test "omawsl_cursor_reachable: false when nothing named cursor is on PATH" {
  run bash -c '
    export PATH=/nonexistent
    source "'"$REPO_ROOT"'/install/lib.sh"
    omawsl_cursor_reachable
  '
  [ "$status" -eq 1 ]
}
```

Append to `tests/windows_prereq_checklist_test.bats`:

```bash

@test "real checklist: shows a VS Code item when chosen and code isn't reachable" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_EDITORS="VS Code"
    export PATH=/nonexistent
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"VS Code"* ]]
  [[ "$output" == *"docs/windows-setup.md#vscode"* ]]
}

@test "real checklist: shows nothing for VS Code when code is already reachable" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_EDITORS="VS Code"
    code() { :; }
    export -f code
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "real checklist: shows a Cursor item when chosen and cursor isn't reachable" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_EDITORS="Cursor"
    export PATH=/nonexistent
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Cursor"* ]]
  [[ "$output" == *"docs/windows-setup.md#cursor"* ]]
}

@test "real checklist: shows nothing when neither VS Code nor Cursor was chosen" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_EDITORS="Neovim"
    export PATH=/nonexistent
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/lib_test.bats tests/windows_prereq_checklist_test.bats"
```
Expected: the 4 new `lib_test.bats` tests FAIL (`command not found`); the 4 new checklist tests FAIL (VS Code/Cursor never mentioned yet).

- [ ] **Step 3: Add the two helpers to `install/lib.sh`**

Append to `install/lib.sh`:

```bash

# omawsl_code_reachable
# True if VS Code's `code` CLI is reachable (via Win32 interop once VS
# Code is installed on Windows). Shared by windows-prereq-checklist.sh
# and app-vscode.sh's own detect-and-defer check (design spec §6, §10).
omawsl_code_reachable() {
  command -v code &>/dev/null
}

# omawsl_cursor_reachable
# Same shape as omawsl_code_reachable, for Cursor's `cursor` CLI.
omawsl_cursor_reachable() {
  command -v cursor &>/dev/null
}
```

- [ ] **Step 4: Update `omawsl_windows_checklist_items` in `install/windows-prereq-checklist.sh`**

Replace:
```bash
omawsl_windows_checklist_items() {
  if [[ "${OMAWSL_DOCKER_MODE:-}" == "Docker Desktop for Windows" ]] && ! omawsl_docker_reachable; then
    echo "  - Docker Desktop - docs/windows-setup.md#docker-desktop (install it, enable WSL integration for this distro, verify 'docker' is reachable)"
  fi
}
```
with:
```bash
# omawsl_windows_checklist_items
# Prints zero or more lines, each describing one pending Windows-side
# prerequisite relevant to what was actually selected. Phase 4 adds VS
# Code and Cursor - shown only if that editor was chosen and its CLI
# isn't already reachable (design spec §6, §10). Later phases extend this
# function further rather than restructuring it.
omawsl_windows_checklist_items() {
  if [[ "${OMAWSL_DOCKER_MODE:-}" == "Docker Desktop for Windows" ]] && ! omawsl_docker_reachable; then
    echo "  - Docker Desktop - docs/windows-setup.md#docker-desktop (install it, enable WSL integration for this distro, verify 'docker' is reachable)"
  fi

  if omawsl_list_has "${OMAWSL_EDITORS:-}" "VS Code" && ! omawsl_code_reachable; then
    echo "  - VS Code - docs/windows-setup.md#vscode (install it, enable the WSL extension, verify 'code' is on PATH)"
  fi

  if omawsl_list_has "${OMAWSL_EDITORS:-}" "Cursor" && ! omawsl_cursor_reachable; then
    echo "  - Cursor - docs/windows-setup.md#cursor (install it, connect to this WSL distro once, verify 'cursor' is on PATH)"
  fi
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/lib_test.bats tests/windows_prereq_checklist_test.bats"
```
Expected: `23 tests, 0 failures` for `lib_test.bats` (19 prior + 4 new), `10 tests, 0 failures` for `windows_prereq_checklist_test.bats` (6 prior + 4 new).

- [ ] **Step 6: Commit**

```bash
git add install/lib.sh install/windows-prereq-checklist.sh tests/lib_test.bats tests/windows_prereq_checklist_test.bats
git commit -m "feat: add VS Code/Cursor reachability helpers and checklist items"
```

---

### Task 3: `configs/vscode.json` + `install/terminal/app-vscode.sh`

**Files:**
- Create: `configs/vscode.json`
- Create: `install/terminal/app-vscode.sh`
- Create: `tests/app_vscode_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has` (Phase 1), `omawsl_code_reachable` (Task 2)
- Produces: `omawsl_install_vscode` (no args), `omawsl_install_vscode_settings [settings_file]`.

- [ ] **Step 1: Write the failing tests**

Create `tests/app_vscode_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-vscode.sh"
}

@test "no-ops entirely when VS Code isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.vscode-server/data/Machine/settings.json" ]
}

@test "deploys settings and installs the Remote-WSL extension when code is reachable" {
  export OMAWSL_EDITORS="VS Code"
  stub_command code
  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ -f "$HOME/.vscode-server/data/Machine/settings.json" ]
  diff "$HOME/.vscode-server/data/Machine/settings.json" "$REPO_ROOT/configs/vscode.json"
  [[ "$(stub_calls)" == *"code --install-extension ms-vscode-remote.remote-wsl"* ]]
}

@test "deploys settings but defers the extension install when code isn't reachable" {
  stub_hide_command code
  export OMAWSL_EDITORS="VS Code"
  run omawsl_install_vscode
  [ "$status" -eq 0 ]
  [ -f "$HOME/.vscode-server/data/Machine/settings.json" ]
  [[ "$(stub_calls)" != *"code --install-extension"* ]]
  [[ "$output" == *"VS Code isn't reachable yet"* ]]
  [[ "$output" == *"docs/windows-setup.md#vscode"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_vscode_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Write `configs/vscode.json`**

```json
{
  "terminal.integrated.defaultProfile.linux": "bash",
  "editor.fontFamily": "'CaskaydiaCove Nerd Font', 'Cascadia Code', monospace",
  "editor.fontLigatures": true,
  "editor.formatOnSave": true,
  "files.trimTrailingWhitespace": true,
  "workbench.colorTheme": "Default Dark Modern"
}
```

- [ ] **Step 4: Write `install/terminal/app-vscode.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_vscode_settings [settings_file]
# Deploys configs/vscode.json to VS Code Remote-WSL's machine-level
# settings file. This directory doesn't exist until VS Code has connected
# to this WSL distro via Remote-WSL at least once - creating it ahead of
# time means the settings apply automatically the first time it does
# (design spec §10: "inert until VS Code exists ... pick up automatically
# once it does"), regardless of whether `code` is reachable right now.
omawsl_install_vscode_settings() {
  local settings_file="${1:-$HOME/.vscode-server/data/Machine/settings.json}"
  mkdir -p "$(dirname "$settings_file")"
  cp "$SCRIPT_DIR/../../configs/vscode.json" "$settings_file"
}

# omawsl_install_vscode
# VS Code is a Windows-side GUI app omawsl never auto-installs (design
# spec §2, §10). Detect-and-defer: the settings file above always gets
# deployed (inert until VS Code exists); if `code` isn't reachable via
# Win32 interop, only the one step needing the live binary (installing
# the Remote-WSL extension) is skipped, with a message pointing at
# docs/windows-setup.md. No-ops entirely if VS Code wasn't selected.
omawsl_install_vscode() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "VS Code"; then
    return 0
  fi

  omawsl_install_vscode_settings

  if omawsl_code_reachable; then
    code --install-extension ms-vscode-remote.remote-wsl
  else
    echo "omawsl: VS Code isn't reachable yet - install it on Windows, then run 'code --install-extension ms-vscode-remote.remote-wsl' yourself, or re-run install.sh."
    echo "See docs/windows-setup.md#vscode for the full steps."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_vscode
fi
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_vscode_test.bats"
```
Expected: `3 tests, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add configs/vscode.json install/terminal/app-vscode.sh tests/app_vscode_test.bats
git commit -m "feat: add app-vscode.sh (Remote-WSL settings + extension detect-and-defer)"
```

---

### Task 4: `install/terminal/app-cursor.sh`

**Files:**
- Create: `install/terminal/app-cursor.sh`
- Create: `tests/app_cursor_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has` (Phase 1), `omawsl_cursor_reachable` (Task 2), `configs/vscode.json` (Task 3)
- Produces: `omawsl_install_cursor` (no args).

- [ ] **Step 1: Write the failing tests**

Create `tests/app_cursor_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-cursor.sh"
}

@test "no-ops entirely when Cursor isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_cursor
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.cursor-server/data/Machine/settings.json" ]
}

@test "deploys the shared settings file when cursor is reachable" {
  export OMAWSL_EDITORS="Cursor"
  stub_command cursor
  run omawsl_install_cursor
  [ "$status" -eq 0 ]
  [ -f "$HOME/.cursor-server/data/Machine/settings.json" ]
  diff "$HOME/.cursor-server/data/Machine/settings.json" "$REPO_ROOT/configs/vscode.json"
}

@test "deploys settings and prints a deferral message when cursor isn't reachable" {
  stub_hide_command cursor
  export OMAWSL_EDITORS="Cursor"
  run omawsl_install_cursor
  [ "$status" -eq 0 ]
  [ -f "$HOME/.cursor-server/data/Machine/settings.json" ]
  [[ "$output" == *"Cursor isn't reachable yet"* ]]
  [[ "$output" == *"docs/windows-setup.md#cursor"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_cursor_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Write `install/terminal/app-cursor.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_cursor
# Cursor is a Windows-side GUI app (a VS Code fork) omawsl never
# auto-installs (design spec §2, §10) - same detect-and-defer shape as
# app-vscode.sh. Cursor reads the same settings.json keys as VS Code, so
# it shares the exact same configs/vscode.json baseline (design spec
# §11). Deliberately does NOT attempt a `cursor --install-extension`
# step the way app-vscode.sh does for VS Code: Cursor has its own
# extension distribution, and Microsoft's marketplace commonly blocks
# non-VS-Code products from installing Microsoft-published extensions -
# not specified precisely enough in the design spec to assume it works,
# so this only deploys what's clearly specified (shared settings).
omawsl_install_cursor() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Cursor"; then
    return 0
  fi

  local settings_file="$HOME/.cursor-server/data/Machine/settings.json"
  mkdir -p "$(dirname "$settings_file")"
  cp "$SCRIPT_DIR/../../configs/vscode.json" "$settings_file"

  if ! omawsl_cursor_reachable; then
    echo "omawsl: Cursor isn't reachable yet - install it on Windows and connect to this WSL distro once; the settings above will apply automatically."
    echo "See docs/windows-setup.md#cursor for the full steps."
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_cursor
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_cursor_test.bats"
```
Expected: `3 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal/app-cursor.sh tests/app_cursor_test.bats
git commit -m "feat: add app-cursor.sh (shared VS Code/Cursor settings, no extension install)"
```

---

### Task 5: `install/terminal/app-neovim.sh`

**Files:**
- Create: `install/terminal/app-neovim.sh`
- Create: `tests/app_neovim_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has` (Phase 1)
- Produces: `omawsl_install_neovim` (no args).

- [ ] **Step 1: Write the failing tests**

Create `tests/app_neovim_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-neovim.sh"
  stub_command sudo
  stub_command git
}

@test "no-ops entirely when Neovim isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_neovim
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "installs neovim and bootstraps LazyVim's starter config" {
  export OMAWSL_EDITORS="Neovim"
  run omawsl_install_neovim
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y neovim"* ]]
  [[ "$(stub_calls)" == *"git clone https://github.com/LazyVim/starter $HOME/.config/nvim"* ]]
}

@test "does not overwrite an existing nvim config" {
  export OMAWSL_EDITORS="Neovim"
  mkdir -p "$HOME/.config/nvim"
  echo "existing config" > "$HOME/.config/nvim/init.lua"
  run omawsl_install_neovim
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"git clone"* ]]
  [ "$(cat "$HOME/.config/nvim/init.lua")" = "existing config" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_neovim_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Write `install/terminal/app-neovim.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_neovim
# Purely WSL-side, no Windows dependency (design spec §10). Installs
# Neovim via apt, then bootstraps LazyVim using its own official starter
# template (github.com/LazyVim/starter) rather than hand-authoring Lua
# config files - the cloned .git directory is removed afterward, matching
# LazyVim's own documented setup instructions. Skipped entirely if
# ~/.config/nvim already exists, so a user's own existing Neovim config
# is never overwritten.
omawsl_install_neovim() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Neovim"; then
    return 0
  fi

  sudo apt-get update -qq
  sudo apt-get install -y neovim

  if [[ ! -d "$HOME/.config/nvim" ]]; then
    git clone https://github.com/LazyVim/starter "$HOME/.config/nvim"
    rm -rf "$HOME/.config/nvim/.git"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_neovim
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_neovim_test.bats"
```
Expected: `3 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal/app-neovim.sh tests/app_neovim_test.bats
git commit -m "feat: add app-neovim.sh (Neovim + LazyVim's official starter config)"
```

---

### Task 6: `install/terminal/app-opencode.sh`

**Files:**
- Modify: `configs/bashrc`
- Create: `install/terminal/app-opencode.sh`
- Create: `tests/app_opencode_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has` (Phase 1)
- Produces: `omawsl_install_opencode` (no args).

- [ ] **Step 1: Write the failing tests**

Create `tests/app_opencode_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-opencode.sh"
  stub_command curl
}

@test "no-ops entirely when opencode isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_opencode
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "installs via the official installer when not already present" {
  export OMAWSL_EDITORS="opencode"
  run omawsl_install_opencode
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://opencode.ai/install"* ]]
}

@test "no-ops when already installed" {
  export OMAWSL_EDITORS="opencode"
  stub_command opencode
  run omawsl_install_opencode
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_opencode_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Update `configs/bashrc`**

Add this block right after the existing `$HOME/.local/bin` block (which currently ends the file):

```bash

# opencode's installer places its binary here, not $HOME/.local/bin like
# mise/lazydocker/claude - needs its own PATH entry.
if [ -d "$HOME/.opencode/bin" ]; then
  export PATH="$HOME/.opencode/bin:$PATH"
fi
```

- [ ] **Step 4: Write `install/terminal/app-opencode.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_opencode
# opencode.ai's terminal AI coding agent CLI - purely WSL-side, no
# Windows dependency (design spec §10). Installs via its official
# installer, which places the binary at $HOME/.opencode/bin/opencode
# (configs/bashrc adds that directory to PATH). Idempotent via a
# command -v guard, since the installer itself always re-downloads
# unconditionally.
omawsl_install_opencode() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "opencode"; then
    return 0
  fi

  if command -v opencode &>/dev/null; then
    return 0
  fi

  curl -fsSL https://opencode.ai/install | bash
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_opencode
fi
```

- [ ] **Step 5: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_opencode_test.bats"
```
Expected: `3 tests, 0 failures`.

- [ ] **Step 6: Commit**

```bash
git add configs/bashrc install/terminal/app-opencode.sh tests/app_opencode_test.bats
git commit -m "feat: add app-opencode.sh (installs to \$HOME/.opencode/bin, new PATH entry)"
```

---

### Task 7: `install/terminal/app-claude-cli.sh`

**Files:**
- Create: `install/terminal/app-claude-cli.sh`
- Create: `tests/app_claude_cli_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has` (Phase 1)
- Produces: `omawsl_install_claude_cli` (no args).

- [ ] **Step 1: Write the failing tests**

Create `tests/app_claude_cli_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-claude-cli.sh"
  stub_command curl
}

@test "no-ops entirely when Claude Code CLI isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_claude_cli
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "installs via the official installer when not already present" {
  export OMAWSL_EDITORS="Claude Code CLI"
  run omawsl_install_claude_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://claude.ai/install.sh"* ]]
}

@test "no-ops when already installed" {
  export OMAWSL_EDITORS="Claude Code CLI"
  stub_command claude
  run omawsl_install_claude_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_claude_cli_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Write `install/terminal/app-claude-cli.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_claude_cli
# Claude Code CLI - purely WSL-side, no Windows dependency (design spec
# §10). Installs via its official native-binary installer (Anthropic's
# own recommended method, avoiding an npm/Node dependency entirely).
# Idempotent via a command -v guard.
omawsl_install_claude_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Claude Code CLI"; then
    return 0
  fi

  if command -v claude &>/dev/null; then
    return 0
  fi

  curl -fsSL https://claude.ai/install.sh | bash
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_claude_cli
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_claude_cli_test.bats"
```
Expected: `3 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal/app-claude-cli.sh tests/app_claude_cli_test.bats
git commit -m "feat: add app-claude-cli.sh (official native-binary installer)"
```

---

### Task 8: `install/terminal/app-codex-cli.sh`

**Files:**
- Create: `install/terminal/app-codex-cli.sh`
- Create: `tests/app_codex_cli_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has` (Phase 1)
- Produces: `omawsl_install_codex_cli` (no args).

- [ ] **Step 1: Write the failing tests**

Create `tests/app_codex_cli_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-codex-cli.sh"
  stub_command mise
}

@test "no-ops entirely when Codex CLI isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_codex_cli
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
  [ ! -f "$HOME/.local/bin/codex" ]
}

@test "installs via a private mise-managed Node and writes a wrapper" {
  export OMAWSL_EDITORS="Codex CLI"
  run omawsl_install_codex_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @openai/codex"* ]]
  [ -x "$HOME/.local/bin/codex" ]
  [[ "$(cat "$HOME/.local/bin/codex")" == *"exec mise exec node@lts -- codex"* ]]
}

@test "no-ops when already installed" {
  export OMAWSL_EDITORS="Codex CLI"
  stub_command codex
  run omawsl_install_codex_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"npm install"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_codex_cli_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Write `install/terminal/app-codex-cli.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_codex_cli
# OpenAI Codex CLI - purely WSL-side, no Windows dependency (design spec
# §10). Its only distribution channel is npm (@openai/codex), so this
# uses a private mise-managed Node runtime to install it (`mise exec
# node@lts`), rather than depending on whether the user separately picked
# Node.js in the language picker - that picker is about the user's own
# project runtime, not an implementation detail of an unrelated tool
# (design spec §10). A thin wrapper at $HOME/.local/bin/codex (already on
# PATH) re-resolves through `mise exec` on every invocation, rather than
# relying on mise's shim mechanism to expose a binary from an ad-hoc
# `mise exec`-driven npm global install - deliberately explicit rather
# than assumed, after Phase 3 found a real bug in the analogous "does
# mise make this reachable automatically" assumption for Rails' gem.
# Idempotent via a command -v guard.
omawsl_install_codex_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Codex CLI"; then
    return 0
  fi

  if command -v codex &>/dev/null; then
    return 0
  fi

  mise exec node@lts -- npm install -g @openai/codex

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/codex" <<'WRAPPER'
#!/usr/bin/env bash
exec mise exec node@lts -- codex "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/codex"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_codex_cli
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_codex_cli_test.bats"
```
Expected: `3 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal/app-codex-cli.sh tests/app_codex_cli_test.bats
git commit -m "feat: add app-codex-cli.sh (private mise-managed Node + explicit wrapper)"
```

---

### Task 9: `install/terminal/app-gemini-cli.sh`

**Files:**
- Create: `install/terminal/app-gemini-cli.sh`
- Create: `tests/app_gemini_cli_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has` (Phase 1)
- Produces: `omawsl_install_gemini_cli` (no args).

- [ ] **Step 1: Write the failing tests**

Create `tests/app_gemini_cli_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-gemini-cli.sh"
  stub_command mise
}

@test "no-ops entirely when Gemini CLI isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_gemini_cli
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
  [ ! -f "$HOME/.local/bin/gemini" ]
}

@test "installs via a private mise-managed Node and writes a wrapper" {
  export OMAWSL_EDITORS="Gemini CLI"
  run omawsl_install_gemini_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @google/gemini-cli"* ]]
  [ -x "$HOME/.local/bin/gemini" ]
  [[ "$(cat "$HOME/.local/bin/gemini")" == *"exec mise exec node@lts -- gemini"* ]]
}

@test "no-ops when already installed" {
  export OMAWSL_EDITORS="Gemini CLI"
  stub_command gemini
  run omawsl_install_gemini_cli
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"npm install"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_gemini_cli_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Write `install/terminal/app-gemini-cli.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_gemini_cli
# Same shape as app-codex-cli.sh: Gemini CLI's only distribution channel
# is npm (@google/gemini-cli), so this uses a private mise-managed Node
# runtime plus an explicit $HOME/.local/bin/gemini wrapper (see
# app-codex-cli.sh's comment for why the wrapper, not a bare mise shim).
omawsl_install_gemini_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Gemini CLI"; then
    return 0
  fi

  if command -v gemini &>/dev/null; then
    return 0
  fi

  mise exec node@lts -- npm install -g @google/gemini-cli

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/gemini" <<'WRAPPER'
#!/usr/bin/env bash
exec mise exec node@lts -- gemini "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/gemini"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_gemini_cli
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_gemini_cli_test.bats"
```
Expected: `3 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal/app-gemini-cli.sh tests/app_gemini_cli_test.bats
git commit -m "feat: add app-gemini-cli.sh (private mise-managed Node + explicit wrapper)"
```

---

### Task 10: `install/terminal/app-gh-copilot.sh`

**Files:**
- Create: `install/terminal/app-gh-copilot.sh`
- Create: `tests/app_gh_copilot_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has` (Phase 1), `gh` (Task 1, now always installed)
- Produces: `omawsl_install_gh_copilot` (no args).

- [ ] **Step 1: Write the failing tests**

Create `tests/app_gh_copilot_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/app-gh-copilot.sh"
  stub_command gh
}

@test "no-ops entirely when GitHub Copilot CLI isn't selected" {
  export OMAWSL_EDITORS=""
  run omawsl_install_gh_copilot
  [ "$status" -eq 0 ]
  [ -z "$(stub_calls)" ]
}

@test "installs the gh-copilot extension when selected" {
  export OMAWSL_EDITORS="GitHub Copilot CLI"
  run omawsl_install_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gh extension install github/gh-copilot"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_gh_copilot_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Write `install/terminal/app-gh-copilot.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_gh_copilot
# GitHub Copilot CLI, installed as a gh extension - depends only on gh
# itself, which apps-terminal.sh now installs unconditionally regardless
# of any picker (Task 1), so there's no cross-picker dependency gap here
# (design spec §10). Actual usability still depends on an authenticated
# gh session and an active Copilot subscription - a README-level runtime
# concern, not an install-time failure.
omawsl_install_gh_copilot() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "GitHub Copilot CLI"; then
    return 0
  fi

  gh extension install github/gh-copilot
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_gh_copilot
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/app_gh_copilot_test.bats"
```
Expected: `2 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal/app-gh-copilot.sh tests/app_gh_copilot_test.bats
git commit -m "feat: add app-gh-copilot.sh (gh extension install)"
```

---

### Task 11: Wire all 8 editor/AI-tool scripts into `install/terminal.sh`

**Files:**
- Modify: `install/terminal.sh`
- Modify: `tests/terminal_test.bats`

**Interfaces:**
- Consumes: `omawsl_install_vscode` (Task 3), `omawsl_install_cursor` (Task 4), `omawsl_install_neovim` (Task 5), `omawsl_install_opencode` (Task 6), `omawsl_install_claude_cli` (Task 7), `omawsl_install_codex_cli` (Task 8), `omawsl_install_gemini_cli` (Task 9), `omawsl_install_gh_copilot` (Task 10)

- [ ] **Step 1: Write the failing test**

Replace the `@test` in `tests/terminal_test.bats` (`setup()` from Phase 3 is unchanged - `OMAWSL_EDITORS` stays unset/empty, so all 8 new scripts no-op cleanly and need no new stubs; add `stub_command gh` defensively since apps-terminal.sh's apt list now includes it, though the apt-get call itself doesn't need gh to actually exist):

```bash
@test "runs every terminal script in the documented fixed order" {
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  run bash "$REPO_ROOT/install/terminal.sh"
  [ "$status" -eq 0 ]

  actual_order="$(echo "$output" | grep "^omawsl: running" | sed 's/^omawsl: running //')"
  expected_order="terminal/required/app-gum.sh
terminal/identification.sh
terminal/a-shell.sh
terminal/apps-terminal.sh
terminal/docker.sh
terminal/mise.sh
terminal/select-dev-language.sh
terminal/cloud-tools.sh
terminal/select-dev-storage.sh
terminal/app-vscode.sh
terminal/app-neovim.sh
terminal/app-opencode.sh
terminal/app-cursor.sh
terminal/app-claude-cli.sh
terminal/app-codex-cli.sh
terminal/app-gh-copilot.sh
terminal/app-gemini-cli.sh
terminal/libraries.sh"

  [ "$actual_order" = "$expected_order" ]
  [ -f "$HOME/.bashrc" ]
  [[ "$(stub_calls)" == *"apt-get install -y gum"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/terminal_test.bats"
```
Expected: FAILs (`actual_order` is missing the 8 new entries).

- [ ] **Step 3: Update `install/terminal.sh`**

Replace the `OMAWSL_TERMINAL_SCRIPTS` array and `SCRIPT_FUNCTIONS` map:

```bash
# Fixed order, sourced (not sub-shelled) so a failure stops the whole run
# immediately (design spec §8).
OMAWSL_TERMINAL_SCRIPTS=(
  "terminal/required/app-gum.sh"
  "terminal/identification.sh"
  "terminal/a-shell.sh"
  "terminal/apps-terminal.sh"
  "terminal/docker.sh"
  "terminal/mise.sh"
  "terminal/select-dev-language.sh"
  "terminal/cloud-tools.sh"
  "terminal/select-dev-storage.sh"
  "terminal/app-vscode.sh"
  "terminal/app-neovim.sh"
  "terminal/app-opencode.sh"
  "terminal/app-cursor.sh"
  "terminal/app-claude-cli.sh"
  "terminal/app-codex-cli.sh"
  "terminal/app-gh-copilot.sh"
  "terminal/app-gemini-cli.sh"
  "terminal/libraries.sh"
)

omawsl_run_terminal_scripts() {
  local script
  # Mapping of script paths to their main function names
  declare -A SCRIPT_FUNCTIONS=(
    ["terminal/required/app-gum.sh"]="omawsl_install_gum"
    ["terminal/identification.sh"]="omawsl_identification"
    ["terminal/a-shell.sh"]="omawsl_install_shell_config"
    ["terminal/apps-terminal.sh"]="omawsl_install_terminal_apps"
    ["terminal/docker.sh"]="omawsl_docker"
    ["terminal/mise.sh"]="omawsl_install_mise"
    ["terminal/select-dev-language.sh"]="omawsl_select_dev_language"
    ["terminal/cloud-tools.sh"]="omawsl_cloud_tools"
    ["terminal/select-dev-storage.sh"]="omawsl_install_storage"
    ["terminal/app-vscode.sh"]="omawsl_install_vscode"
    ["terminal/app-neovim.sh"]="omawsl_install_neovim"
    ["terminal/app-opencode.sh"]="omawsl_install_opencode"
    ["terminal/app-cursor.sh"]="omawsl_install_cursor"
    ["terminal/app-claude-cli.sh"]="omawsl_install_claude_cli"
    ["terminal/app-codex-cli.sh"]="omawsl_install_codex_cli"
    ["terminal/app-gh-copilot.sh"]="omawsl_install_gh_copilot"
    ["terminal/app-gemini-cli.sh"]="omawsl_install_gemini_cli"
    ["terminal/libraries.sh"]="omawsl_install_libraries"
  )

  for script in "${OMAWSL_TERMINAL_SCRIPTS[@]}"; do
    echo "omawsl: running $script"
    # shellcheck source=/dev/null
    source "$OMAWSL_INSTALL_DIR/$script"
    # Call the script's main function
    "${SCRIPT_FUNCTIONS[$script]}"
  done
}
```

(The rest of `install/terminal.sh` — shebang, `set -euo pipefail`, `OMAWSL_INSTALL_DIR`, the `lib.sh` source, and the final auto-run guard — is unchanged.)

- [ ] **Step 4: Run test to verify it passes**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/terminal_test.bats"
```
Expected: `1 test, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal.sh tests/terminal_test.bats
git commit -m "feat: wire all 8 editor/AI-tool scripts into terminal.sh's dispatch table"
```

---

### Task 12: Update `tests/install_test.bats` for full end-to-end coverage

**Files:**
- Modify: `tests/install_test.bats`

**Interfaces:** none new — this task only extends coverage of `install.sh` now that it exercises editors/AI tooling too.

- [ ] **Step 1: Write the failing tests**

Replace `tests/install_test.bats`'s `setup()` and first `@test` (leave the second `@test`, "choosing Docker Desktop surfaces...", exactly as-is - it's unaffected by this phase):

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  gum_stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  stub_command sudo
  stub_command git
  stub_command curl
  stub_command gpg
  stub_command mise
  stub_command gem
  stub_command tar
  stub_command gh
  stub_hide_command docker terraform az lazydocker zellij code cursor claude codex gemini opencode

  export OMAWSL_WSL_CONF_FILE="$BATS_TEST_TMPDIR/wsl.conf"
  printf '[boot]\nsystemd=true\n' > "$OMAWSL_WSL_CONF_FILE"
  export OMAWSL_DOCKER_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/docker.list"
  export OMAWSL_DOCKER_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  # Pre-seed every third-party apt sources file this run could touch as
  # already-existing, so each one takes its "already configured" branch
  # and skips its curl|gpg / echo|tee repo-add pipes (Phase 2's Task 5
  # SIGPIPE-avoidance pattern - already covered directly elsewhere).
  : > "$OMAWSL_DOCKER_APT_SOURCES_FILE"
  export OMAWSL_TERRAFORM_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/hashicorp.list"
  export OMAWSL_TERRAFORM_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  : > "$OMAWSL_TERRAFORM_APT_SOURCES_FILE"
  export OMAWSL_AZURE_CLI_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/azure-cli.list"
  export OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  : > "$OMAWSL_AZURE_CLI_APT_SOURCES_FILE"
  export USER=testuser
}

@test "runs the full install end to end and writes version state" {
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Engine only, inside WSL (recommended)"
  gum_stub_respond $'VS Code\nNeovim\nGitHub Copilot CLI'
  gum_stub_respond $'Go\nTerraform'
  gum_stub_respond ""
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  run bash "$REPO_ROOT/install.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"install complete"* ]]
  [[ "$output" == *"remember to open a new terminal"* ]]
  [ -f "$HOME/.bashrc" ]
  [ -f "$HOME/.inputrc" ]
  [ -f "$OMAWSL_STATE_DIR/version" ]
  [ "$(cat "$OMAWSL_STATE_DIR/version")" = "$(cat "$REPO_ROOT/version")" ]
  [ -f "$OMAWSL_STATE_DIR/choices.env" ]
  grep -q '^OMAWSL_NETWORK_MODE="Personal / unrestricted"$' "$OMAWSL_STATE_DIR/choices.env"
  grep -q '^OMAWSL_EDITORS="VS Code,Neovim,GitHub Copilot CLI"$' "$OMAWSL_STATE_DIR/choices.env"
  grep -q '^OMAWSL_LANGUAGES="Go,Terraform"$' "$OMAWSL_STATE_DIR/choices.env"
  [[ "$(stub_calls)" == *"sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]
  [[ "$(stub_calls)" == *"mise use --global go@latest"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y terraform"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop fastfetch lazygit"* ]]
  [ -f "$HOME/.vscode-server/data/Machine/settings.json" ]
  [[ "$(stub_calls)" == *"git clone https://github.com/LazyVim/starter $HOME/.config/nvim"* ]]
  [[ "$(stub_calls)" == *"gh extension install github/gh-copilot"* ]]
  [[ "$(stub_calls)" != *"cursor-server"* ]]
  [[ "$(stub_calls)" != *"opencode"* ]]
}
```

- [ ] **Step 2: Run tests to verify the outcome**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/install_test.bats"
```
Expected: `2 tests, 0 failures`. (No production-code implementation step needed here — Tasks 1–11 already made `install.sh` support this; this task is pure test-coverage catch-up.)

- [ ] **Step 3: Run the entire test suite to confirm nothing regressed**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase4-editors-ai-tooling && tests/.bats-core/bin/bats tests/*.bats"
```
Expected: every file's tests pass, zero failures. The exact total isn't critical to pre-compute given how many new files this phase adds — the important thing is zero failures.

- [ ] **Step 4: Commit**

```bash
git add tests/install_test.bats
git commit -m "test: extend install_test.bats for editors + AI tooling end-to-end coverage"
```

---

### Task 13: Manual end-to-end verification (human-in-the-loop)

**Files:** none — this task produces no new code, only a verification record.

This is the one step in this plan the agent executing it should **not** attempt: it requires real network access to several third-party installers/apt repos/npm registries, and real (possibly slow) downloads. Everything up through Task 12 is fully verified by the automated, stubbed test suite — this task is the final "does the real thing actually work, unstubbed" check.

- [ ] **Step 1 (human): Run the real install, picking a representative subset**

From inside the WSL Ubuntu terminal itself:

```bash
bash /mnt/c/Users/tcins/vscode-workspace/omawsl/install.sh
```

You don't need to test all 8 options - picking Neovim (fully WSL-side, no Windows dependency, exercises the LazyVim bootstrap) plus Claude Code CLI (exercises the native-binary installer path) plus GitHub Copilot CLI (exercises the `gh` dependency from Task 1) plus Codex CLI or Gemini CLI (exercises the private mise-managed Node + wrapper path, the part of this phase with the most genuine uncertainty) is enough to cover every distinct install mechanism in this plan without a long wait. VS Code/Cursor answers can be "not selected" unless you actually have one installed on Windows to test the reachable path against - the not-reachable path is already covered by the automated suite.

- [ ] **Step 2 (human): Confirm the always-on tools from Task 1 actually work**

After the run completes with `omawsl: install complete.`, open a **new terminal** and confirm: `gh --version`, `btop --version`, `fastfetch --version`, `lazygit --version`, `lazydocker --version`, `zellij --version` all succeed.

- [ ] **Step 3 (human): Confirm your chosen editor/AI tools actually work**

- If you picked Neovim: `nvim` opens and LazyVim's plugin manager bootstraps on first launch (may take a minute the very first time).
- If you picked Claude Code CLI: `claude --version` succeeds. **This confirms or refutes this plan's flagged assumption that the installer places the binary under `$HOME/.local/bin`** - if `claude` isn't found in the new terminal even though the install step reported success, check where the installer actually placed it (`find $HOME -name claude -type f 2>/dev/null`) and report back; this plan's Environment Notes section will need updating either way.
- If you picked GitHub Copilot CLI: `gh copilot --help` succeeds (shows usage even without being authenticated).
- If you picked Codex CLI: `codex --version` succeeds (via the wrapper).
- If you picked Gemini CLI: `gemini --version` succeeds (via the wrapper).
- If you picked VS Code or Cursor and actually have it installed on Windows: connect to this WSL distro via Remote-WSL/its WSL integration at least once, then confirm the font/theme settings from `configs/vscode.json` took effect.

- [ ] **Step 4 (human): Idempotency check**

Re-run `bash install.sh` a second time end to end (same answers) and confirm it completes cleanly with no errors - every step here should silently no-op or harmlessly re-affirm the second time (matching every `command -v` guard in this phase).

- [ ] **Step 5 (human): Report back**

Tell me either "it worked, here's what I saw" or paste the exact error/output if something broke - particularly anything related to the two flagged assumptions in this plan's Environment Notes (Claude Code CLI's install location; the `mise exec` + wrapper pattern for Codex/Gemini CLI actually producing a working command). A real failure here is more valuable to see than a hypothetical one, as every previous phase's Task N has proven.

- [ ] **Step 6 (human, only once Step 5 confirms success): confirm the commit history is clean**

Run `git log --oneline` and check it reads as a clean, incremental history of Tasks 1–12 (no fixup commits needed). If everything's fine, update `docs/superpowers/plans/roadmap.md`'s Phase 4 entry to "DONE, merged to `master`" (matching Phases 1–3's entry format) and Phase 5 is next.

---

## Self-Review Notes

- **Spec coverage:** §10's editor tooling section (all 8 scripts, each detect-and-defer or WSL-side per its own nature, GitHub Copilot CLI's `gh` dependency) → Tasks 3–10. §6's Windows-side checklist extension for VS Code/Cursor → Task 2. §11's shared VS Code/Cursor settings file → Tasks 3, 4. §7's always-on terminal tools (a genuine gap in the 7-phase roadmap, not originally scoped to any phase, folded in per explicit user decision) → Task 1. §15's "runnable in isolation" → every task's tests call each script's functions directly with explicit env vars. Everything else in the design spec (theming, Windows-side docs beyond the checklist pointers, the rest of `bin/omawsl`) is out of scope for Phase 4 per `docs/superpowers/plans/roadmap.md`.
- **Placeholder scan:** no TBD/TODO markers; every step has complete, runnable code. Two genuine, explicitly-flagged unverified assumptions exist (Claude Code CLI's install location; whether `mise exec`-based ad-hoc npm installs need the explicit wrapper this plan uses) - these are documented uncertainty, not placeholders, matching this project's established pattern for `configs/zellij.kdl` keybinding fidelity and the original `bashrc`/`inputrc` fidelity.
- **Type/name consistency check:** `omawsl_install_vscode` (Task 3), `omawsl_install_cursor` (Task 4), `omawsl_install_neovim` (Task 5), `omawsl_install_opencode` (Task 6), `omawsl_install_claude_cli` (Task 7), `omawsl_install_codex_cli` (Task 8), `omawsl_install_gemini_cli` (Task 9), `omawsl_install_gh_copilot` (Task 10) are the exact function names registered in Task 11's `SCRIPT_FUNCTIONS` map. `omawsl_code_reachable`/`omawsl_cursor_reachable` (Task 2) are used identically in Tasks 3 and 4. `configs/vscode.json` (Task 3) is referenced identically by Task 4. `stub_hide_command` (Phase 3) is used consistently across every new test file needing "tool X is not installed."
