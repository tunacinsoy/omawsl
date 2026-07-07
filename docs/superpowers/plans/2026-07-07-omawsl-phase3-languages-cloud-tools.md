# omawsl Phase 3: Languages & Cloud Tools — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `mise.sh` (bootstraps the `mise` version manager), `select-dev-language.sh` (Ruby on Rails, Node.js, Go, PHP, Python, Elixir, Rust, Java via `mise`), and `cloud-tools.sh` (Terraform, Azure CLI via their own third-party apt repos, with explicit failure isolation) to the existing Phase 1+2 skeleton.

**Architecture:** `mise.sh` installs the `mise` binary via its official installer (no stable Ubuntu archive package exists for it) and immediately exports `$HOME/.local/bin` onto the *current* script's `PATH` — not just via `configs/bashrc`, which only takes effect in a new shell — since `select-dev-language.sh` runs moments later in the same sourced session (the same staleness pitfall Phase 2 hit with Docker group membership). `select-dev-language.sh` maps each `OMAWSL_LANGUAGES` selection to a `mise use --global <tool>@latest` call, with Ruby on Rails getting one extra `gem install rails` step. `cloud-tools.sh` installs Terraform and Azure CLI from their own apt repos (HashiCorp's and Microsoft's), each wrapped in a `{ ... } || ok=0` block so a single unreachable third-party mirror reports failure for just that tool and lets the rest of the run continue, rather than letting `set -e` cascade into failing everything after it. All three plug into the existing `terminal.sh` dispatch table, inserted between `docker.sh` and `select-dev-storage.sh` (mise must precede the language picker; docker.sh's real position stays put per Phase 2).

**Tech Stack:** Bash (`set -euo pipefail`), `mise` (https://mise.jdx.dev, installed via `curl https://mise.run | sh`), HashiCorp's and Microsoft's official apt repos for Terraform/Azure CLI, bats-core (already vendored).

## Global Constraints

(Copied verbatim or paraphrased from `docs/superpowers/specs/2026-07-05-omawsl-design.md` §12 and this codebase's own established Phase 1/2 conventions — every task below implicitly inherits these.)

- **Nothing is pre-selected by default** in `OMAWSL_LANGUAGES` (already true since Phase 1's `first-run-choices.sh`), and **selecting nothing is a valid, expected state** — every script here must no-op cleanly, not assume at least one option was picked (§6, §12).
- Membership checks on `OMAWSL_LANGUAGES` go through `omawsl_list_has` (comma-delimited, whole-token match), never a bare substring check (§6).
- **Terraform and Azure CLI each add their own third-party apt repository and GPG key, separate from Ubuntu's own mirrors.** Because every script in this flow runs under `set -e`, `cloud-tools.sh` must isolate a repo-add/`apt-get` failure for one tool (explicit exit-code check, report just that tool as failed, continue) rather than letting it cascade into failing every later step — including the *other* cloud tool and anything that runs after `cloud-tools.sh` in the dispatch order (§12).
- `install/terminal/*.sh` scripts are **sourced, not sub-shelled**, by `terminal.sh` — this is what makes `mise.sh` exporting `PATH` for the current session actually reach `select-dev-language.sh` later in the same run (§8).
- Every install script must be **runnable in isolation** (sourced/called directly with the relevant `OMAWSL_*` vars pre-set) (§15).
- `mise use --global <tool>@latest` re-pins versions harmlessly on re-run — idempotent by construction, no extra guard needed (§7).
- Any filesystem path a script would otherwise hardcode (an apt sources file, a keyrings dir) is resolvable through an `OMAWSL_*` env-var override, mirroring the pattern `lib.sh`'s `OMAWSL_STATE_DIR` and `docker.sh`'s `OMAWSL_DOCKER_APT_SOURCES_FILE`/`OMAWSL_DOCKER_APT_KEYRINGS_DIR` already established (Phase 1/2).
- **A stubbed `sudo`/`curl`/`gpg` sitting on a real pipe's read side can SIGPIPE the write side** when the whole script runs as a freshly exec'd process, since the stub returns instantly without draining stdin while the real writer takes measurably longer (e.g. forking `dpkg`) — found in Phase 2 testing `docker.sh`'s `echo | sudo tee` pipe. Any test that runs `terminal.sh`/`install.sh` as a fresh process (not a direct in-process function call) and exercises Terraform/Azure CLI's repo-add pipes must pre-seed the relevant `OMAWSL_*_APT_SOURCES_FILE` as already-existing to skip that pipe, exactly as Phase 2 did for Docker.

---

## Environment Notes for Whoever Runs This Plan

- Same test instance as Phases 1/2: reachable via `wsl.exe -d Ubuntu -- bash -c "..."`, repo at `/mnt/c/Users/tcins/vscode-workspace/omawsl` inside WSL. Every `.bats` file runs the same way:
  ```
  wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/<branch> && tests/.bats-core/bin/bats tests/<file>.bats"
  ```
- **This WSL instance now has real `docker-ce` installed on it** (from Phase 2's manual verification) — `/usr/bin/docker` and `/bin/docker` are genuinely present. Irrelevant to this phase's own scripts, but relevant if any test here needs to simulate a tool being *absent*: don't assume a fixed "safe" PATH list stays safe forever on this machine (see `tests/install_test.bats`'s Docker Desktop test from Phase 2 for the robust pattern — a shadow PATH directory of symlinks to everything except the one binary being hidden).
- **`mise`, `terraform`, and `azure-cli` are not installed on this machine yet** — every test in this plan stubs `curl`/`gpg`/`sudo`/`mise`/`gem`, never calls the real thing. The one genuinely unstubbed step (real `mise` install, real language toolchain downloads, real Terraform/Azure CLI apt installs) is Task 6, and it is explicitly a **manual task for the human running this plan**.
- Use an isolated git worktree for this phase (same as Phase 2): `git worktree add .worktrees/phase3-languages-cloud-tools -b phase3-languages-cloud-tools`, then re-vendor bats-core inside it (`git clone https://github.com/bats-core/bats-core.git tests/.bats-core` — it's gitignored, so it doesn't carry over from the main checkout).

## File Structure

```
omawsl/
├── install/
│   ├── terminal.sh                         # + mise.sh, select-dev-language.sh, cloud-tools.sh in the dispatch table (Task 4)
│   └── terminal/
│       ├── mise.sh                         # NEW (Task 1)
│       ├── select-dev-language.sh          # NEW (Task 2)
│       └── cloud-tools.sh                  # NEW (Task 3)
└── tests/
    ├── mise_test.bats                      # NEW (Task 1)
    ├── select_dev_language_test.bats       # NEW (Task 2)
    ├── cloud_tools_test.bats               # NEW (Task 3)
    ├── terminal_test.bats                  # updated fixed-order list (Task 4)
    └── install_test.bats                   # updated end-to-end coverage (Task 5)
```

---

### Task 1: `install/terminal/mise.sh`

**Files:**
- Create: `install/terminal/mise.sh`
- Create: `tests/mise_test.bats`

**Interfaces:**
- Produces: `omawsl_install_mise` (no args) — idempotent, exports `$HOME/.local/bin` onto `PATH` for the current session, installs `mise` via its official installer if not already present.

- [ ] **Step 1: Write the failing tests**

Create `tests/mise_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/terminal/mise.sh"
  stub_command curl
}

@test "installs mise via the official installer when not already present" {
  run omawsl_install_mise
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://mise.run"* ]]
}

@test "no-ops when mise is already on PATH" {
  stub_command mise
  run omawsl_install_mise
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "adds \$HOME/.local/bin to PATH for the current session" {
  omawsl_install_mise
  [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase3-languages-cloud-tools && tests/.bats-core/bin/bats tests/mise_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Write `install/terminal/mise.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

# omawsl_install_mise
# Installs mise (https://mise.jdx.dev) via its official installer script -
# no stable Ubuntu archive package exists for it, unlike gum/docker-ce.
# Idempotent: no-ops if mise is already on PATH. Exports $HOME/.local/bin
# onto the CURRENT script's PATH immediately, not just via configs/bashrc
# (which only takes effect in a NEW shell) - select-dev-language.sh runs
# moments later in this same sourced session (terminal.sh sources scripts,
# not sub-shells them), so it needs mise reachable right away. Same
# staleness pitfall as the Docker group-membership issue found in Phase 2.
omawsl_install_mise() {
  export PATH="$HOME/.local/bin:$PATH"

  if command -v mise &>/dev/null; then
    return 0
  fi

  curl -fsSL https://mise.run | sh
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_mise
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase3-languages-cloud-tools && tests/.bats-core/bin/bats tests/mise_test.bats"
```
Expected: `3 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal/mise.sh tests/mise_test.bats
git commit -m "feat: add mise.sh (bootstraps the mise version manager)"
```

---

### Task 2: `install/terminal/select-dev-language.sh`

**Files:**
- Create: `install/terminal/select-dev-language.sh`
- Create: `tests/select_dev_language_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has` (Phase 1, `lib.sh`); `mise` (Task 1, must already be on `PATH` when this runs)
- Produces: `omawsl_select_dev_language` (no args), `omawsl_install_language <mise_tool_name>`.

- [ ] **Step 1: Write the failing tests**

Create `tests/select_dev_language_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/select-dev-language.sh"
  stub_command mise
  stub_command gem
}

@test "installs ruby and rails when Ruby on Rails is selected" {
  export OMAWSL_LANGUAGES="Ruby on Rails"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global ruby@latest"* ]]
  [[ "$(stub_calls)" == *"gem install rails --no-document"* ]]
}

@test "installs node when Node.js is selected" {
  export OMAWSL_LANGUAGES="Node.js"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global node@latest"* ]]
  [[ "$(stub_calls)" != *"gem install"* ]]
}

@test "installs go when Go is selected" {
  export OMAWSL_LANGUAGES="Go"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global go@latest"* ]]
}

@test "installs php when PHP is selected" {
  export OMAWSL_LANGUAGES="PHP"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global php@latest"* ]]
}

@test "installs python when Python is selected" {
  export OMAWSL_LANGUAGES="Python"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global python@latest"* ]]
}

@test "installs elixir when Elixir is selected" {
  export OMAWSL_LANGUAGES="Elixir"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global elixir@latest"* ]]
}

@test "installs rust when Rust is selected" {
  export OMAWSL_LANGUAGES="Rust"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global rust@latest"* ]]
}

@test "installs java when Java is selected" {
  export OMAWSL_LANGUAGES="Java"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global java@latest"* ]]
}

@test "installs multiple languages when several are selected" {
  export OMAWSL_LANGUAGES="Go,Rust,Python"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global go@latest"* ]]
  [[ "$(stub_calls)" == *"mise use --global rust@latest"* ]]
  [[ "$(stub_calls)" == *"mise use --global python@latest"* ]]
  [[ "$(stub_calls)" != *"php"* ]]
  [[ "$(stub_calls)" != *"java"* ]]
}

@test "does not treat Terraform or Azure CLI as languages (cloud-tools.sh's job)" {
  export OMAWSL_LANGUAGES="Terraform,Azure CLI"
  omawsl_select_dev_language
  [[ "$(stub_calls)" != *"mise use"* ]]
}

@test "selecting nothing installs no languages" {
  export OMAWSL_LANGUAGES=""
  omawsl_select_dev_language
  [[ "$(stub_calls)" != *"mise use"* ]]
}

@test "no-ops cleanly when OMAWSL_LANGUAGES is unset entirely" {
  unset OMAWSL_LANGUAGES
  run omawsl_select_dev_language
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"mise use"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase3-languages-cloud-tools && tests/.bats-core/bin/bats tests/select_dev_language_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Write `install/terminal/select-dev-language.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_language <mise_tool_name>
# Idempotent by construction: `mise use --global` re-pins an already-set
# version harmlessly (design spec §7).
omawsl_install_language() {
  local mise_tool="$1"
  mise use --global "${mise_tool}@latest"
}

# omawsl_select_dev_language
# Installs one mise-managed tool per selection in OMAWSL_LANGUAGES.
# Terraform and Azure CLI live in this same picker but are cloud-tools.sh's
# job, not this script's (design spec §6, §12). Nothing is pre-selected by
# default and selecting nothing is a valid, expected state - each branch
# below no-ops cleanly if its option wasn't picked.
omawsl_select_dev_language() {
  local languages="${OMAWSL_LANGUAGES:-}"

  if omawsl_list_has "$languages" "Ruby on Rails"; then
    omawsl_install_language ruby
    gem install rails --no-document
  fi

  if omawsl_list_has "$languages" "Node.js"; then
    omawsl_install_language node
  fi

  if omawsl_list_has "$languages" "Go"; then
    omawsl_install_language go
  fi

  if omawsl_list_has "$languages" "PHP"; then
    omawsl_install_language php
  fi

  if omawsl_list_has "$languages" "Python"; then
    omawsl_install_language python
  fi

  if omawsl_list_has "$languages" "Elixir"; then
    omawsl_install_language elixir
  fi

  if omawsl_list_has "$languages" "Rust"; then
    omawsl_install_language rust
  fi

  if omawsl_list_has "$languages" "Java"; then
    omawsl_install_language java
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_select_dev_language
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase3-languages-cloud-tools && tests/.bats-core/bin/bats tests/select_dev_language_test.bats"
```
Expected: `11 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal/select-dev-language.sh tests/select_dev_language_test.bats
git commit -m "feat: add select-dev-language.sh (8 mise-managed languages, Rails gem on top of ruby)"
```

---

### Task 3: `install/terminal/cloud-tools.sh`

**Files:**
- Create: `install/terminal/cloud-tools.sh`
- Create: `tests/cloud_tools_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has` (Phase 1, `lib.sh`)
- Produces: `omawsl_cloud_tools` (no args), `omawsl_install_terraform [apt_sources_file] [keyrings_dir]`, `omawsl_install_azure_cli [apt_sources_file] [keyrings_dir]`.

- [ ] **Step 1: Write the failing tests**

Create `tests/cloud_tools_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/cloud-tools.sh"
  stub_command sudo
  stub_command gpg
}

# --- omawsl_install_terraform ------------------------------------------------

@test "terraform: installs via apt when not already present" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/hashicorp.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_terraform "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://apt.releases.hashicorp.com/gpg"* ]]
  [[ "$(stub_calls)" == *"sudo gpg --dearmor -o $keyrings_dir/hashicorp.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo tee $sources_file"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y terraform"* ]]
}

@test "terraform: no-ops when already installed" {
  stub_command curl
  stub_command terraform
  run omawsl_install_terraform "$BATS_TEST_TMPDIR/hashicorp.list" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "terraform: skips the repo-add step when the sources file already exists" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/hashicorp-existing.list"
  : > "$sources_file"
  run omawsl_install_terraform "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y terraform"* ]]
}

@test "terraform: isolates a repo-add failure instead of aborting" {
  stub_command curl 1
  sources_file="$BATS_TEST_TMPDIR/hashicorp-fail.list"
  run omawsl_install_terraform "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Terraform install failed"* ]]
  [[ "$(stub_calls)" != *"apt-get install -y terraform"* ]]
}

# --- omawsl_install_azure_cli -------------------------------------------------

@test "azure-cli: installs via apt when not already present" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/azure-cli.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_azure_cli "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"curl -fsSL https://packages.microsoft.com/keys/microsoft.asc"* ]]
  [[ "$(stub_calls)" == *"sudo gpg --dearmor -o $keyrings_dir/microsoft.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo tee $sources_file"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y azure-cli"* ]]
}

@test "azure-cli: no-ops when already installed" {
  stub_command curl
  stub_command az
  run omawsl_install_azure_cli "$BATS_TEST_TMPDIR/azure-cli.list" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
}

@test "azure-cli: skips the repo-add step when the sources file already exists" {
  stub_command curl
  sources_file="$BATS_TEST_TMPDIR/azure-cli-existing.list"
  : > "$sources_file"
  run omawsl_install_azure_cli "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y azure-cli"* ]]
}

@test "azure-cli: isolates a repo-add failure instead of aborting" {
  stub_command curl 1
  sources_file="$BATS_TEST_TMPDIR/azure-cli-fail.list"
  run omawsl_install_azure_cli "$sources_file" "$BATS_TEST_TMPDIR/keyrings"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Azure CLI install failed"* ]]
  [[ "$(stub_calls)" != *"apt-get install -y azure-cli"* ]]
}

# --- omawsl_cloud_tools --------------------------------------------------------

@test "cloud_tools: installs both when both are selected" {
  stub_command curl
  export OMAWSL_LANGUAGES="Terraform,Azure CLI"
  omawsl_cloud_tools
  [[ "$(stub_calls)" == *"apt-get install -y terraform"* ]]
  [[ "$(stub_calls)" == *"apt-get install -y azure-cli"* ]]
}

@test "cloud_tools: installs only the one selected" {
  stub_command curl
  export OMAWSL_LANGUAGES="Terraform"
  omawsl_cloud_tools
  [[ "$(stub_calls)" == *"apt-get install -y terraform"* ]]
  [[ "$(stub_calls)" != *"azure-cli"* ]]
}

@test "cloud_tools: selecting neither installs nothing" {
  export OMAWSL_LANGUAGES="Go,Rust"
  omawsl_cloud_tools
  [[ "$(stub_calls)" != *"terraform"* ]]
  [[ "$(stub_calls)" != *"azure-cli"* ]]
}

@test "cloud_tools: a failed terraform repo-add doesn't prevent azure-cli from being attempted" {
  stub_command curl 1
  export OMAWSL_LANGUAGES="Terraform,Azure CLI"
  omawsl_cloud_tools
  [[ "$(stub_calls)" == *"curl -fsSL https://apt.releases.hashicorp.com/gpg"* ]]
  [[ "$(stub_calls)" == *"curl -fsSL https://packages.microsoft.com/keys/microsoft.asc"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase3-languages-cloud-tools && tests/.bats-core/bin/bats tests/cloud_tools_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Write `install/terminal/cloud-tools.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_terraform [apt_sources_file] [keyrings_dir]
# Idempotent (skips the repo-add once the sources file exists; apt-get
# install itself no-ops on an already-installed package) and
# failure-isolated: because this whole flow runs under set -e, a single
# unreachable third-party repo (HashiCorp's, here) must not cascade into
# failing every later step in the run (design spec §12). The `{ ... } ||`
# block catches any failure inside it without killing the script, and
# reports just this tool as failed rather than letting it propagate.
# Kept as its own function rather than sharing a parameterized helper with
# omawsl_install_azure_cli below - the two are similar but not identical,
# and a shared helper would need as many parameters as it'd save lines.
omawsl_install_terraform() {
  local apt_sources_file="${1:-${OMAWSL_TERRAFORM_APT_SOURCES_FILE:-/etc/apt/sources.list.d/hashicorp.list}}"
  local keyrings_dir="${2:-${OMAWSL_TERRAFORM_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if command -v terraform &>/dev/null; then
    return 0
  fi

  local ok=1
  {
    if [[ ! -f "$apt_sources_file" ]]; then
      sudo install -m 0755 -d "$keyrings_dir"
      curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o "$keyrings_dir/hashicorp.gpg"
      echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyrings_dir/hashicorp.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
        | sudo tee "$apt_sources_file" >/dev/null
      sudo apt-get update -qq
    fi
    sudo apt-get install -y terraform
  } || ok=0

  if [[ "$ok" -eq 0 ]]; then
    echo "omawsl: Terraform install failed (repo unreachable?) - skipping, continuing with the rest of the run."
  fi
}

# omawsl_install_azure_cli [apt_sources_file] [keyrings_dir]
# Same idempotent + failure-isolated shape as omawsl_install_terraform,
# for Microsoft's apt repo instead of HashiCorp's (design spec §12).
omawsl_install_azure_cli() {
  local apt_sources_file="${1:-${OMAWSL_AZURE_CLI_APT_SOURCES_FILE:-/etc/apt/sources.list.d/azure-cli.list}}"
  local keyrings_dir="${2:-${OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if command -v az &>/dev/null; then
    return 0
  fi

  local ok=1
  {
    if [[ ! -f "$apt_sources_file" ]]; then
      sudo install -m 0755 -d "$keyrings_dir"
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o "$keyrings_dir/microsoft.gpg"
      echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyrings_dir/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
        | sudo tee "$apt_sources_file" >/dev/null
      sudo apt-get update -qq
    fi
    sudo apt-get install -y azure-cli
  } || ok=0

  if [[ "$ok" -eq 0 ]]; then
    echo "omawsl: Azure CLI install failed (repo unreachable?) - skipping, continuing with the rest of the run."
  fi
}

# omawsl_cloud_tools
# Reads OMAWSL_LANGUAGES (Terraform/Azure CLI live in the same picker as
# the 8 languages - design spec §6) and installs each selected tool.
# Nothing pre-selected by default; selecting neither is a valid no-op.
# Each install function already swallows its own failure internally and
# always returns 0, so no extra isolation logic is needed here - a failed
# Terraform install simply doesn't stop Azure CLI from still being tried.
omawsl_cloud_tools() {
  local languages="${OMAWSL_LANGUAGES:-}"

  if omawsl_list_has "$languages" "Terraform"; then
    omawsl_install_terraform
  fi

  if omawsl_list_has "$languages" "Azure CLI"; then
    omawsl_install_azure_cli
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_cloud_tools
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase3-languages-cloud-tools && tests/.bats-core/bin/bats tests/cloud_tools_test.bats"
```
Expected: `12 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal/cloud-tools.sh tests/cloud_tools_test.bats
git commit -m "feat: add cloud-tools.sh (Terraform/Azure CLI with repo-failure isolation)"
```

---

### Task 4: Wire `mise.sh`, `select-dev-language.sh`, `cloud-tools.sh` into `install/terminal.sh`

**Files:**
- Modify: `install/terminal.sh`
- Modify: `tests/terminal_test.bats`

**Interfaces:**
- Consumes: `omawsl_install_mise` (Task 1), `omawsl_select_dev_language` (Task 2), `omawsl_cloud_tools` (Task 3)

- [ ] **Step 1: Write the failing test**

Replace the `@test` in `tests/terminal_test.bats` (keep the existing `setup()` from Phase 2 unchanged - `OMAWSL_LANGUAGES` stays unset/empty here, so the three new scripts all no-op cleanly and need no new stubs beyond what Phase 2 already added):

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
terminal/libraries.sh"

  [ "$actual_order" = "$expected_order" ]
  [ -f "$HOME/.bashrc" ]
  [[ "$(stub_calls)" == *"apt-get install -y gum"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase3-languages-cloud-tools && tests/.bats-core/bin/bats tests/terminal_test.bats"
```
Expected: FAILs (`actual_order` is missing the three new entries).

- [ ] **Step 3: Update `install/terminal.sh`**

Replace the `OMAWSL_TERMINAL_SCRIPTS` array and `SCRIPT_FUNCTIONS` map:

```bash
# Fixed order, sourced (not sub-shelled) so a failure stops the whole run
# immediately (design spec §8). Extended by later phases (the app-*.sh
# editor/tool scripts) rather than restructured.
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
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase3-languages-cloud-tools && tests/.bats-core/bin/bats tests/terminal_test.bats"
```
Expected: `1 test, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal.sh tests/terminal_test.bats
git commit -m "feat: wire mise.sh, select-dev-language.sh, cloud-tools.sh into terminal.sh's dispatch table"
```

---

### Task 5: Update `tests/install_test.bats` for full end-to-end coverage

**Files:**
- Modify: `tests/install_test.bats`

**Interfaces:** none new — this task only extends coverage of `install.sh` now that it exercises languages/cloud-tools too.

- [ ] **Step 1: Write the failing tests**

Replace `tests/install_test.bats`'s `setup()` and first `@test` (leave the second `@test`, "choosing Docker Desktop surfaces...", exactly as-is from Phase 2 - it's unaffected by this phase):

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

  export OMAWSL_WSL_CONF_FILE="$BATS_TEST_TMPDIR/wsl.conf"
  printf '[boot]\nsystemd=true\n' > "$OMAWSL_WSL_CONF_FILE"
  export OMAWSL_DOCKER_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/docker.list"
  export OMAWSL_DOCKER_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  # Pre-seed every third-party apt sources file this run could touch as
  # already-existing, so each one takes its "already configured" branch
  # and skips its curl|gpg / echo|tee repo-add pipes. Found during Phase
  # 2's Task 5: those pipes' stubbed sudo/curl/gpg exit near-instantly
  # without draining stdin (unlike the real commands), so when this whole
  # script runs as a freshly exec'd process the writer side can lose the
  # SIGPIPE race under pipefail (deterministic 141, not flaky). Every one
  # of these pipes already has dedicated, non-flaky coverage via a direct
  # in-process call in docker_test.bats/cloud_tools_test.bats, so this
  # loses no coverage.
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
  gum_stub_respond ""
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
  grep -q '^OMAWSL_LANGUAGES="Go,Terraform"$' "$OMAWSL_STATE_DIR/choices.env"
  grep -q '^OMAWSL_STORAGE=""$' "$OMAWSL_STATE_DIR/choices.env"
  [[ "$(stub_calls)" == *"sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]
  [[ "$(stub_calls)" == *"mise use --global go@latest"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y terraform"* ]]
  [[ "$(stub_calls)" != *"azure-cli"* ]]
}
```

- [ ] **Step 2: Run tests to verify the outcome**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase3-languages-cloud-tools && tests/.bats-core/bin/bats tests/install_test.bats"
```
Expected: `2 tests, 0 failures`. (No production-code implementation step needed here — Tasks 1–4 already made `install.sh` support this; this task is pure test-coverage catch-up.)

- [ ] **Step 3: Run the entire test suite to confirm nothing regressed**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl/.worktrees/phase3-languages-cloud-tools && tests/.bats-core/bin/bats tests/*.bats"
```
Expected: every file's tests pass, zero failures (79 from Phase 1+2 + 3 mise + 11 language + 12 cloud-tools = 105, plus `terminal_test.bats`'s and `install_test.bats`'s counts stay at 1 and 2 respectively, both already included in the 79 — the important thing is zero failures, not the exact total).

- [ ] **Step 4: Commit**

```bash
git add tests/install_test.bats
git commit -m "test: extend install_test.bats for languages + cloud-tools end-to-end coverage"
```

---

### Task 6: Manual end-to-end verification (human-in-the-loop)

**Files:** none — this task produces no new code, only a verification record.

This is the one step in this plan the agent executing it should **not** attempt: it requires real network access to `mise.run`, HashiCorp's and Microsoft's real apt repos, and real (possibly slow) toolchain downloads/compiles. Everything up through Task 5 is fully verified by the automated, stubbed test suite — this task is the final "does the real thing actually work, unstubbed" check.

- [x] **Step 1 (human): Run the real install, picking a representative subset**

From inside the WSL Ubuntu terminal itself:

```bash
bash /mnt/c/Users/tcins/vscode-workspace/omawsl/install.sh
```

You don't need to test all 10 language/cloud-tool options, but **include Ruby on Rails specifically** - the only path with an extra `mise exec ruby@latest -- gem install rails` step on top of a plain `mise use --global`, added during this phase's final review to fix a real gap (a bare `gem install rails` wouldn't have found `gem` on PATH after a mise-only Ruby install). Picking Ruby on Rails plus one fast language (e.g. Go) and one cloud tool (Terraform or Azure CLI) is enough to exercise every code path for real without a long wait. Docker/storage answers can be whatever's convenient (they're already verified from Phase 2).

- [x] **Step 2 (human): Confirm mise and the chosen languages actually work**

After the run completes with `omawsl: install complete.`:
- `mise --version` succeeds.
- `mise ls` shows the language(s) you picked, each with a real installed version (not just "requested").
- For each language you picked, its own version command works (e.g. `go version`, `rustc --version`) - open a **new terminal** first if the current one doesn't see `mise`/the languages yet (same PATH-refresh consideration as Phase 2's Docker group reminder, though `mise.sh` exports PATH for the *current* install.sh run itself, so this matters only for your own separate interactive shell).
- If you picked Ruby on Rails specifically: `ruby --version` and `rails --version` both work.

**Outcome: one real bug found, not caught by any automated test.** `go`, `ruby`, `rails`, and `gem` were all unreachable in a brand-new terminal even after `mise ls` correctly showed them installed - only `mise --version` itself worked. Root cause: `configs/bashrc` checked `command -v mise` *before* the line that puts `$HOME/.local/bin` (where `mise` lives) on PATH, so `mise activate bash` never ran in any interactive shell, ever - not just during this run. Fixed by reordering those two lines (commit `7e9b10b`), with a new regression test in `tests/a_shell_test.bats`.

- [x] **Step 3 (human): Confirm the cloud tool(s) actually work**

- If you picked Terraform: `terraform version` succeeds.
- If you picked Azure CLI: `az --version` succeeds.

**Outcome: Terraform installed and worked correctly** (`terraform version` succeeded). **Azure CLI failed to install** - Microsoft's `azure-cli` apt repo doesn't yet have a Release file for Ubuntu 26.04's "resolute" codename (a real, current limitation on Microsoft's end, not something omawsl controls) - `cloud-tools.sh`'s failure isolation correctly reported this and didn't crash. However, the failed attempt left a broken `/etc/apt/sources.list.d/azure-cli.list` in place, which then made `libraries.sh`'s own unrelated `apt-get update` fail too (apt returns nonzero when *any* configured repo errors) and **silently aborted the entire `install.sh` run under `set -e`, before `install complete` ever printed** - a second real bug, more severe than the first, since it broke the rest of the run for anyone hitting an unreachable third-party repo. Fixed by having both `omawsl_install_terraform`/`omawsl_install_azure_cli` remove their own apt sources file on any failure, so it can't poison later steps or future runs (commit `18134f5`). Discovering this also surfaced that this WSL instance's newly-real `docker-ce`/`terraform`/`mise` installs had broken several tests' assumptions about what's "not installed" on this specific machine - hardened `install_test.bats`, `cloud_tools_test.bats`, and `mise_test.bats` accordingly (commits `18134f5`, `ba6a01b`), including a new shared `stub_hide_command` test helper.

- [x] **Step 4 (human): Idempotency check**

Re-run `bash install.sh` a second time end to end (same answers) and confirm it completes cleanly with no errors - the mise re-pins, the apt-repo-adds, and the package installs should all silently no-op or harmlessly re-affirm the second time.

**Outcome: confirmed clean on the second run**, per the pasted output ("libpq-dev is already the newest version...", "0 upgraded, 0 newly installed, 0 to remove", ending in `omawsl: install complete.` plus the docker-group reminder).

- [x] **Step 5 (human): Report back**

Tell me either "it worked, here's what I saw" or paste the exact error/output if something broke. If something breaks, that's the systematic-debugging skill's territory next - a real failure here is more valuable to see than a hypothetical one (as Phase 2's Task 7 proved twice over).

- [ ] **Step 6 (human, only once Step 5 confirms success): confirm the commit history is clean**

Run `git log --oneline` and check it reads as a clean, incremental history of Tasks 1–5 (no fixup commits needed). If everything's fine, update `docs/superpowers/plans/roadmap.md`'s Phase 3 entry to "DONE, merged to `master`" (matching Phases 1 and 2's entry format) and Phase 4 is next.

**Note for whoever does Step 6: several more fix commits landed after the ones Task 6 originally covered** (`7e9b10b`, `18134f5`, `ba6a01b`, `7105055`) - these are expected, real-world-verification-driven fixes, not fixup noise, consistent with Phase 2's own Task 7 precedent.

**A confirming re-run surfaced one more real bug (fixed in `7105055`):** the leftover `azure-cli.list` from the *original* pre-fix failed run wasn't the only stale artifact - `/etc/apt/keyrings/microsoft.gpg` was also already there (the key-fetch step had succeeded before the original failure), and `gpg --dearmor -o <file>` without `--yes` interactively prompts "File exists. Overwrite? (y/N)" when the destination already exists. On a non-interactive script this hangs forever waiting for input that never comes. Added `--yes` to all three `gpg --dearmor` call sites (`docker.sh`, and both functions in `cloud-tools.sh` - same pattern, same latent risk, just not yet triggered for the other two). **A fully clean re-run (no manual `sudo rm` needed, no interactive prompts) still hasn't been confirmed** - worth doing once more before considering Phase 3 fully closed, though all three fixes are covered by automated tests regardless.

---

## Self-Review Notes

- **Spec coverage:** §12's languages section (`select-dev-language.sh` via `mise`, all 8 languages, Rails as the one gem-on-top case) → Task 2. §12's third-party-repo + failure-isolation requirement for Terraform/Azure CLI → Task 3. §7's "mise use re-pins versions harmlessly" idempotency → Tasks 1, 2. §6/§12's "nothing pre-selected, selecting nothing is valid" → Tasks 2, 3. §8's "sourced not sub-shelled" (exploited by `mise.sh`'s same-session `PATH` export) → Tasks 1, 4. §15's "runnable in isolation" → every task's tests call each script's functions directly with explicit args/env vars. Storage (§12's third bullet) was already done in Phase 2 and is untouched here. Everything else in the design spec (editors, theming, Windows-side docs, the rest of `bin/omawsl`) is out of scope for Phase 3 per `docs/superpowers/plans/roadmap.md`.
- **Placeholder scan:** no TBD/TODO markers; every step has complete, runnable code; no "similar to Task N" shortcuts.
- **Type/name consistency check:** `omawsl_install_mise` (Task 1), `omawsl_select_dev_language` (Task 2), and `omawsl_cloud_tools` (Task 3) are the exact function names registered in Task 4's `SCRIPT_FUNCTIONS` map. `OMAWSL_TERRAFORM_APT_SOURCES_FILE`/`OMAWSL_TERRAFORM_APT_KEYRINGS_DIR` and `OMAWSL_AZURE_CLI_APT_SOURCES_FILE`/`OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR` (Task 3) are the exact env vars set in Task 5's test setup, mirroring Task 2 (Phase 2)'s `OMAWSL_DOCKER_APT_*` naming convention exactly. `omawsl_list_has` (Phase 1) is used identically in Tasks 2 and 3.
