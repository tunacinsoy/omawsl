# omawsl Phase 7: `bin/omawsl` CLI Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the remaining five `bin/omawsl` subcommands (`update`, `migrate`, `uninstall`, `install`, `doctor`) plus the `uninstall/` tree, completing the design spec's §14 CLI and closing out the 7-phase roadmap.

**Architecture:** One new shared slug/label registry (`bin/omawsl-sub/items.sh`) gives every command a single flat namespace ("go", "vscode", "mysql", ...) across languages, editors, and storage, so `install` and `uninstall` never drift on what a name means, and `doctor` can print the exact `install`/`uninstall` command to fix a gap. Each new subcommand gets its own `bin/omawsl-sub/<command>.sh` file (same shape as the existing `theme.sh`/`windows-terminal.sh`), wired into `bin/omawsl`'s dispatch table. `uninstall/*.sh` mirrors `install/terminal/*.sh` one-for-one (same idempotent, sourced-not-subshelled conventions) so removing something is exactly as safe to re-run as installing it.

**Tech Stack:** Bash (`set -euo pipefail`), `mise` (verified live against the real WSL2 test instance: `mise unuse --global <tool>@latest` removes both the pin and prunes the installed version; `mise ls --current` lists configured tools), `gum choose --selected` (verified to support pre-selection), `docker`/`gh`/`git`, bats-core for tests (`tests/helpers/stubs.bash`).

## Global Constraints

- Every new/modified script starts with `#!/usr/bin/env bash` + `set -euo pipefail`, matching every existing script in this repo.
- Comma-delimited list membership always goes through `omawsl_list_has` (`install/lib.sh`) — never a bare substring/`==` check.
- Persisted user choices always go through `omawsl_save_choice`/`omawsl_load_choice` (`install/lib.sh`) — never `source`/`eval` `choices.env` directly.
- Every `install/terminal/*.sh` and `uninstall/*.sh` function must be idempotent and safe to re-run (design spec §8) — an uninstall of something never installed is a no-op with an informational message, never a hard error (design spec §14).
- `bin/omawsl` owns exactly two things: its own scripts/configs (`update`, `migrate`), and re-running/removing what it installed (`theme`, `install`, `uninstall`, `doctor`) — it never wraps `apt upgrade`, `mise upgrade`, or `docker pull` (design spec §14, "Division of responsibility").
- **Never run git commands through `wsl.exe`** — this repo lives on the Windows filesystem; only plain Windows-native `git` is safe here. `wsl.exe` is only for running bash scripts/bats tests.
- **Never create or push to a GitHub remote for this repo without asking the user first** — even though this is Phase 7 and the user's stated plan is to create the remote once v1 is done, this is a one-way, externally-visible action that needs an explicit go-ahead each time, not standing authorization.
- **Do NOT run `git clean` for any reason** inside any worktree used for this phase — a stray `git clean` deleted an untracked plan file mid-phase in Phase 5.

---

## File structure for this phase

```
bin/
├── omawsl                       # extend dispatch table (Task 13)
└── omawsl-sub/
    ├── items.sh                 # NEW - shared slug<->label registry (Task 8)
    ├── uninstall.sh              # NEW - `omawsl uninstall <name>` (Task 8)
    ├── migrate.sh                 # NEW - `omawsl migrate` (Task 9)
    ├── update.sh                  # NEW - `omawsl update` (Task 10)
    ├── doctor.sh                  # NEW - `omawsl doctor` (Task 11)
    └── install.sh                 # NEW - `omawsl install [category] [item]` (Task 12)
install/
└── lib.sh                       # add omawsl_write_version_state, omawsl_merge_csv (Task 9)
uninstall/
├── dev-language.sh               # NEW (Task 1) - all 10 "Languages & cloud tools" items
├── storage.sh                    # NEW (Task 2)
├── docker.sh                     # NEW (Task 3)
├── app-vscode.sh                 # NEW (Task 4)
├── app-cursor.sh                 # NEW (Task 4)
├── app-neovim.sh                 # NEW (Task 5)
├── app-opencode.sh               # NEW (Task 5)
├── app-claude-cli.sh             # NEW (Task 6)
├── app-codex-cli.sh              # NEW (Task 6)
├── app-gemini-cli.sh             # NEW (Task 6)
└── app-gh-copilot.sh             # NEW (Task 7)
tests/
├── uninstall_dev_language_test.bats    # Task 1
├── uninstall_storage_test.bats          # Task 2
├── uninstall_docker_test.bats           # Task 3
├── uninstall_editors_test.bats          # Task 4
├── uninstall_wsl_tools_test.bats        # Task 5
├── uninstall_ai_cli_test.bats           # Task 6
├── uninstall_gh_copilot_test.bats       # Task 7
├── omawsl_uninstall_command_test.bats   # Task 8
├── lib_test.bats                        # extended (Task 9)
├── omawsl_migrate_test.bats             # Task 9
├── omawsl_update_test.bats              # Task 10
├── omawsl_doctor_test.bats              # Task 11
├── omawsl_install_command_test.bats     # Task 12
└── omawsl_cli_test.bats                 # extended (Task 13)
README.md                                # Status section updated (Task 13)
docs/superpowers/plans/roadmap.md        # updated after Task 14's human sign-off, not before
```

---

### Task 1: `uninstall/dev-language.sh`

**Files:**
- Create: `uninstall/dev-language.sh`
- Test: `tests/uninstall_dev_language_test.bats`

**Interfaces:**
- Consumes: `install/lib.sh`'s `omawsl_list_has` (not used directly here, but sourced for consistency); nothing else from earlier tasks.
- Produces: `omawsl_uninstall_language <label>` — takes the *exact* picker label string (e.g. `"Ruby on Rails"`, `"Terraform"`), the same convention `install/terminal/select-dev-language.sh`/`cloud-tools.sh` already use for `OMAWSL_LANGUAGES`. Later tasks (8, 11, 12) call this by label, not by mise tool name or CLI slug.

This single file covers all 10 items from the "Languages & cloud tools" picker (design spec §7's file tree lists one `uninstall/dev-language.sh` for the whole category, not one file per tool) — 8 mise-managed languages plus Terraform/Azure CLI, mirroring how `select-dev-language.sh` + `cloud-tools.sh` together cover install for that same picker.

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/dev-language.sh"
  stub_command sudo
  stub_command mise
}

@test "omawsl_uninstall_language unpins a mise-managed tool via mise unuse --global" {
  run omawsl_uninstall_language "Go"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise unuse --global go@latest"* ]]
  [[ "$output" == *"Go"* ]]
}

@test "omawsl_uninstall_language handles Ruby on Rails by unpinning ruby" {
  run omawsl_uninstall_language "Ruby on Rails"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise unuse --global ruby@latest"* ]]
}

@test "omawsl_uninstall_language purges terraform and removes its apt source" {
  export OMAWSL_TERRAFORM_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/hashicorp.list"
  export OMAWSL_TERRAFORM_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  touch "$OMAWSL_TERRAFORM_APT_SOURCES_FILE"
  stub_command terraform
  run omawsl_uninstall_language "Terraform"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y terraform"* ]]
  [ ! -f "$OMAWSL_TERRAFORM_APT_SOURCES_FILE" ]
}

@test "omawsl_uninstall_language no-ops cleanly when terraform was never installed" {
  stub_hide_command terraform
  run omawsl_uninstall_language "Terraform"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to do"* ]]
  [[ "$(stub_calls)" != *"apt-get purge"* ]]
}

@test "omawsl_uninstall_language purges azure-cli and removes its apt source" {
  export OMAWSL_AZURE_CLI_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/azure-cli.list"
  export OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  touch "$OMAWSL_AZURE_CLI_APT_SOURCES_FILE"
  stub_command az
  run omawsl_uninstall_language "Azure CLI"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y azure-cli"* ]]
  [ ! -f "$OMAWSL_AZURE_CLI_APT_SOURCES_FILE" ]
}

@test "omawsl_uninstall_language rejects an unknown label" {
  run omawsl_uninstall_language "Not A Real Language"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_dev_language_test.bats"`
Expected: FAIL — `uninstall/dev-language.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_mise_tool <mise_tool>
# `mise unuse --global <tool>@latest` both removes the [tools] entry from
# ~/.config/mise/config.toml AND prunes the installed version (verified
# live: help text says "Will also prune the installed version if no other
# configurations are using it"). Confirmed idempotent on a real WSL2
# instance: calling it for a tool that was never configured exits 0
# silently rather than erroring, so no pre-check is needed here - the
# echo below is what actually satisfies design spec §14's "no-op with an
# informational message, not an error" requirement.
omawsl_uninstall_mise_tool() {
  local mise_tool="$1"
  mise unuse --global "${mise_tool}@latest"
}

# omawsl_uninstall_terraform [apt_sources_file] [keyrings_dir]
# Inverse of install/terminal/cloud-tools.sh's omawsl_install_terraform.
# Same OMAWSL_TERRAFORM_APT_*-overridable paths, for the same testability
# reason.
omawsl_uninstall_terraform() {
  local apt_sources_file="${1:-${OMAWSL_TERRAFORM_APT_SOURCES_FILE:-/etc/apt/sources.list.d/hashicorp.list}}"
  local keyrings_dir="${2:-${OMAWSL_TERRAFORM_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if ! command -v terraform &>/dev/null; then
    echo "omawsl: Terraform isn't installed - nothing to do."
    return 0
  fi

  sudo apt-get purge -y terraform
  sudo rm -f "$apt_sources_file" "$keyrings_dir/hashicorp.gpg"
  echo "omawsl: Terraform removed."
}

# omawsl_uninstall_azure_cli [apt_sources_file] [keyrings_dir]
# Inverse of omawsl_install_azure_cli.
omawsl_uninstall_azure_cli() {
  local apt_sources_file="${1:-${OMAWSL_AZURE_CLI_APT_SOURCES_FILE:-/etc/apt/sources.list.d/azure-cli.list}}"
  local keyrings_dir="${2:-${OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if ! command -v az &>/dev/null; then
    echo "omawsl: Azure CLI isn't installed - nothing to do."
    return 0
  fi

  sudo apt-get purge -y azure-cli
  sudo rm -f "$apt_sources_file" "$keyrings_dir/microsoft.gpg"
  echo "omawsl: Azure CLI removed."
}

# omawsl_uninstall_language <label>
# Takes the exact picker label (matches OMAWSL_LANGUAGES's own comma-list
# values) rather than a mise tool name or CLI slug - callers translate a
# short slug ("go") to this label via bin/omawsl-sub/items.sh (Task 8).
omawsl_uninstall_language() {
  local label="$1"
  case "$label" in
    "Ruby on Rails") omawsl_uninstall_mise_tool ruby; echo "omawsl: Ruby on Rails removed." ;;
    "Node.js")        omawsl_uninstall_mise_tool node; echo "omawsl: Node.js removed." ;;
    "Go")             omawsl_uninstall_mise_tool go; echo "omawsl: Go removed." ;;
    "PHP")            omawsl_uninstall_mise_tool php; echo "omawsl: PHP removed." ;;
    "Python")         omawsl_uninstall_mise_tool python; echo "omawsl: Python removed." ;;
    "Elixir")         omawsl_uninstall_mise_tool elixir; echo "omawsl: Elixir removed." ;;
    "Rust")           omawsl_uninstall_mise_tool rust; echo "omawsl: Rust removed." ;;
    "Java")           omawsl_uninstall_mise_tool java; echo "omawsl: Java removed." ;;
    "Terraform")      omawsl_uninstall_terraform ;;
    "Azure CLI")      omawsl_uninstall_azure_cli ;;
    *)
      echo "omawsl: unknown language/tool '$label'" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_language "$@"
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_dev_language_test.bats"`
Expected: PASS (all 6 tests)

- [ ] **Step 5: Commit**

```bash
git add uninstall/dev-language.sh tests/uninstall_dev_language_test.bats
git commit -m "feat(phase7): add uninstall/dev-language.sh"
```

---

### Task 2: `uninstall/storage.sh`

**Files:**
- Create: `uninstall/storage.sh`
- Test: `tests/uninstall_storage_test.bats`

**Interfaces:**
- Consumes: `omawsl_docker_reachable` (`install/lib.sh`).
- Produces: `omawsl_uninstall_storage <label>` — label is `"MySQL"`/`"Redis"`/`"PostgreSQL"`, matching `OMAWSL_STORAGE`'s own values and `install/terminal/select-dev-storage.sh`'s container-naming convention (`omawsl-mysql`, `omawsl-mysql-data`, ...).

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/storage.sh"
  stub_command sudo
}

@test "omawsl_uninstall_storage removes an existing MySQL container and its volume" {
  docker() {
    case "$1 $2" in
      "ps -a") echo "omawsl-mysql" ;;
      "volume") [[ "$3" == "ls" ]] && echo "omawsl-mysql-data" ;;
    esac
    echo "docker $*" >> "$STUB_LOG"
  }
  export -f docker
  run omawsl_uninstall_storage "MySQL"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"docker rm -f omawsl-mysql"* ]]
  [[ "$(stub_calls)" == *"docker volume rm omawsl-mysql-data"* ]]
}

@test "omawsl_uninstall_storage no-ops when the container was never created" {
  docker() { echo "docker $*" >> "$STUB_LOG"; }
  export -f docker
  run omawsl_uninstall_storage "Redis"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"rm -f"* ]]
  [[ "$output" == *"Redis"* ]]
}

@test "omawsl_uninstall_storage no-ops cleanly when docker isn't reachable" {
  stub_hide_command docker
  run omawsl_uninstall_storage "PostgreSQL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"isn't reachable"* ]]
}

@test "omawsl_uninstall_storage rejects an unknown label" {
  run omawsl_uninstall_storage "MongoDB"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_storage_test.bats"`
Expected: FAIL — `uninstall/storage.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_storage <label>
# Inverse of install/terminal/select-dev-storage.sh's omawsl_ensure_container -
# same sudo docker rationale (group-membership staleness within one sourced
# session, design spec §8). Checks existence before removing rather than
# relying on `docker rm -f` failing silently, since `docker rm`/`volume rm`
# on a name that doesn't exist actually errors (nonzero exit), which would
# trip set -e here.
omawsl_uninstall_storage() {
  local label="$1"
  local container volume
  case "$label" in
    MySQL)      container=omawsl-mysql;      volume=omawsl-mysql-data ;;
    Redis)      container=omawsl-redis;      volume=omawsl-redis-data ;;
    PostgreSQL) container=omawsl-postgresql; volume=omawsl-postgresql-data ;;
    *)
      echo "omawsl: unknown storage option '$label'" >&2
      return 1
      ;;
  esac

  if ! omawsl_docker_reachable; then
    echo "omawsl: 'docker' isn't reachable - nothing to remove for $label."
    return 0
  fi

  if sudo docker ps -a --format '{{.Names}}' | grep -qx "$container"; then
    sudo docker rm -f "$container" >/dev/null
  fi
  if sudo docker volume ls --format '{{.Name}}' | grep -qx "$volume"; then
    sudo docker volume rm "$volume" >/dev/null
  fi
  echo "omawsl: $label container removed (or was already not present)."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_storage "$@"
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_storage_test.bats"`
Expected: PASS (all 4 tests)

- [ ] **Step 5: Commit**

```bash
git add uninstall/storage.sh tests/uninstall_storage_test.bats
git commit -m "feat(phase7): add uninstall/storage.sh"
```

---

### Task 3: `uninstall/docker.sh`

**Files:**
- Create: `uninstall/docker.sh`
- Test: `tests/uninstall_docker_test.bats`

**Interfaces:**
- Consumes: `omawsl_docker_reachable`, `omawsl_load_choice` (`install/lib.sh`).
- Produces: `omawsl_uninstall_docker [apt_sources_file] [keyrings_dir]` — no-ops with a message if `OMAWSL_DOCKER_MODE` in `choices.env` was Docker Desktop (omawsl never installed it in that mode); otherwise removes every `omawsl-*` container/volume it may have created (across all three storage options, regardless of what's currently selected — this is a full Docker teardown, not scoped to current picker state) and purges `docker-ce`.

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/docker.sh"
  stub_command sudo
}

@test "omawsl_uninstall_docker no-ops when Docker Desktop mode was chosen" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Desktop for Windows"
  stub_command docker
  run omawsl_uninstall_docker
  [ "$status" -eq 0 ]
  [[ "$output" == *"never installed it"* ]]
  [[ "$(stub_calls)" != *"apt-get purge"* ]]
}

@test "omawsl_uninstall_docker purges docker-ce and removes omawsl-* containers/volumes in Engine mode" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Engine only, inside WSL (recommended)"
  stub_command docker
  local sources="$BATS_TEST_TMPDIR/docker.list"
  local keyrings="$BATS_TEST_TMPDIR/keyrings"
  touch "$sources"
  run omawsl_uninstall_docker "$sources" "$keyrings"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"docker rm -f omawsl-mysql"* ]]
  [[ "$(stub_calls)" == *"docker rm -f omawsl-redis"* ]]
  [[ "$(stub_calls)" == *"docker rm -f omawsl-postgresql"* ]]
  [[ "$(stub_calls)" == *"docker volume rm omawsl-mysql-data"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]
  [ ! -f "$sources" ]
}

@test "omawsl_uninstall_docker no-ops on the apt purge when docker-ce isn't actually installed" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Engine only, inside WSL (recommended)"
  stub_hide_command docker
  run omawsl_uninstall_docker
  [ "$status" -eq 0 ]
  [[ "$output" == *"isn't installed"* ]]
  [[ "$(stub_calls)" != *"apt-get purge"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_docker_test.bats"`
Expected: FAIL — `uninstall/docker.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_omawsl_containers
# Removes every omawsl-* container/volume this repo could have created
# across all three storage options (design spec §7's own uninstall/docker.sh
# scope: "removes docker-ce + containers/images/volumes it created"), not
# just whatever's currently selected in OMAWSL_STORAGE - a full Docker
# teardown removes everything omawsl ever touched, regardless of the
# user's current picker state. `|| true` on each: unlike storage.sh's
# per-item uninstall (which checks existence first), this is a best-effort
# sweep over fixed candidate names, so a missing container/volume is
# expected, not exceptional.
omawsl_uninstall_omawsl_containers() {
  omawsl_docker_reachable || return 0
  local name
  for name in omawsl-mysql omawsl-redis omawsl-postgresql; do
    sudo docker rm -f "$name" >/dev/null 2>&1 || true
  done
  for name in omawsl-mysql-data omawsl-redis-data omawsl-postgresql-data; do
    sudo docker volume rm "$name" >/dev/null 2>&1 || true
  done
}

# omawsl_uninstall_docker [apt_sources_file] [keyrings_dir]
# Detect-and-defer's inverse: if OMAWSL_DOCKER_MODE (persisted in
# choices.env, design spec §6) was Docker Desktop, omawsl's docker.sh
# never installed docker-ce (design spec §9) - so there's genuinely
# nothing here for THIS repo to uninstall. Otherwise purges docker-ce and
# its apt source/keyring, same paths omawsl_install_docker_ce writes
# (install/terminal/docker.sh). Deliberately leaves the user's docker
# group membership in place rather than auto-revoking it - that's a
# broader system change than "undo what omawsl installed."
omawsl_uninstall_docker() {
  local apt_sources_file="${1:-/etc/apt/sources.list.d/docker.list}"
  local keyrings_dir="${2:-/etc/apt/keyrings}"

  if [[ "$(omawsl_load_choice OMAWSL_DOCKER_MODE)" == "Docker Desktop for Windows" ]]; then
    echo "omawsl: Docker was set up via Docker Desktop for Windows - omawsl never installed it, so there's nothing to uninstall here."
    echo "Uninstall Docker Desktop yourself on the Windows side if you want to remove it."
    return 0
  fi

  omawsl_uninstall_omawsl_containers

  if ! command -v docker &>/dev/null; then
    echo "omawsl: docker-ce isn't installed - nothing more to do."
    return 0
  fi

  sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo rm -f "$apt_sources_file" "$keyrings_dir/docker.gpg"
  echo "omawsl: docker-ce removed. Your user's docker group membership was left in place - run 'sudo gpasswd -d \"\$USER\" docker' yourself if you want that removed too."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_docker "$@"
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_docker_test.bats"`
Expected: PASS (all 3 tests)

- [ ] **Step 5: Commit**

```bash
git add uninstall/docker.sh tests/uninstall_docker_test.bats
git commit -m "feat(phase7): add uninstall/docker.sh"
```

---

### Task 4: `uninstall/app-vscode.sh` + `uninstall/app-cursor.sh`

**Files:**
- Create: `uninstall/app-vscode.sh`
- Create: `uninstall/app-cursor.sh`
- Test: `tests/uninstall_editors_test.bats`

**Interfaces:**
- Consumes: `omawsl_code_reachable` (`install/lib.sh`).
- Produces: `omawsl_uninstall_vscode [settings_file]`, `omawsl_uninstall_cursor [settings_file]`.

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/app-vscode.sh"
  source "$REPO_ROOT/uninstall/app-cursor.sh"
}

@test "omawsl_uninstall_vscode removes the deployed settings file and uninstalls the extension when code is reachable" {
  local settings="$HOME/.vscode-server/data/Machine/settings.json"
  mkdir -p "$(dirname "$settings")"
  echo '{}' > "$settings"
  stub_command code
  run omawsl_uninstall_vscode "$settings"
  [ "$status" -eq 0 ]
  [ ! -f "$settings" ]
  [[ "$(stub_calls)" == *"code --uninstall-extension ms-vscode-remote.remote-wsl"* ]]
}

@test "omawsl_uninstall_vscode removes the settings file even when code isn't reachable" {
  local settings="$HOME/.vscode-server/data/Machine/settings.json"
  mkdir -p "$(dirname "$settings")"
  echo '{}' > "$settings"
  stub_hide_command code
  run omawsl_uninstall_vscode "$settings"
  [ "$status" -eq 0 ]
  [ ! -f "$settings" ]
}

@test "omawsl_uninstall_cursor removes the deployed settings file" {
  local settings="$HOME/.cursor-server/data/Machine/settings.json"
  mkdir -p "$(dirname "$settings")"
  echo '{}' > "$settings"
  run omawsl_uninstall_cursor "$settings"
  [ "$status" -eq 0 ]
  [ ! -f "$settings" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_editors_test.bats"`
Expected: FAIL — `uninstall/app-vscode.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_vscode [settings_file]
# Inverse of install/terminal/app-vscode.sh: removes the deployed
# configs/vscode.json copy and uninstalls the Remote-WSL extension if
# `code` is reachable (best-effort - if it isn't, the settings file
# removal below is still the meaningful part).
omawsl_uninstall_vscode() {
  local settings_file="${1:-$HOME/.vscode-server/data/Machine/settings.json}"

  if omawsl_code_reachable; then
    code --uninstall-extension ms-vscode-remote.remote-wsl || true
  fi

  rm -f "$settings_file"
  echo "omawsl: VS Code's omawsl-deployed settings removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_vscode "$@"
fi
```

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_cursor [settings_file]
# Inverse of install/terminal/app-cursor.sh. No extension-uninstall step -
# app-cursor.sh never installed one either (design spec §10: Cursor's own
# marketplace commonly blocks Microsoft-published extensions).
omawsl_uninstall_cursor() {
  local settings_file="${1:-$HOME/.cursor-server/data/Machine/settings.json}"
  rm -f "$settings_file"
  echo "omawsl: Cursor's omawsl-deployed settings removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_cursor "$@"
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_editors_test.bats"`
Expected: PASS (all 3 tests)

- [ ] **Step 5: Commit**

```bash
git add uninstall/app-vscode.sh uninstall/app-cursor.sh tests/uninstall_editors_test.bats
git commit -m "feat(phase7): add uninstall/app-vscode.sh and uninstall/app-cursor.sh"
```

---

### Task 5: `uninstall/app-neovim.sh` + `uninstall/app-opencode.sh`

**Files:**
- Create: `uninstall/app-neovim.sh`
- Create: `uninstall/app-opencode.sh`
- Test: `tests/uninstall_wsl_tools_test.bats`

**Interfaces:**
- Produces: `omawsl_uninstall_neovim`, `omawsl_uninstall_opencode`.

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/app-neovim.sh"
  source "$REPO_ROOT/uninstall/app-opencode.sh"
  stub_command sudo
}

@test "omawsl_uninstall_neovim removes the LazyVim config dir and purges the apt package" {
  mkdir -p "$HOME/.config/nvim/lua/plugins"
  run omawsl_uninstall_neovim
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.config/nvim" ]
  [[ "$(stub_calls)" == *"sudo apt-get purge -y neovim"* ]]
}

@test "omawsl_uninstall_neovim no-ops cleanly when nvim config never existed" {
  run omawsl_uninstall_neovim
  [ "$status" -eq 0 ]
}

@test "omawsl_uninstall_opencode removes the ~/.opencode directory" {
  mkdir -p "$HOME/.opencode/bin"
  touch "$HOME/.opencode/bin/opencode"
  run omawsl_uninstall_opencode
  [ "$status" -eq 0 ]
  [ ! -d "$HOME/.opencode" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_wsl_tools_test.bats"`
Expected: FAIL — `uninstall/app-neovim.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_neovim
# Inverse of install/terminal/app-neovim.sh: removes the LazyVim config
# tree it cloned and purges the apt-installed neovim package. Removing
# ~/.config/nvim unconditionally mirrors app-neovim.sh's own one-directional
# guard (it only skips the clone if the dir already existed at install
# time) - there is no reliable way to tell "omawsl's LazyVim clone" apart
# from a config a user hand-edited afterward, so this is a documented,
# scoped tradeoff, not an oversight.
omawsl_uninstall_neovim() {
  rm -rf "$HOME/.config/nvim"
  sudo apt-get purge -y neovim
  echo "omawsl: Neovim and its LazyVim config removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_neovim
fi
```

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_opencode
# Inverse of install/terminal/app-opencode.sh: opencode's own installer
# places everything under $HOME/.opencode (bin/ + node_modules/, confirmed
# on the real test WSL2 instance), so removing that directory is a
# complete uninstall.
omawsl_uninstall_opencode() {
  rm -rf "$HOME/.opencode"
  echo "omawsl: opencode removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_opencode
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_wsl_tools_test.bats"`
Expected: PASS (all 3 tests)

- [ ] **Step 5: Commit**

```bash
git add uninstall/app-neovim.sh uninstall/app-opencode.sh tests/uninstall_wsl_tools_test.bats
git commit -m "feat(phase7): add uninstall/app-neovim.sh and uninstall/app-opencode.sh"
```

---

### Task 6: `uninstall/app-claude-cli.sh` + `uninstall/app-codex-cli.sh` + `uninstall/app-gemini-cli.sh`

**Files:**
- Create: `uninstall/app-claude-cli.sh`
- Create: `uninstall/app-codex-cli.sh`
- Create: `uninstall/app-gemini-cli.sh`
- Test: `tests/uninstall_ai_cli_test.bats`

**Interfaces:**
- Produces: `omawsl_uninstall_claude_cli`, `omawsl_uninstall_codex_cli`, `omawsl_uninstall_gemini_cli`.

Verified live on the real WSL2 test instance: Claude Code's installer places a symlink at `~/.local/bin/claude` pointing into `~/.local/share/claude/versions/...` — removing both paths is a complete uninstall (no official `claude uninstall` subcommand exists).

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/app-claude-cli.sh"
  source "$REPO_ROOT/uninstall/app-codex-cli.sh"
  source "$REPO_ROOT/uninstall/app-gemini-cli.sh"
}

@test "omawsl_uninstall_claude_cli removes the binary and its data dir" {
  mkdir -p "$HOME/.local/share/claude/versions" "$HOME/.local/bin"
  ln -s "$HOME/.local/share/claude/versions/1.0" "$HOME/.local/bin/claude"
  run omawsl_uninstall_claude_cli
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.local/bin/claude" ]
  [ ! -d "$HOME/.local/share/claude" ]
}

@test "omawsl_uninstall_codex_cli uninstalls the npm package and removes the wrapper" {
  stub_command mise
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/codex" <<'EOF'
#!/usr/bin/env bash
exec mise exec node@lts -- codex "$@"
EOF
  chmod +x "$HOME/.local/bin/codex"
  run omawsl_uninstall_codex_cli
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.local/bin/codex" ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm uninstall -g @openai/codex"* ]]
}

@test "omawsl_uninstall_gemini_cli uninstalls the npm package and removes the wrapper" {
  stub_command mise
  mkdir -p "$HOME/.local/bin"
  touch "$HOME/.local/bin/gemini"
  run omawsl_uninstall_gemini_cli
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.local/bin/gemini" ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm uninstall -g @google/gemini-cli"* ]]
}

@test "omawsl_uninstall_codex_cli no-ops cleanly when mise isn't reachable" {
  stub_hide_command mise
  mkdir -p "$HOME/.local/bin"
  touch "$HOME/.local/bin/codex"
  run omawsl_uninstall_codex_cli
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.local/bin/codex" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_ai_cli_test.bats"`
Expected: FAIL — `uninstall/app-claude-cli.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_claude_cli
# Inverse of install/terminal/app-claude-cli.sh. Claude Code's own
# installer has no built-in uninstall subcommand (confirmed via
# `claude --help` on the real test WSL2 instance); it places a symlink at
# ~/.local/bin/claude pointing into ~/.local/share/claude/versions/... -
# removing both is a complete uninstall.
omawsl_uninstall_claude_cli() {
  rm -rf "$HOME/.local/share/claude" "$HOME/.local/bin/claude"
  echo "omawsl: Claude Code CLI removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_claude_cli
fi
```

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_codex_cli
# Inverse of install/terminal/app-codex-cli.sh: uninstalls the npm global
# package via the same private mise-managed Node runtime it was installed
# with, then removes the $HOME/.local/bin/codex wrapper. No-ops the npm
# step (but still removes the wrapper) if mise isn't reachable, since a
# leftover wrapper pointing at a now-broken `mise exec` call is worse than
# nothing.
omawsl_uninstall_codex_cli() {
  if command -v mise &>/dev/null; then
    mise exec node@lts -- npm uninstall -g @openai/codex || true
  fi
  rm -f "$HOME/.local/bin/codex"
  echo "omawsl: Codex CLI removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_codex_cli
fi
```

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_gemini_cli
# Same shape as omawsl_uninstall_codex_cli, for @google/gemini-cli.
omawsl_uninstall_gemini_cli() {
  if command -v mise &>/dev/null; then
    mise exec node@lts -- npm uninstall -g @google/gemini-cli || true
  fi
  rm -f "$HOME/.local/bin/gemini"
  echo "omawsl: Gemini CLI removed."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_gemini_cli
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_ai_cli_test.bats"`
Expected: PASS (all 4 tests)

- [ ] **Step 5: Commit**

```bash
git add uninstall/app-claude-cli.sh uninstall/app-codex-cli.sh uninstall/app-gemini-cli.sh tests/uninstall_ai_cli_test.bats
git commit -m "feat(phase7): add uninstall scripts for Claude Code, Codex, and Gemini CLIs"
```

---

### Task 7: `uninstall/app-gh-copilot.sh`

**Files:**
- Create: `uninstall/app-gh-copilot.sh`
- Test: `tests/uninstall_gh_copilot_test.bats`

**Interfaces:**
- Produces: `omawsl_uninstall_gh_copilot`.

Verified live: the installed extension's directory is `~/.local/share/gh/extensions/gh-copilot`, matching the `gh extension remove <name>` argument (`gh extension remove gh-copilot`).

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/uninstall/app-gh-copilot.sh"
}

@test "omawsl_uninstall_gh_copilot removes the extension when installed" {
  gh() {
    if [[ "$1 $2" == "extension list" ]]; then
      echo "gh copilot	github/gh-copilot	v1.2.0"
    fi
    echo "gh $*" >> "$STUB_LOG"
  }
  export -f gh
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gh extension remove gh-copilot"* ]]
}

@test "omawsl_uninstall_gh_copilot no-ops cleanly when it was never installed" {
  gh() { echo "gh $*" >> "$STUB_LOG"; }
  export -f gh
  run omawsl_uninstall_gh_copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"remove"* ]]
  [[ "$output" == *"GitHub Copilot CLI"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_gh_copilot_test.bats"`
Expected: FAIL — `uninstall/app-gh-copilot.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_uninstall_gh_copilot
# Inverse of install/terminal/app-gh-copilot.sh. `gh extension list`'s
# machine-parseable output starts each line with the invocation name
# ("gh copilot"), but the argument `gh extension remove` actually takes is
# the extension's own directory/repo-derived name ("gh-copilot", confirmed
# on the real test WSL2 instance via
# ~/.local/share/gh/extensions/gh-copilot).
omawsl_uninstall_gh_copilot() {
  if gh extension list 2>/dev/null | grep -q '^gh-copilot\|^gh copilot'; then
    gh extension remove gh-copilot
  fi
  echo "omawsl: GitHub Copilot CLI extension removed (or was already not installed)."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_uninstall_gh_copilot
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/uninstall_gh_copilot_test.bats"`
Expected: PASS (both tests)

- [ ] **Step 5: Commit**

```bash
git add uninstall/app-gh-copilot.sh tests/uninstall_gh_copilot_test.bats
git commit -m "feat(phase7): add uninstall/app-gh-copilot.sh"
```

---

### Task 8: `bin/omawsl-sub/items.sh` + `bin/omawsl-sub/uninstall.sh`

**Files:**
- Create: `bin/omawsl-sub/items.sh`
- Create: `bin/omawsl-sub/uninstall.sh`
- Test: `tests/omawsl_uninstall_command_test.bats`

**Interfaces:**
- Consumes: every `uninstall/*.sh` function from Tasks 1-7.
- Produces:
  - `omawsl_item_category <slug>` → prints `language`/`editor`/`storage`/`docker`, fails on unknown.
  - `omawsl_item_label <slug>` → prints the exact picker/choices.env label string, fails on unknown.
  - `omawsl_item_slugs <category>` → prints one slug per line, in picker order.
  - `omawsl_uninstall_command <slug>` → entry point for `bin/omawsl uninstall <name>`.
  - These three `items.sh` functions are also consumed by Task 12 (`install.sh`) and Task 11 (`doctor.sh`) — this is the single shared slug/label registry for the whole CLI, per design spec §14's own examples (`install language go`, `install editor vscode`).

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/items.sh"
  source "$REPO_ROOT/bin/omawsl-sub/uninstall.sh"
}

@test "omawsl_item_category classifies every known slug correctly" {
  [[ "$(omawsl_item_category go)" == "language" ]]
  [[ "$(omawsl_item_category terraform)" == "language" ]]
  [[ "$(omawsl_item_category vscode)" == "editor" ]]
  [[ "$(omawsl_item_category gh-copilot)" == "editor" ]]
  [[ "$(omawsl_item_category mysql)" == "storage" ]]
  [[ "$(omawsl_item_category docker)" == "docker" ]]
  ! omawsl_item_category not-a-real-slug
}

@test "omawsl_item_label maps every slug to its exact picker label" {
  [[ "$(omawsl_item_label ruby)" == "Ruby on Rails" ]]
  [[ "$(omawsl_item_label vscode)" == "VS Code" ]]
  [[ "$(omawsl_item_label gh-copilot)" == "GitHub Copilot CLI" ]]
  [[ "$(omawsl_item_label postgresql)" == "PostgreSQL" ]]
}

@test "omawsl_item_slugs lists all 10 language slugs, 8 editor slugs, 3 storage slugs" {
  [[ "$(omawsl_item_slugs language | wc -l)" -eq 10 ]]
  [[ "$(omawsl_item_slugs editor | wc -l)" -eq 8 ]]
  [[ "$(omawsl_item_slugs storage | wc -l)" -eq 3 ]]
}

@test "omawsl_uninstall_command dispatches a language slug to uninstall/dev-language.sh" {
  stub_command sudo
  stub_command mise
  run omawsl_uninstall_command go
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise unuse --global go@latest"* ]]
}

@test "omawsl_uninstall_command dispatches the docker slug to uninstall/docker.sh" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  stub_command sudo
  stub_hide_command docker
  run omawsl_uninstall_command docker
  [ "$status" -eq 0 ]
}

@test "omawsl_uninstall_command rejects an unknown item" {
  run omawsl_uninstall_command not-a-real-item
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown item"* ]]
}

@test "omawsl_uninstall_command with no argument prints usage and fails" {
  run omawsl_uninstall_command
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: omawsl uninstall"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_uninstall_command_test.bats"`
Expected: FAIL — `bin/omawsl-sub/items.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
# Shared slug<->label registry, one flat namespace across every option
# `bin/omawsl install`/`bin/omawsl uninstall` can target by a short
# lowercase slug (design spec §14's own examples: "install language go",
# "install editor vscode"). One place, reused by install.sh, uninstall.sh,
# and doctor.sh, so they never drift out of sync on what a name means.

# omawsl_item_category <slug>
omawsl_item_category() {
  case "$1" in
    ruby|node|go|php|python|elixir|rust|java|terraform|azure) echo "language" ;;
    vscode|neovim|opencode|cursor|claude|codex|gh-copilot|gemini) echo "editor" ;;
    mysql|redis|postgresql) echo "storage" ;;
    docker) echo "docker" ;;
    *) return 1 ;;
  esac
}

# omawsl_item_label <slug>
# The exact string used in choices.env's comma-delimited lists
# (OMAWSL_LANGUAGES/OMAWSL_EDITORS/OMAWSL_STORAGE) and passed to each
# uninstall/*.sh function - matches install/first-run-choices.sh's own gum
# choose option strings verbatim.
omawsl_item_label() {
  case "$1" in
    ruby) echo "Ruby on Rails" ;;
    node) echo "Node.js" ;;
    go) echo "Go" ;;
    php) echo "PHP" ;;
    python) echo "Python" ;;
    elixir) echo "Elixir" ;;
    rust) echo "Rust" ;;
    java) echo "Java" ;;
    terraform) echo "Terraform" ;;
    azure) echo "Azure CLI" ;;
    vscode) echo "VS Code" ;;
    neovim) echo "Neovim" ;;
    opencode) echo "opencode" ;;
    cursor) echo "Cursor" ;;
    claude) echo "Claude Code CLI" ;;
    codex) echo "Codex CLI" ;;
    gh-copilot) echo "GitHub Copilot CLI" ;;
    gemini) echo "Gemini CLI" ;;
    mysql) echo "MySQL" ;;
    redis) echo "Redis" ;;
    postgresql) echo "PostgreSQL" ;;
    *) return 1 ;;
  esac
}

# omawsl_item_slugs <category>
# All slugs for one category, in install/first-run-choices.sh's own
# picker order.
omawsl_item_slugs() {
  case "$1" in
    language) printf '%s\n' ruby node go php python elixir rust java terraform azure ;;
    editor) printf '%s\n' vscode neovim opencode cursor claude codex gh-copilot gemini ;;
    storage) printf '%s\n' mysql redis postgresql ;;
    *) return 1 ;;
  esac
}
```

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=items.sh
source "$SCRIPT_DIR/items.sh"

# omawsl_uninstall_dispatch <slug>
# Sources the matching uninstall/*.sh and calls its function with the
# right argument shape - languages/storage take the picker label (Tasks
# 1, 2), everything else takes no argument.
omawsl_uninstall_dispatch() {
  local slug="$1"
  local label
  case "$slug" in
    ruby|node|go|php|python|elixir|rust|java|terraform|azure)
      label="$(omawsl_item_label "$slug")"
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/dev-language.sh"
      omawsl_uninstall_language "$label"
      ;;
    mysql|redis|postgresql)
      label="$(omawsl_item_label "$slug")"
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/storage.sh"
      omawsl_uninstall_storage "$label"
      ;;
    docker)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/docker.sh"
      omawsl_uninstall_docker
      ;;
    vscode)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-vscode.sh"
      omawsl_uninstall_vscode
      ;;
    cursor)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-cursor.sh"
      omawsl_uninstall_cursor
      ;;
    neovim)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-neovim.sh"
      omawsl_uninstall_neovim
      ;;
    opencode)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-opencode.sh"
      omawsl_uninstall_opencode
      ;;
    claude)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-claude-cli.sh"
      omawsl_uninstall_claude_cli
      ;;
    codex)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-codex-cli.sh"
      omawsl_uninstall_codex_cli
      ;;
    gemini)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-gemini-cli.sh"
      omawsl_uninstall_gemini_cli
      ;;
    gh-copilot)
      # shellcheck source=/dev/null
      source "$OMAWSL_ROOT_DIR/uninstall/app-gh-copilot.sh"
      omawsl_uninstall_gh_copilot
      ;;
    *)
      echo "omawsl: unknown item '$slug'" >&2
      echo "Run 'omawsl install' with no arguments to see the available categories." >&2
      return 1
      ;;
  esac
}

# omawsl_uninstall_command [slug]
# Entry point for `bin/omawsl uninstall <name>` (design spec §14).
omawsl_uninstall_command() {
  local slug="${1:-}"
  if [[ -z "$slug" ]]; then
    echo "Usage: omawsl uninstall <name>" >&2
    return 1
  fi
  omawsl_uninstall_dispatch "$slug"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_uninstall_command_test.bats"`
Expected: PASS (all 7 tests)

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/items.sh bin/omawsl-sub/uninstall.sh tests/omawsl_uninstall_command_test.bats
git commit -m "feat(phase7): add the item registry and bin/omawsl uninstall"
```

---

### Task 9: `bin/omawsl-sub/migrate.sh`

**Files:**
- Modify: `install/lib.sh` (add `omawsl_write_version_state`, moved from `install.sh`)
- Modify: `install.sh:19-23,39` (use the moved function)
- Modify: `tests/lib_test.bats` (cover the moved function)
- Create: `bin/omawsl-sub/migrate.sh`
- Test: `tests/omawsl_migrate_test.bats`

**Interfaces:**
- Produces: `omawsl_write_version_state <root_dir>` (in `install/lib.sh`, now takes an explicit arg instead of reading a global), `omawsl_migrate` (entry point for `bin/omawsl migrate`).

`install.sh` currently defines `omawsl_write_version_state` inline, reading the top-level `$OMAWSL_ROOT_DIR` global. Moving it into `lib.sh` with an explicit parameter makes it a proper shared, independently-testable helper instead of a script-private one, consistent with every other cross-script helper in this repo living in `lib.sh`. `migrate.sh`'s own final "bump to the repo's current version" step deliberately does **not** call it directly — that step needs to honor `OMAWSL_VERSION_FILE`'s test-only override (so `omawsl_migrate` can be exercised against a fixture version file without touching this repo's own real `version` file), which `omawsl_write_version_state`'s `root_dir`-relative `cp` doesn't support. The two are separate, independently useful pieces of DRY-ness: `install.sh` reuses the shared function verbatim; `migrate.sh` reuses the same *convention* (state dir holds a single-line timestamp) with its own override-aware read/write.

- [ ] **Step 1: Write the failing tests**

```bash
# --- append to tests/lib_test.bats ---

@test "omawsl_write_version_state copies the given root dir's version file into the state dir" {
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  local root="$BATS_TEST_TMPDIR/root"
  mkdir -p "$root"
  echo "1234567890" > "$root/version"
  omawsl_write_version_state "$root"
  [ -f "$OMAWSL_STATE_DIR/version" ]
  [ "$(cat "$OMAWSL_STATE_DIR/version")" = "1234567890" ]
}
```

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/migrate.sh"
}

@test "omawsl_migrate reports up to date when no migrations directory exists" {
  export OMAWSL_MIGRATIONS_DIR="$BATS_TEST_TMPDIR/no-such-dir"
  export OMAWSL_VERSION_FILE="$BATS_TEST_TMPDIR/version"
  echo 0 > "$OMAWSL_VERSION_FILE"
  run omawsl_migrate
  [ "$status" -eq 0 ]
  [[ "$output" == *"up to date"* ]]
}

@test "omawsl_migrate runs every migration newer than the recorded state, in order" {
  local migrations="$BATS_TEST_TMPDIR/migrations"
  mkdir -p "$migrations"
  echo 'echo "ran-100" >> "$STUB_LOG"' > "$migrations/100.sh"
  echo 'echo "ran-200" >> "$STUB_LOG"' > "$migrations/200.sh"
  export OMAWSL_MIGRATIONS_DIR="$migrations"
  export OMAWSL_VERSION_FILE="$BATS_TEST_TMPDIR/version"
  echo 50 > "$OMAWSL_VERSION_FILE"
  mkdir -p "$OMAWSL_STATE_DIR"
  echo 50 > "$OMAWSL_STATE_DIR/version"

  run omawsl_migrate
  [ "$status" -eq 0 ]
  local calls; calls="$(cat "$STUB_LOG")"
  [[ "$calls" == *"ran-100"* ]]
  [[ "$calls" == *"ran-200"* ]]
  [ "$(cat "$OMAWSL_STATE_DIR/version")" = "200" ]
}

@test "omawsl_migrate skips migrations already covered by the recorded state" {
  local migrations="$BATS_TEST_TMPDIR/migrations"
  mkdir -p "$migrations"
  echo 'echo "ran-100" >> "$STUB_LOG"' > "$migrations/100.sh"
  export OMAWSL_MIGRATIONS_DIR="$migrations"
  export OMAWSL_VERSION_FILE="$BATS_TEST_TMPDIR/version"
  echo 100 > "$OMAWSL_VERSION_FILE"
  mkdir -p "$OMAWSL_STATE_DIR"
  echo 100 > "$OMAWSL_STATE_DIR/version"

  run omawsl_migrate
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"ran-100"* ]]
  [[ "$output" == *"up to date"* ]]
}

@test "omawsl_migrate bumps state to the repo version even with zero pending migrations" {
  export OMAWSL_MIGRATIONS_DIR="$BATS_TEST_TMPDIR/empty-migrations"
  mkdir -p "$OMAWSL_MIGRATIONS_DIR"
  export OMAWSL_VERSION_FILE="$BATS_TEST_TMPDIR/version"
  echo 999 > "$OMAWSL_VERSION_FILE"
  mkdir -p "$OMAWSL_STATE_DIR"
  echo 500 > "$OMAWSL_STATE_DIR/version"

  run omawsl_migrate
  [ "$status" -eq 0 ]
  [ "$(cat "$OMAWSL_STATE_DIR/version")" = "999" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/lib_test.bats tests/omawsl_migrate_test.bats"`
Expected: FAIL — `omawsl_write_version_state: command not found` / `bin/omawsl-sub/migrate.sh: No such file or directory`

- [ ] **Step 3: Move `omawsl_write_version_state` into `install/lib.sh`**

Append to `install/lib.sh`:

```bash

# omawsl_write_version_state <root_dir>
# Copies <root_dir>/version into the persisted state dir (design spec §8:
# a fresh install already reflects current desired state, so the first
# `bin/omawsl migrate` doesn't treat every historical migration as
# pending). Moved here from install.sh (Phase 1) so bin/omawsl-sub/migrate.sh
# (Phase 7) can reuse it without duplicating - takes root_dir as an
# explicit argument rather than reading a global, so both callers stay
# self-contained and testable in isolation.
omawsl_write_version_state() {
  local root_dir="$1"
  local dir; dir="$(omawsl_choices_dir)"
  mkdir -p "$dir"
  cp "$root_dir/version" "$dir/version"
}
```

Replace `install.sh`'s inline definition and call site:

```bash
# install.sh - remove the old omawsl_write_version_state() {...} block
# (lines 19-23), and change the call site (was line 39):
  omawsl_write_version_state "$OMAWSL_ROOT_DIR"
```

- [ ] **Step 4: Write `bin/omawsl-sub/migrate.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"

# omawsl_migrations_dir
# Overridable via OMAWSL_MIGRATIONS_DIR for testing, same pattern as every
# other OMAWSL_*_FILE/_DIR override in this repo (docker.sh, cloud-tools.sh).
omawsl_migrations_dir() {
  echo "${OMAWSL_MIGRATIONS_DIR:-$OMAWSL_ROOT_DIR/migrations}"
}

# omawsl_migration_timestamps
# Prints every migrations/<timestamp>.sh file's timestamp, one per line,
# sorted numerically ascending. Silent no-op if the dir doesn't exist.
omawsl_migration_timestamps() {
  local dir; dir="$(omawsl_migrations_dir)"
  [[ -d "$dir" ]] || return 0
  local f base
  for f in "$dir"/*.sh; do
    [[ -e "$f" ]] || continue
    base="${f##*/}"
    echo "${base%.sh}"
  done | sort -n
}

# omawsl_last_migrated_timestamp
# Reads the persisted state's version file (design spec §8); defaults to
# 0 if it's never been written (nothing has ever "completed" a migration
# baseline for this user yet).
omawsl_last_migrated_timestamp() {
  local file; file="$(omawsl_choices_dir)/version"
  if [[ -f "$file" ]]; then
    cat "$file"
  else
    echo 0
  fi
}

# omawsl_pending_migrations
omawsl_pending_migrations() {
  local last; last="$(omawsl_last_migrated_timestamp)"
  local ts
  omawsl_migration_timestamps | while IFS= read -r ts; do
    if [[ "$ts" -gt "$last" ]]; then
      echo "$ts"
    fi
  done
}

# omawsl_migrate
# Entry point for `bin/omawsl migrate` (design spec §14): runs every
# migration newer than the recorded state, updating state after EACH one
# individually (not just at the end) so a mid-run failure doesn't lose
# progress already made on a re-run. Afterward, if the repo's own current
# version is newer than what's recorded (e.g. a release bumped `version`
# with zero actual migrations), bumps state to match - otherwise a later
# `migrate` run would see nothing pending but state would never reflect
# "fully up to date."
omawsl_migrate() {
  local pending; pending="$(omawsl_pending_migrations)"
  local dir; dir="$(omawsl_migrations_dir)"
  local state_dir; state_dir="$(omawsl_choices_dir)"

  if [[ -z "$pending" ]]; then
    echo "omawsl: no pending migrations - up to date."
  else
    mkdir -p "$state_dir"
    local ts
    while IFS= read -r ts; do
      echo "omawsl: running migration $ts..."
      bash "$dir/$ts.sh"
      echo "$ts" > "$state_dir/version"
    done <<< "$pending"
    echo "omawsl: migrations complete."
  fi

  local version_file="${OMAWSL_VERSION_FILE:-$OMAWSL_ROOT_DIR/version}"
  local repo_version; repo_version="$(cat "$version_file")"
  local current; current="$(omawsl_last_migrated_timestamp)"
  if [[ "$repo_version" -gt "$current" ]]; then
    mkdir -p "$state_dir"
    echo "$repo_version" > "$state_dir/version"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_migrate
fi
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/lib_test.bats tests/omawsl_migrate_test.bats tests/install_test.bats"`
Expected: PASS — including `install_test.bats`'s existing "writes version state" assertion, unaffected by the refactor.

- [ ] **Step 6: Commit**

```bash
git add install/lib.sh install.sh bin/omawsl-sub/migrate.sh tests/lib_test.bats tests/omawsl_migrate_test.bats
git commit -m "feat(phase7): add bin/omawsl migrate, share omawsl_write_version_state via lib.sh"
```

---

### Task 10: `bin/omawsl-sub/update.sh`

**Files:**
- Create: `bin/omawsl-sub/update.sh`
- Test: `tests/omawsl_update_test.bats`

**Interfaces:**
- Consumes: `omawsl_migrate` (Task 9).
- Produces: `omawsl_update` (entry point for `bin/omawsl update`).

This is the one place in the plan that needs a *real* git repo fixture (not a stub) to exercise the dirty-tree check and an actual `git pull` meaningfully — every other test in this codebase stubs `git` entirely, but a stub can't distinguish "clean" from "dirty."

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/migrate.sh"
  source "$REPO_ROOT/bin/omawsl-sub/update.sh"
  git config --global user.email "test@example.com"
  git config --global user.name "Test"
}

@test "omawsl_update fails cleanly when OMAWSL_HOME has no git checkout" {
  export OMAWSL_HOME="$BATS_TEST_TMPDIR/not-a-repo"
  mkdir -p "$OMAWSL_HOME"
  run omawsl_update
  [ "$status" -ne 0 ]
  [[ "$output" == *"no checkout found"* ]]
}

@test "omawsl_update refuses to pull over local changes" {
  export OMAWSL_HOME="$BATS_TEST_TMPDIR/home-repo"
  mkdir -p "$OMAWSL_HOME"
  git -C "$OMAWSL_HOME" init -q
  echo "1" > "$OMAWSL_HOME/version"
  git -C "$OMAWSL_HOME" add version
  git -C "$OMAWSL_HOME" commit -q -m init
  echo "dirty" >> "$OMAWSL_HOME/version"

  run omawsl_update
  [ "$status" -ne 0 ]
  [[ "$output" == *"local changes"* ]]
}

@test "omawsl_update pulls a clean checkout and runs migrate" {
  local origin="$BATS_TEST_TMPDIR/origin.git"
  git init -q --bare "$origin"

  local seed="$BATS_TEST_TMPDIR/seed"
  git clone -q "$origin" "$seed"
  echo "1" > "$seed/version"
  git -C "$seed" add version
  git -C "$seed" commit -q -m init
  git -C "$seed" push -q origin master

  export OMAWSL_HOME="$BATS_TEST_TMPDIR/home-repo"
  git clone -q "$origin" "$OMAWSL_HOME"

  echo "2" > "$seed/version"
  git -C "$seed" add version
  git -C "$seed" commit -q -m "bump version"
  git -C "$seed" push -q origin master

  omawsl_migrate() { echo "migrate-called" >> "$STUB_LOG"; }
  export -f omawsl_migrate

  run omawsl_update
  [ "$status" -eq 0 ]
  [ "$(cat "$OMAWSL_HOME/version")" = "2" ]
  [[ "$(stub_calls)" == *"migrate-called"* ]]
  [[ "$output" == *"update complete"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_update_test.bats"`
Expected: FAIL — `bin/omawsl-sub/update.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=migrate.sh
source "$SCRIPT_DIR/migrate.sh"

# omawsl_update
# Entry point for `bin/omawsl update` (design spec §14): git pull inside
# $OMAWSL_HOME, then runs pending migrations - a deliberate improvement
# over upstream Omakub, whose own update flow never automates the git
# pull itself. Detects a dirty working tree first (someone hand-edited a
# file directly inside the checkout) and refuses to pull over it rather
# than letting `git pull` fail confusingly or silently discard those
# edits. Same $OMAWSL_HOME default/override convention as boot.sh.
omawsl_update() {
  local home_dir="${OMAWSL_HOME:-$HOME/.local/share/omawsl}"

  if [[ ! -d "$home_dir/.git" ]]; then
    echo "omawsl: no checkout found at $home_dir - nothing to update." >&2
    return 1
  fi

  if [[ -n "$(git -C "$home_dir" status --porcelain)" ]]; then
    echo "omawsl: $home_dir has local changes - refusing to 'git pull' over them." >&2
    echo "Commit, stash, or discard those changes yourself, then re-run 'omawsl update'." >&2
    return 1
  fi

  echo "omawsl: pulling latest..."
  if ! git -C "$home_dir" pull; then
    echo "omawsl: 'git pull' failed - check your network connection and try again." >&2
    return 1
  fi

  omawsl_migrate

  echo "omawsl: update complete."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_update
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_update_test.bats"`
Expected: PASS (all 3 tests)

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/update.sh tests/omawsl_update_test.bats
git commit -m "feat(phase7): add bin/omawsl update"
```

---

### Task 11: `bin/omawsl-sub/doctor.sh`

**Files:**
- Create: `bin/omawsl-sub/doctor.sh`
- Test: `tests/omawsl_doctor_test.bats`

**Interfaces:**
- Consumes: `omawsl_item_slugs`, `omawsl_item_label` (Task 8); `omawsl_load_choice`, `omawsl_list_has`, `omawsl_docker_reachable`, `omawsl_code_reachable`, `omawsl_cursor_reachable` (`install/lib.sh`).
- Produces: `omawsl_doctor` (entry point for `bin/omawsl doctor`).

- [ ] **Step 1: Write the failing tests**

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/items.sh"
  source "$REPO_ROOT/bin/omawsl-sub/doctor.sh"
  stub_command sudo
}

@test "omawsl_doctor reports OK for an installed, configured language" {
  omawsl_save_choice OMAWSL_LANGUAGES "Go"
  mise() {
    [[ "$1 $2" == "ls --current" ]] && echo "go      1.26.4  ~/.config/mise/config.toml  latest"
  }
  export -f mise
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"[OK]      Go"* ]]
}

@test "omawsl_doctor reports PENDING with the exact install command for a selected-but-missing item" {
  omawsl_save_choice OMAWSL_LANGUAGES "Rust"
  stub_hide_command mise
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"[PENDING] Rust - run: omawsl install language rust"* ]]
}

@test "omawsl_doctor skips categories where nothing was selected" {
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"none selected"* ]]
}

@test "omawsl_doctor flags a still-unreachable Docker Desktop selection" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Desktop for Windows"
  stub_hide_command docker
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker Desktop for Windows"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_doctor_test.bats"`
Expected: FAIL — `bin/omawsl-sub/doctor.sh: No such file or directory`

- [ ] **Step 3: Write the implementation**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=items.sh
source "$SCRIPT_DIR/items.sh"

# omawsl_doctor_language_installed <slug>
# Terraform/Azure CLI aren't mise-managed (design spec §12), so they're
# checked via command -v; the 8 mise-managed tools are checked against
# `mise ls --current`'s own tool-name column - this is what mise use
# --global actually configures (verified live: `mise ls --current` lists
# exactly go/python/ruby on the real test WSL2 instance after those three
# were selected).
omawsl_doctor_language_installed() {
  local slug="$1"
  case "$slug" in
    terraform) command -v terraform &>/dev/null ;;
    azure) command -v az &>/dev/null ;;
    *)
      local mise_tool
      case "$slug" in
        ruby) mise_tool=ruby ;; node) mise_tool=node ;; go) mise_tool=go ;;
        php) mise_tool=php ;; python) mise_tool=python ;; elixir) mise_tool=elixir ;;
        rust) mise_tool=rust ;; java) mise_tool=java ;;
      esac
      command -v mise &>/dev/null && mise ls --current 2>/dev/null | awk '{print $1}' | grep -qx "$mise_tool"
      ;;
  esac
}

# omawsl_doctor_editor_installed <slug>
omawsl_doctor_editor_installed() {
  local slug="$1"
  case "$slug" in
    vscode) omawsl_code_reachable ;;
    cursor) omawsl_cursor_reachable ;;
    neovim) [[ -d "$HOME/.config/nvim" ]] ;;
    opencode) command -v opencode &>/dev/null ;;
    claude) command -v claude &>/dev/null ;;
    codex) command -v codex &>/dev/null ;;
    gemini) command -v gemini &>/dev/null ;;
    gh-copilot) gh extension list 2>/dev/null | grep -q '^gh-copilot\|^gh copilot' ;;
  esac
}

# omawsl_doctor_storage_installed <slug>
omawsl_doctor_storage_installed() {
  local slug="$1" container
  case "$slug" in
    mysql) container=omawsl-mysql ;;
    redis) container=omawsl-redis ;;
    postgresql) container=omawsl-postgresql ;;
  esac
  omawsl_docker_reachable && sudo docker ps -a --format '{{.Names}}' 2>/dev/null | grep -qx "$container"
}

# omawsl_doctor_report_category <category> <check_fn> <choices_key>
# Cross-checks every selected item in one category against its check
# function, printing [OK]/[PENDING] with the exact `omawsl install`
# command to resolve a gap (design spec §14).
omawsl_doctor_report_category() {
  local category="$1" check_fn="$2" choices_key="$3"
  local selected; selected="$(omawsl_load_choice "$choices_key")"

  if [[ -z "$selected" ]]; then
    echo "  (none selected)"
    return 0
  fi

  local slug label
  while IFS= read -r slug; do
    label="$(omawsl_item_label "$slug")"
    omawsl_list_has "$selected" "$label" || continue
    if "$check_fn" "$slug"; then
      echo "  [OK]      $label"
    else
      echo "  [PENDING] $label - run: omawsl install $category $slug"
    fi
  done < <(omawsl_item_slugs "$category")
}

# omawsl_doctor
# Entry point for `bin/omawsl doctor` (design spec §14).
omawsl_doctor() {
  echo "omawsl doctor - checking what's installed/configured:"
  echo
  echo "Languages & cloud tools:"
  omawsl_doctor_report_category language omawsl_doctor_language_installed OMAWSL_LANGUAGES
  echo
  echo "Editors & AI tooling:"
  omawsl_doctor_report_category editor omawsl_doctor_editor_installed OMAWSL_EDITORS
  echo
  echo "Storage:"
  omawsl_doctor_report_category storage omawsl_doctor_storage_installed OMAWSL_STORAGE

  if [[ "$(omawsl_load_choice OMAWSL_DOCKER_MODE)" == "Docker Desktop for Windows" ]] && ! omawsl_docker_reachable; then
    echo
    echo "Docker:"
    echo "  [PENDING] Docker Desktop for Windows - see docs/windows-setup.md#docker-desktop"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_doctor
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_doctor_test.bats"`
Expected: PASS (all 4 tests)

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/doctor.sh tests/omawsl_doctor_test.bats
git commit -m "feat(phase7): add bin/omawsl doctor"
```

---

### Task 12: `bin/omawsl-sub/install.sh`

**Files:**
- Modify: `install/lib.sh` (add `omawsl_merge_csv`)
- Modify: `tests/lib_test.bats` (cover `omawsl_merge_csv`)
- Create: `bin/omawsl-sub/install.sh`
- Test: `tests/omawsl_install_command_test.bats`

**Interfaces:**
- Consumes: `omawsl_item_category`, `omawsl_item_label`, `omawsl_item_slugs` (Task 8); every `install/terminal/*.sh` install function (already exists); `omawsl_merge_csv` (new, this task).
- Produces: `omawsl_install_command [category] [item]` (entry point for `bin/omawsl install`).

- [ ] **Step 1: Write the failing tests**

```bash
# --- append to tests/lib_test.bats ---

@test "omawsl_merge_csv unions two comma lists, deduplicated, a's order first" {
  [[ "$(omawsl_merge_csv "Go,Rust" "Python,Go")" == "Go,Rust,Python" ]]
}

@test "omawsl_merge_csv handles an empty existing list" {
  [[ "$(omawsl_merge_csv "" "Go,Rust")" == "Go,Rust" ]]
}

@test "omawsl_merge_csv handles an empty new list" {
  [[ "$(omawsl_merge_csv "Go,Rust" "")" == "Go,Rust" ]]
}
```

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
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/items.sh"
  source "$REPO_ROOT/bin/omawsl-sub/install.sh"
  stub_command sudo
  stub_command mise
  stub_command gem
  stub_hide_command docker terraform az code cursor claude codex gemini opencode
}

@test "omawsl install language go - installs go directly and merges it into OMAWSL_LANGUAGES" {
  omawsl_save_choice OMAWSL_LANGUAGES "Rust"
  run omawsl_install_command language go
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise use --global go@latest"* ]]
  [[ "$(omawsl_load_choice OMAWSL_LANGUAGES)" == "Rust,Go" ]]
}

@test "omawsl install editor vscode - installs vscode directly and merges it into OMAWSL_EDITORS" {
  run omawsl_install_command editor vscode
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_EDITORS)" == "VS Code" ]]
}

@test "omawsl install storage mysql - installs mysql directly" {
  stub_hide_command docker
  run omawsl_install_command storage mysql
  [ "$status" -eq 0 ]
  [[ "$(omawsl_load_choice OMAWSL_STORAGE)" == "MySQL" ]]
}

@test "omawsl install rejects an item that doesn't belong to the given category" {
  run omawsl_install_command editor go
  [ "$status" -ne 0 ]
  [[ "$output" == *"isn't in the 'editor' category"* ]]
}

@test "omawsl install rejects an unknown item" {
  run omawsl_install_command language not-a-real-item
  [ "$status" -ne 0 ]
}

@test "omawsl install with a category but no item prints usage" {
  run omawsl_install_command language
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: omawsl install"* ]]
}

@test "omawsl install with no args runs the interactive category picker, pre-checking existing choices" {
  omawsl_save_choice OMAWSL_LANGUAGES "Go"
  # Custom override, not the shared gum_stub_respond queue: both
  # omawsl_install_interactive's category picker and
  # omawsl_install_prompt_multi's item picker pass their options as plain
  # arguments (never piped into gum), unlike theme.sh's `... | gum choose`
  # pattern - so no stdin draining is needed here, just two distinct
  # responses keyed off which prompt is being asked.
  gum() {
    echo "gum $*" >> "$STUB_LOG"
    if [[ "$*" == *"What do you want to add"* ]]; then
      echo "Language/tool"
    else
      echo "Go
Python"
    fi
  }
  export -f gum
  run omawsl_install_command
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"--selected Go"* ]]
  [[ "$(omawsl_load_choice OMAWSL_LANGUAGES)" == "Go,Python" ]]
}

@test "omawsl install with no args returns cleanly when the category picker is cancelled" {
  gum() { echo "gum $*" >> "$STUB_LOG"; return 1; }
  export -f gum
  BATS_RUN_ERREXIT=1 run omawsl_install_command
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/lib_test.bats tests/omawsl_install_command_test.bats"`
Expected: FAIL — `omawsl_merge_csv: command not found` / `bin/omawsl-sub/install.sh: No such file or directory`

- [ ] **Step 3: Add `omawsl_merge_csv` to `install/lib.sh`**

Append to `install/lib.sh`:

```bash

# omawsl_merge_csv <a> <b>
# Union of two comma-delimited lists, de-duplicated, order-preserving
# (a's items first, then any of b's items not already in a) - via
# omawsl_list_has, so this respects the same whole-token matching every
# other membership check in this repo uses.
omawsl_merge_csv() {
  local a="$1" b="$2"
  local result="$a"
  local item
  IFS=',' read -ra items <<< "$b"
  for item in "${items[@]}"; do
    [[ -z "$item" ]] && continue
    if ! omawsl_list_has "$result" "$item"; then
      result="${result:+$result,}$item"
    fi
  done
  echo "$result"
}
```

- [ ] **Step 4: Write `bin/omawsl-sub/install.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=items.sh
source "$SCRIPT_DIR/items.sh"

# omawsl_install_prompt_multi <header> <preselected_csv> <options...>
# Same shape as install/first-run-choices.sh's omawsl_prompt_multi, plus
# gum choose's --selected flag (verified live to accept a comma-list of
# labels to pre-check) so already-installed items show pre-checked, per
# design spec §14's "no-args" picker behavior.
omawsl_install_prompt_multi() {
  local header="$1" preselected="$2"; shift 2
  gum choose --no-limit --selected "$preselected" --header "$header" "$@" | paste -sd, -
}

# omawsl_install_apply_language <picked_labels_csv> <existing_labels_csv>
omawsl_install_apply_language() {
  local picked="$1" existing="$2"
  local merged; merged="$(omawsl_merge_csv "$existing" "$picked")"
  export OMAWSL_LANGUAGES="$merged"
  omawsl_save_choice OMAWSL_LANGUAGES "$merged"
  # shellcheck source=/dev/null
  source "$OMAWSL_ROOT_DIR/install/terminal/select-dev-language.sh"
  # shellcheck source=/dev/null
  source "$OMAWSL_ROOT_DIR/install/terminal/cloud-tools.sh"
  omawsl_select_dev_language
  omawsl_cloud_tools
}

# omawsl_install_apply_editor <picked_labels_csv> <existing_labels_csv>
omawsl_install_apply_editor() {
  local picked="$1" existing="$2"
  local merged; merged="$(omawsl_merge_csv "$existing" "$picked")"
  export OMAWSL_EDITORS="$merged"
  omawsl_save_choice OMAWSL_EDITORS "$merged"
  local f
  for f in app-vscode app-neovim app-opencode app-cursor app-claude-cli app-codex-cli app-gh-copilot app-gemini-cli; do
    # shellcheck source=/dev/null
    source "$OMAWSL_ROOT_DIR/install/terminal/$f.sh"
  done
  omawsl_install_vscode
  omawsl_install_neovim
  omawsl_install_opencode
  omawsl_install_cursor
  omawsl_install_claude_cli
  omawsl_install_codex_cli
  omawsl_install_gh_copilot
  omawsl_install_gemini_cli
}

# omawsl_install_apply_storage <picked_labels_csv> <existing_labels_csv>
omawsl_install_apply_storage() {
  local picked="$1" existing="$2"
  local merged; merged="$(omawsl_merge_csv "$existing" "$picked")"
  export OMAWSL_STORAGE="$merged"
  omawsl_save_choice OMAWSL_STORAGE "$merged"
  # shellcheck source=/dev/null
  source "$OMAWSL_ROOT_DIR/install/terminal/select-dev-storage.sh"
  omawsl_install_storage
}

# omawsl_install_category_language
omawsl_install_category_language() {
  local existing; existing="$(omawsl_load_choice OMAWSL_LANGUAGES)"
  local labels=() slug
  while IFS= read -r slug; do labels+=("$(omawsl_item_label "$slug")"); done < <(omawsl_item_slugs language)
  local picked
  picked="$(omawsl_install_prompt_multi "Languages & cloud tools (already-installed items are pre-checked)" "$existing" "${labels[@]}")" || picked=""
  omawsl_install_apply_language "$picked" "$existing"
}

# omawsl_install_category_editor
omawsl_install_category_editor() {
  local existing; existing="$(omawsl_load_choice OMAWSL_EDITORS)"
  local labels=() slug
  while IFS= read -r slug; do labels+=("$(omawsl_item_label "$slug")"); done < <(omawsl_item_slugs editor)
  local picked
  picked="$(omawsl_install_prompt_multi "Editors & AI tooling (already-installed items are pre-checked)" "$existing" "${labels[@]}")" || picked=""
  omawsl_install_apply_editor "$picked" "$existing"
}

# omawsl_install_category_storage
omawsl_install_category_storage() {
  local existing; existing="$(omawsl_load_choice OMAWSL_STORAGE)"
  local labels=() slug
  while IFS= read -r slug; do labels+=("$(omawsl_item_label "$slug")"); done < <(omawsl_item_slugs storage)
  local picked
  picked="$(omawsl_install_prompt_multi "Storage (already-installed items are pre-checked)" "$existing" "${labels[@]}")" || picked=""
  omawsl_install_apply_storage "$picked" "$existing"
}

# omawsl_install_direct <category> <slug>
omawsl_install_direct() {
  local category="$1" slug="$2"
  local item_category
  if ! item_category="$(omawsl_item_category "$slug")"; then
    echo "omawsl: unknown item '$slug'" >&2
    return 1
  fi
  if [[ "$item_category" != "$category" ]]; then
    echo "omawsl: '$slug' isn't in the '$category' category (it's '$item_category')" >&2
    return 1
  fi

  local label; label="$(omawsl_item_label "$slug")"
  case "$category" in
    language) omawsl_install_apply_language "$label" "$(omawsl_load_choice OMAWSL_LANGUAGES)" ;;
    editor)   omawsl_install_apply_editor   "$label" "$(omawsl_load_choice OMAWSL_EDITORS)" ;;
    storage)  omawsl_install_apply_storage  "$label" "$(omawsl_load_choice OMAWSL_STORAGE)" ;;
  esac
}

# omawsl_install_interactive
# The no-args path (design spec §14): pick a category, then that
# category's own multi-select re-appears with already-installed items
# pre-checked.
omawsl_install_interactive() {
  local category
  category="$(gum choose --header "What do you want to add?" "Language/tool" "Editors & AI tooling" "Storage")" || category=""
  [[ -n "$category" ]] || return 0
  case "$category" in
    "Language/tool")         omawsl_install_category_language ;;
    "Editors & AI tooling")  omawsl_install_category_editor ;;
    "Storage")               omawsl_install_category_storage ;;
  esac
}

# omawsl_install_command [category] [item]
# Entry point for `bin/omawsl install [category] [item]` (design spec
# §14). Category names here are the human words used in the interactive
# picker's own choices ("language", "editor", "storage"), matching the
# spec's own examples ("install language go", "install editor vscode").
omawsl_install_command() {
  local category="${1:-}" item="${2:-}"

  if [[ -z "$category" ]]; then
    omawsl_install_interactive
    return
  fi

  if [[ -z "$item" ]]; then
    echo "Usage: omawsl install [category] [item]" >&2
    echo "Categories: language, editor, storage" >&2
    return 1
  fi

  case "$category" in
    language|editor|storage) omawsl_install_direct "$category" "$item" ;;
    *)
      echo "omawsl: unknown category '$category' (expected language, editor, or storage)" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_command "$@"
fi
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/lib_test.bats tests/omawsl_install_command_test.bats"`
Expected: PASS (all tests)

- [ ] **Step 6: Commit**

```bash
git add install/lib.sh bin/omawsl-sub/install.sh tests/lib_test.bats tests/omawsl_install_command_test.bats
git commit -m "feat(phase7): add bin/omawsl install"
```

---

### Task 13: Wire `bin/omawsl`'s dispatch table, update usage text and README

**Files:**
- Modify: `bin/omawsl`
- Modify: `tests/omawsl_cli_test.bats`
- Modify: `README.md:79-81`

**Interfaces:**
- Consumes: `omawsl_uninstall_command` (Task 8), `omawsl_migrate` (Task 9), `omawsl_update` (Task 10), `omawsl_doctor` (Task 11), `omawsl_install_command` (Task 12).

- [ ] **Step 1: Write the failing tests**

```bash
# --- append to tests/omawsl_cli_test.bats ---

@test "bin/omawsl usage text lists every subcommand" {
  run bash "$REPO_ROOT/bin/omawsl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"theme"* ]]
  [[ "$output" == *"update"* ]]
  [[ "$output" == *"migrate"* ]]
  [[ "$output" == *"install"* ]]
  [[ "$output" == *"uninstall"* ]]
  [[ "$output" == *"doctor"* ]]
}

@test "bin/omawsl doctor runs end to end with no selections made" {
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME" "$OMAWSL_STATE_DIR"
  run bash "$REPO_ROOT/bin/omawsl" doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"none selected"* ]]
}

@test "bin/omawsl uninstall with no name prints usage and exits non-zero" {
  run bash "$REPO_ROOT/bin/omawsl" uninstall
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage: omawsl uninstall"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_cli_test.bats"`
Expected: FAIL — usage text doesn't mention the new subcommands yet; `bin/omawsl doctor`/`uninstall` are unrecognized commands.

- [ ] **Step 3: Update `bin/omawsl`**

```bash
#!/usr/bin/env bash
set -euo pipefail

OMAWSL_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=omawsl-sub/theme.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/theme.sh"
# shellcheck source=omawsl-sub/items.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/items.sh"
# shellcheck source=omawsl-sub/migrate.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/migrate.sh"
# shellcheck source=omawsl-sub/update.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/update.sh"
# shellcheck source=omawsl-sub/uninstall.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/uninstall.sh"
# shellcheck source=omawsl-sub/install.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/install.sh"
# shellcheck source=omawsl-sub/doctor.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/doctor.sh"

omawsl_usage() {
  cat <<'EOF'
Usage: omawsl <command> [args]

Commands:
  theme [name]              Apply one of the ported themes. With no name,
                             choose interactively.
  update                    Pull the latest omawsl and run pending
                             migrations.
  migrate                   Run pending migrations only, without pulling.
  install [category] [item] Add a language/editor/storage item. With no
                             args, choose interactively.
  uninstall <name>          Remove one installed item by name.
  doctor                    Report what's installed/configured, and what's
                             still pending.
EOF
}

omawsl_main() {
  local cmd="${1:-}"
  case "$cmd" in
    theme)
      shift
      omawsl_theme_command "$@"
      ;;
    update)
      omawsl_update
      ;;
    migrate)
      omawsl_migrate
      ;;
    install)
      shift
      omawsl_install_command "$@"
      ;;
    uninstall)
      shift
      omawsl_uninstall_command "$@"
      ;;
    doctor)
      omawsl_doctor
      ;;
    ""|-h|--help)
      omawsl_usage
      ;;
    *)
      echo "omawsl: unknown command '$cmd'" >&2
      omawsl_usage >&2
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_main "$@"
fi
```

- [ ] **Step 4: Update `README.md`'s Status section**

Replace `README.md:77-81`:

```markdown
## Status

omawsl's full CLI is now shipped: `bin/omawsl theme`, `update`, `migrate`,
`install`, `uninstall`, and `doctor`. Run `bin/omawsl` with no arguments for
the full command list.
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_cli_test.bats"`
Expected: PASS (all tests, including the 3 pre-existing ones)

- [ ] **Step 6: Run the entire test suite**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/"`
Expected: PASS across every `.bats` file (the pre-existing `windows_terminal_test.bats` `cmd.exe`-reachability flake, unrelated to this phase, is the one known exception per Phase 5/6's own notes — confirm it's still the *only* failure, not a new one).

- [ ] **Step 7: Commit**

```bash
git add bin/omawsl README.md tests/omawsl_cli_test.bats
git commit -m "feat(phase7): wire update/migrate/install/uninstall/doctor into bin/omawsl"
```

---

### Task 14 (human-only): Manual end-to-end verification

**Not implemented by an agentic worker** — this task requires a real WSL2 instance with real state to uninstall/reinstall against, and a decision only the user can make.

- [ ] **Step 1: Assistant runs `bin/omawsl doctor` against the real test WSL2 instance's current state** (languages/editors/storage already selected from prior phases' verification runs) and confirms the report matches what's actually installed.
- [ ] **Step 2: Assistant exercises `bin/omawsl install <category> <item>` for one item not yet installed** (e.g. a language not previously picked) and confirms it installs and `doctor` now reports it `[OK]`.
- [ ] **Step 3: Assistant exercises `bin/omawsl uninstall <name>` for that same item** and confirms `doctor` now reports it `[PENDING]` again (or omits it, since it's no longer selected — whichever this task's actual implementation does), and that re-running `uninstall` on the same name a second time is a clean no-op, not an error.
- [ ] **Step 4: Assistant exercises `bin/omawsl migrate`** with the (still-empty) real `migrations/` dir and confirms it reports "up to date" cleanly.
- [ ] **Step 5: `bin/omawsl update` is verified against a local scratch git fixture, not the live GitHub remote** — no GitHub remote exists for this repo yet (deliberate, see Global Constraints above), so a real `git pull` against `github.com/tunacinsoy/omawsl` can't be exercised until that remote exists. Assistant sets up a throwaway local bare repo standing in for `$OMAWSL_HOME`'s origin (same shape as this plan's own `omawsl_update_test.bats` fixture, just on the real WSL2 instance) and confirms the dirty-tree guard and the pull-then-migrate flow both work for real, end to end.
- [ ] **Step 6: User confirms** all of the above, including that nothing under `install/`, `uninstall/`, or `bin/` from Phases 1-6 regressed.
- [ ] **Step 7: Separately — ask the user explicitly whether to create the GitHub remote now** (`gh repo create tunacinsoy/omawsl` or equivalent, then push `master`). Per this project's own standing feedback rule, do NOT do this automatically just because Phase 7/v1 is done — the user's own plan to do it "once all 7 phases are done" is context, not standing authorization. Only proceed if the user says yes in this specific conversation.
- [ ] **Step 8 (only after Step 6's sign-off):** update `docs/superpowers/plans/roadmap.md`'s Phase 7 entry to DONE, matching every prior phase's own closing entry shape (what shipped, test count, what Task 14 found, if anything).
