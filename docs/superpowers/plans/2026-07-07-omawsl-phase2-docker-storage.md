# omawsl Phase 2: Docker + Storage — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `docker.sh` (the `OMAWSL_DOCKER_MODE` branch: native Engine-only install with systemd/PATH-collision handling, vs. Docker Desktop detect-and-defer) and `select-dev-storage.sh` (MySQL/Redis/PostgreSQL as idempotent Docker containers, driven by `OMAWSL_STORAGE`) to the existing Phase 1 skeleton, and give `windows-prereq-checklist.sh` its first real checklist item (Docker Desktop, when chosen and not yet detected).

**Architecture:** `docker.sh` branches on `OMAWSL_DOCKER_MODE` between `omawsl_docker_engine` (idempotent systemd-support guard, first-ever third-party apt repo in this codebase for `docker-ce`, group membership, a PATH-collision guard against Docker Desktop's interop shim, and a deliberate early `exit 0` when a WSL restart is required) and `omawsl_docker_desktop` (pure detect-and-defer, never installs `docker-ce`). `select-dev-storage.sh` creates one container per `OMAWSL_STORAGE` selection through a small `omawsl_ensure_container` helper guarded by a name-existence check. Both scripts plug into the existing `terminal.sh` dispatch table and `windows-prereq-checklist.sh`'s already-real (if currently empty) extension point, without restructuring either. Every filesystem path this phase would otherwise hardcode (`/etc/wsl.conf`, the Docker apt sources file, the apt keyrings dir) is resolvable through an `OMAWSL_*` environment-variable override, mirroring the `OMAWSL_STATE_DIR` pattern `lib.sh` already established in Phase 1 — this is what keeps the whole phase testable without touching real system files or requiring root.

**Tech Stack:** Bash (`set -euo pipefail`, matching every existing script), `docker-ce`/`docker-ce-cli`/`containerd.io`/`docker-buildx-plugin`/`docker-compose-plugin` via Docker's official apt repo, `mysql:8`/`redis:7`/`postgres:16` official Docker Hub images, bats-core (already vendored).

## Global Constraints

(Copied verbatim or paraphrased from `docs/superpowers/specs/2026-07-05-omawsl-design.md` and Phase 1's own established conventions — every task below implicitly inherits these.)

- `OMAWSL_DOCKER_MODE` and `OMAWSL_STORAGE` are plain/comma-delimited strings, already produced and persisted by Phase 1's `first-run-choices.sh` — this phase only *consumes* them, via `omawsl_list_has` for `OMAWSL_STORAGE` and a direct string comparison for the single-select `OMAWSL_DOCKER_MODE` (§6).
- **Nothing is pre-selected by default** for `OMAWSL_STORAGE`, and **selecting nothing is a valid, expected state** — `select-dev-storage.sh` must no-op cleanly, not assume at least one option was picked (§6, §12).
- Membership checks on `OMAWSL_STORAGE` wrap both sides in comma delimiters via `omawsl_list_has`, never a bare substring check (§6).
- `install/terminal/*.sh` scripts are **sourced, not sub-shelled**, by `terminal.sh`, so a failure (or a deliberate `exit`) stops the whole run immediately (§8, §9).
- Every install script must be **runnable in isolation** (sourced directly with the relevant `OMAWSL_*` vars pre-set) (§15).
- **Engine-only is the pre-highlighted default.** Anything other than the literal `"Docker Desktop for Windows"` string is treated as Engine-only (§6, §9).
- **Docker Desktop mode must never install `docker-ce`** — detect-and-defer only, same shape as the VS Code/Cursor checks later phases add (§9, §10).
- The Docker Desktop prerequisite surfaces in `windows-prereq-checklist.sh` **only if** Desktop mode was chosen **and** `docker` isn't already reachable (§6, §9).
- If Docker Desktop's `docker.exe` interop and a natively-installed `docker` are both reachable, warn about the PATH collision rather than silently leaving resolution order to chance (§9 step 3).
- A script running inside the live WSL instance **cannot restart the WSL VM itself** — if systemd support was just enabled, stop with a clear restart message via `exit 0` (which, because `terminal/*.sh` scripts are sourced, terminates the entire `install.sh` run, not just `docker.sh` — intentional) rather than continuing into a state Docker can't actually use yet (§9 step 4).
- Storage containers are guarded by a name-existence check so re-running is a no-op, not a crash on `docker run`'s name collision (§7, §12).

---

## Environment Notes for Whoever Runs This Plan

- Same test instance as Phase 1: reachable via `wsl.exe -d Ubuntu -- bash -c "..."`, repo at `/mnt/c/Users/tcins/vscode-workspace/omawsl` inside WSL. Every `.bats` file runs the same way:
  ```
  wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/<file>.bats"
  ```
- **`sudo` still requires an interactive password** — every test in this plan stubs `sudo`/`curl`/`gpg`/`docker`, never calls the real thing. The one genuinely unstubbed step (real `docker-ce` install, real container creation, a real `wsl --shutdown` restart) is Task 7, and it is explicitly a **manual task for the human running this plan**.
- **Docker is not installed on the test instance yet** (Phase 2 hasn't merged) — a few tests below lean on that fact (e.g. `which -a docker` returning nothing for the real-host default case). If Docker Desktop or `docker-ce` is ever manually installed on this machine outside of a plan run, revisit those specific assertions.
- This phase introduces the first **third-party apt repository** in the codebase (Docker's own, for `docker-ce`) — every path it would otherwise touch on the real filesystem (`/etc/wsl.conf`, `/etc/apt/sources.list.d/docker.list`, `/etc/apt/keyrings`) is made overridable via an `OMAWSL_*` env var, exactly like `lib.sh`'s existing `OMAWSL_STATE_DIR` override, so tests never need root or touch real system files.
- **User-facing messages use plain `echo`, not `gum style`** — this diverges from the design spec's illustrative pseudocode in §9, but matches the actual convention `windows-prereq-checklist.sh` already established in Phase 1 (plain `echo` for every advisory message, no `gum` dependency for non-interactive text).

## File Structure

```
omawsl/
├── install/
│   ├── lib.sh                              # + omawsl_docker_reachable (Task 1)
│   ├── windows-prereq-checklist.sh         # + real Docker Desktop item (Task 3)
│   ├── terminal.sh                         # + docker.sh, select-dev-storage.sh in the dispatch table (Task 5)
│   └── terminal/
│       ├── docker.sh                       # NEW (Task 2)
│       └── select-dev-storage.sh           # NEW (Task 4)
└── tests/
    ├── lib_test.bats                       # + 2 tests (Task 1)
    ├── docker_test.bats                    # NEW (Task 2)
    ├── windows_prereq_checklist_test.bats  # + 3 tests (Task 3)
    ├── select_dev_storage_test.bats        # NEW (Task 4)
    ├── terminal_test.bats                  # updated fixed-order list (Task 5)
    └── install_test.bats                   # updated end-to-end coverage (Task 6)
```

---

### Task 1: `omawsl_docker_reachable` in `install/lib.sh`

**Files:**
- Modify: `install/lib.sh`
- Modify: `tests/lib_test.bats`

**Interfaces:**
- Produces: `omawsl_docker_reachable` (exit 0/1) — used by both `windows-prereq-checklist.sh` (Task 3) and `docker.sh`'s Desktop-mode check (Task 2).

- [ ] **Step 1: Write the failing tests**

Append to `tests/lib_test.bats` (after the existing tests, before the final closing of the file):

```bash

@test "omawsl_docker_reachable: true when a docker command is present" {
  stub_command docker
  run omawsl_docker_reachable
  [ "$status" -eq 0 ]
}

@test "omawsl_docker_reachable: false when nothing named docker is on PATH" {
  run bash -c '
    export PATH=/nonexistent
    source "'"$REPO_ROOT"'/install/lib.sh"
    omawsl_docker_reachable
  '
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/lib_test.bats"
```
Expected: the two new tests FAIL (`omawsl_docker_reachable: command not found`), the existing 17 still pass.

- [ ] **Step 3: Add `omawsl_docker_reachable` to `install/lib.sh`**

Append to `install/lib.sh`:

```bash

# omawsl_docker_reachable
# True if a `docker` CLI is already reachable on PATH. Shared by
# windows-prereq-checklist.sh (deciding whether Docker Desktop needs
# flagging as a pending Windows-side prerequisite) and docker.sh's own
# Desktop-mode detect-and-defer check (design spec §6, §9).
omawsl_docker_reachable() {
  command -v docker &>/dev/null
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/lib_test.bats"
```
Expected: `19 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/lib.sh tests/lib_test.bats
git commit -m "feat: add omawsl_docker_reachable shared helper"
```

---

### Task 2: `install/terminal/docker.sh`

**Files:**
- Create: `install/terminal/docker.sh`
- Create: `tests/docker_test.bats`

**Interfaces:**
- Consumes: `omawsl_docker_reachable` (Task 1)
- Produces: `omawsl_docker` (dispatcher, no args), `omawsl_docker_engine [wsl_conf_file] [apt_sources_file] [keyrings_dir]`, `omawsl_docker_desktop`, `omawsl_install_docker_ce [apt_sources_file] [keyrings_dir]`, `omawsl_check_docker_path_collision [which_a_docker_output]`.

- [ ] **Step 1: Write the failing tests**

Create `tests/docker_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/docker.sh"
  stub_command sudo
  stub_command curl
  stub_command gpg
  export USER=testuser
}

# --- omawsl_docker_desktop ------------------------------------------------

@test "desktop mode: does nothing when docker is already reachable" {
  stub_command docker
  run omawsl_docker_desktop
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "desktop mode: prints a deferral message when docker isn't reachable" {
  run bash -c '
    export PATH=/nonexistent
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_docker_desktop
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"docs/windows-setup.md#docker-desktop"* ]]
  [[ "$output" == *"re-run install.sh"* ]]
}

# --- omawsl_docker dispatcher ----------------------------------------------

@test "dispatcher: routes to desktop mode when Docker Desktop is selected" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_docker_desktop() { echo "DESKTOP_CALLED"; }
    export OMAWSL_DOCKER_MODE="Docker Desktop for Windows"
    omawsl_docker
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "DESKTOP_CALLED" ]]
}

@test "dispatcher: routes to engine mode for the recommended option" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_docker_engine() { echo "ENGINE_CALLED"; }
    export OMAWSL_DOCKER_MODE="Docker Engine only, inside WSL (recommended)"
    omawsl_docker
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "ENGINE_CALLED" ]]
}

@test "dispatcher: routes to engine mode when OMAWSL_DOCKER_MODE is unset" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_docker_engine() { echo "ENGINE_CALLED"; }
    omawsl_docker
  '
  [ "$status" -eq 0 ]
  [[ "$output" == "ENGINE_CALLED" ]]
}

# --- omawsl_check_docker_path_collision -------------------------------------

@test "path collision: a single docker path is fine" {
  run omawsl_check_docker_path_collision "/usr/bin/docker"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "path collision: native docker resolving first is fine even with a second path present" {
  run omawsl_check_docker_path_collision "/usr/bin/docker
/mnt/c/Program Files/Docker/resources/bin/docker"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "path collision: warns when a non-native docker resolves first" {
  run omawsl_check_docker_path_collision "/mnt/c/Program Files/Docker/resources/bin/docker
/usr/bin/docker"
  [ "$status" -eq 0 ]
  [[ "$output" == *"multiple 'docker' binaries"* ]]
  [[ "$output" == *"/usr/bin/docker"* ]]
}

# --- omawsl_install_docker_ce ------------------------------------------------

@test "install_docker_ce: adds the apt repo and key when the sources file doesn't exist yet" {
  sources_file="$BATS_TEST_TMPDIR/docker.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  run omawsl_install_docker_ce "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo install -m 0755 -d $keyrings_dir"* ]]
  [[ "$(stub_calls)" == *"curl -fsSL https://download.docker.com/linux/ubuntu/gpg"* ]]
  [[ "$(stub_calls)" == *"sudo gpg --dearmor -o $keyrings_dir/docker.gpg"* ]]
  [[ "$(stub_calls)" == *"sudo tee $sources_file"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]
}

@test "install_docker_ce: skips the repo-add step when the sources file already exists" {
  sources_file="$BATS_TEST_TMPDIR/docker.list"
  keyrings_dir="$BATS_TEST_TMPDIR/keyrings"
  : > "$sources_file"
  run omawsl_install_docker_ce "$sources_file" "$keyrings_dir"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"curl -fsSL"* ]]
  [[ "$(stub_calls)" != *"gpg --dearmor"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]
}

# --- omawsl_docker_engine -----------------------------------------------------

@test "engine mode: enables systemd and stops with a restart message when it wasn't set yet" {
  wsl_conf="$BATS_TEST_TMPDIR/wsl.conf"
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_install_docker_ce() { echo "DOCKER_CE_INSTALLED"; }
    export USER=testuser
    omawsl_docker_engine "'"$wsl_conf"'" "'"$BATS_TEST_TMPDIR"'/docker.list" "'"$BATS_TEST_TMPDIR"'/keyrings"
    echo "SHOULD_NOT_REACH_HERE"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"WSL systemd support was just enabled"* ]]
  [[ "$output" != *"DOCKER_CE_INSTALLED"* ]]
  [[ "$output" != *"SHOULD_NOT_REACH_HERE"* ]]
  [[ "$(stub_calls)" == *"sudo tee -a $wsl_conf"* ]]
}

@test "engine mode: continues past systemd, installs docker, adds the user to the docker group, when systemd is already enabled" {
  wsl_conf="$BATS_TEST_TMPDIR/wsl-already.conf"
  printf '[boot]\nsystemd=true\n' > "$wsl_conf"

  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_install_docker_ce() { echo "DOCKER_CE_INSTALLED"; }
    export USER=testuser
    omawsl_docker_engine "'"$wsl_conf"'" "'"$BATS_TEST_TMPDIR"'/docker.list" "'"$BATS_TEST_TMPDIR"'/keyrings"
    echo "REACHED_END"
  '

  [ "$status" -eq 0 ]
  [[ "$output" == *"DOCKER_CE_INSTALLED"* ]]
  [[ "$output" == *"open a new terminal"* ]]
  [[ "$output" == *"REACHED_END"* ]]
  [[ "$output" != *"WSL systemd support was just enabled"* ]]
  [[ "$(stub_calls)" == *"sudo usermod -aG docker testuser"* ]]
  [[ "$(stub_calls)" != *"sudo tee -a $wsl_conf"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/docker_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Write `install/terminal/docker.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

OMAWSL_DOCKER_MODE_DESKTOP="Docker Desktop for Windows"

# omawsl_docker_desktop
# Docker Desktop was explicitly chosen (design spec §9): never installs
# docker-ce. Detect-and-defer, the same shape later phases use for
# VS Code/Cursor - if `docker` is already reachable via Docker Desktop's
# WSL integration, there's nothing to do; otherwise this is a genuine
# Windows-side prerequisite already surfaced up front by
# windows-prereq-checklist.sh, so this is just a non-fatal reminder if the
# user proceeded anyway without completing it yet.
omawsl_docker_desktop() {
  if omawsl_docker_reachable; then
    return 0
  fi

  echo "omawsl: Docker Desktop was selected but 'docker' isn't reachable yet."
  echo "Install Docker Desktop and enable WSL integration for this distro - see docs/windows-setup.md#docker-desktop."
  echo "Nothing else to do here for now; re-run install.sh after completing that step."
}

# omawsl_check_docker_path_collision [which_a_docker_output]
# Docker Desktop's docker.exe interop shim can land earlier on PATH than the
# natively apt-installed docker binary - a real case seen on an actual test
# machine during this project's design review (design spec §9 step 3).
# Warns rather than silently leaving resolution order to chance. Takes the
# `which -a docker` output as an argument so it's unit-testable with
# fixture paths instead of depending on the real host's PATH.
omawsl_check_docker_path_collision() {
  local which_output="${1:-$(which -a docker 2>/dev/null || true)}"
  [[ -z "$which_output" ]] && return 0

  local first_path
  first_path="$(echo "$which_output" | head -n1)"
  local count
  count="$(echo "$which_output" | grep -c . || true)"

  if [[ "$count" -gt 1 && "$first_path" != "/usr/bin/docker" ]]; then
    echo "omawsl: multiple 'docker' binaries found on PATH:"
    echo "$which_output"
    echo "'$first_path' resolves first, which isn't the natively installed docker-ce."
    echo "Reorder your PATH (e.g. in ~/.bashrc) so /usr/bin/docker comes first, or the"
    echo "Docker Desktop interop version may shadow it unexpectedly."
  fi
}

# omawsl_install_docker_ce [apt_sources_file] [keyrings_dir]
# Idempotent: the repo-add + GPG-key steps only run once (guarded by the
# sources file not existing yet); `apt-get install` itself no-ops on
# already-installed packages regardless. Parameterized paths default to the
# real system locations and are only ever overridden in tests.
omawsl_install_docker_ce() {
  local apt_sources_file="${1:-/etc/apt/sources.list.d/docker.list}"
  local keyrings_dir="${2:-/etc/apt/keyrings}"

  sudo apt-get update -qq
  sudo apt-get install -y ca-certificates curl gnupg

  if [[ ! -f "$apt_sources_file" ]]; then
    sudo install -m 0755 -d "$keyrings_dir"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o "$keyrings_dir/docker.gpg"
    sudo chmod a+r "$keyrings_dir/docker.gpg"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyrings_dir/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | sudo tee "$apt_sources_file" >/dev/null
    sudo apt-get update -qq
  fi

  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# omawsl_docker_engine [wsl_conf_file] [apt_sources_file] [keyrings_dir]
# Engine-only is the pre-highlighted default (design spec §6, §9): installs
# docker-ce natively inside WSL, no Windows-side dependency. Every path
# defaults to an OMAWSL_* env-var override (falling back to the real system
# location) before falling back further to an explicit positional arg's
# default - this is what makes it safely callable both directly (tests,
# explicit tmp paths) and via the zero-arg terminal.sh dispatch table (a
# real run, where only the env-var override matters).
omawsl_docker_engine() {
  local wsl_conf="${1:-${OMAWSL_WSL_CONF_FILE:-/etc/wsl.conf}}"
  local apt_sources_file="${2:-${OMAWSL_DOCKER_APT_SOURCES_FILE:-/etc/apt/sources.list.d/docker.list}}"
  local keyrings_dir="${3:-${OMAWSL_DOCKER_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"
  local needs_restart=0

  if ! grep -q "^systemd=true" "$wsl_conf" 2>/dev/null; then
    printf '[boot]\nsystemd=true\n' | sudo tee -a "$wsl_conf" >/dev/null
    needs_restart=1
  fi

  omawsl_install_docker_ce "$apt_sources_file" "$keyrings_dir"

  sudo usermod -aG docker "$USER"
  echo "omawsl: open a new terminal (or run 'newgrp docker') before using Docker without sudo."

  omawsl_check_docker_path_collision

  # A script running inside the live WSL instance cannot restart the WSL VM
  # itself. Because install/terminal/*.sh scripts are sourced (not
  # sub-shelled) by terminal.sh, this `exit 0` deliberately terminates the
  # entire install.sh run, not just this script - intentional (design spec
  # §9): the remaining steps have no useful work to do until after the
  # restart, and re-running install.sh afterward resumes cleanly since this
  # guard becomes a no-op.
  if [[ "$needs_restart" == "1" ]]; then
    echo "omawsl: WSL systemd support was just enabled."
    echo "Run 'wsl --shutdown' from Windows (PowerShell/cmd), reopen this terminal, then re-run install.sh to finish Docker setup."
    exit 0
  fi
}

# omawsl_docker
# Branches on OMAWSL_DOCKER_MODE (design spec §6, §9). Treats anything other
# than the literal Docker Desktop option as Engine-only, matching that
# prompt's pre-highlighted default.
omawsl_docker() {
  if [[ "${OMAWSL_DOCKER_MODE:-}" == "$OMAWSL_DOCKER_MODE_DESKTOP" ]]; then
    omawsl_docker_desktop
  else
    omawsl_docker_engine
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_docker
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/docker_test.bats"
```
Expected: `12 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal/docker.sh tests/docker_test.bats
git commit -m "feat: add docker.sh (Engine-only native install vs. Docker Desktop detect-and-defer)"
```

---

### Task 3: `install/windows-prereq-checklist.sh` — real Docker Desktop item

**Files:**
- Modify: `install/windows-prereq-checklist.sh`
- Modify: `tests/windows_prereq_checklist_test.bats`

**Interfaces:**
- Consumes: `omawsl_docker_reachable` (Task 1)
- Modifies: `omawsl_windows_checklist_items` — now prints a real line when `OMAWSL_DOCKER_MODE` is Docker Desktop and `docker` isn't reachable yet, instead of always being empty.

- [ ] **Step 1: Write the failing tests**

Append to `tests/windows_prereq_checklist_test.bats`:

```bash

@test "real checklist: shows a Docker Desktop item when chosen and docker isn't reachable" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_DOCKER_MODE="Docker Desktop for Windows"
    export PATH=/nonexistent
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker Desktop"* ]]
  [[ "$output" == *"docs/windows-setup.md#docker-desktop"* ]]
}

@test "real checklist: shows nothing when Docker Desktop was chosen but docker is already reachable" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_DOCKER_MODE="Docker Desktop for Windows"
    docker() { :; }
    export -f docker
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "real checklist: shows nothing when Engine-only mode was chosen" {
  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/windows-prereq-checklist.sh"
    export OMAWSL_DOCKER_MODE="Docker Engine only, inside WSL (recommended)"
    export PATH=/nonexistent
    omawsl_windows_checklist_items
  '
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run tests to verify the new ones fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/windows_prereq_checklist_test.bats"
```
Expected: the 3 new tests FAIL (the first expects text that doesn't exist yet, the other two already pass trivially since the function is currently always empty — that's fine, they're here to lock in the "still empty" cases going forward).

- [ ] **Step 3: Update `omawsl_windows_checklist_items` in `install/windows-prereq-checklist.sh`**

Replace:
```bash
omawsl_windows_checklist_items() {
  :
}
```
with:
```bash
# omawsl_windows_checklist_items
# Prints zero or more lines, each describing one pending Windows-side
# prerequisite relevant to what was actually selected. Phase 2 adds the
# first real item: Docker Desktop, shown only if that mode was chosen and
# `docker` isn't already reachable (design spec §6, §9). Later phases
# (VS Code/Cursor in Phase 4) extend this function further rather than
# restructuring it.
omawsl_windows_checklist_items() {
  if [[ "${OMAWSL_DOCKER_MODE:-}" == "Docker Desktop for Windows" ]] && ! omawsl_docker_reachable; then
    echo "  - Docker Desktop - docs/windows-setup.md#docker-desktop (install it, enable WSL integration for this distro, verify 'docker' is reachable)"
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/windows_prereq_checklist_test.bats"
```
Expected: `6 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/windows-prereq-checklist.sh tests/windows_prereq_checklist_test.bats
git commit -m "feat: populate windows-prereq-checklist.sh's first real item (Docker Desktop)"
```

---

### Task 4: `install/terminal/select-dev-storage.sh`

**Files:**
- Create: `install/terminal/select-dev-storage.sh`
- Create: `tests/select_dev_storage_test.bats`

**Interfaces:**
- Consumes: `omawsl_list_has` (Phase 1, `lib.sh`)
- Produces: `omawsl_install_storage` (no args), `omawsl_ensure_container <name> <docker run args...>`.

- [ ] **Step 1: Write the failing tests**

Create `tests/select_dev_storage_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/select-dev-storage.sh"

  DOCKER_EXISTING_CONTAINERS=""
  docker() {
    echo "docker $*" >> "$STUB_LOG"
    if [[ "$1" == "ps" ]]; then
      printf '%s\n' "$DOCKER_EXISTING_CONTAINERS"
    fi
    return 0
  }
  export -f docker
}

@test "creates a container for each selected storage option" {
  export OMAWSL_STORAGE="MySQL,PostgreSQL"
  omawsl_install_storage
  [[ "$(stub_calls)" == *"docker run -d --name omawsl-mysql"*"mysql:8"* ]]
  [[ "$(stub_calls)" == *"docker run -d --name omawsl-postgresql"*"postgres:16"* ]]
  [[ "$(stub_calls)" != *"omawsl-redis"* ]]
}

@test "creates all three when all three are selected" {
  export OMAWSL_STORAGE="MySQL,Redis,PostgreSQL"
  omawsl_install_storage
  [[ "$(stub_calls)" == *"omawsl-mysql"* ]]
  [[ "$(stub_calls)" == *"omawsl-redis"* ]]
  [[ "$(stub_calls)" == *"omawsl-postgresql"* ]]
}

@test "selecting nothing creates no containers" {
  export OMAWSL_STORAGE=""
  omawsl_install_storage
  [[ "$(stub_calls)" != *"docker run"* ]]
}

@test "no-ops cleanly when OMAWSL_STORAGE is unset entirely" {
  unset OMAWSL_STORAGE
  run omawsl_install_storage
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"docker run"* ]]
}

@test "skips creating a container that already exists (idempotent)" {
  export OMAWSL_STORAGE="Redis"
  DOCKER_EXISTING_CONTAINERS="omawsl-redis"
  omawsl_install_storage
  [[ "$(stub_calls)" != *"docker run"* ]]
  [[ "$(stub_calls)" == *"docker ps -a"* ]]
}

@test "creates redis when a differently-named container already exists" {
  export OMAWSL_STORAGE="Redis"
  DOCKER_EXISTING_CONTAINERS="some-other-container"
  omawsl_install_storage
  [[ "$(stub_calls)" == *"docker run -d --name omawsl-redis"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/select_dev_storage_test.bats"
```
Expected: every test FAILs (`No such file or directory`).

- [ ] **Step 3: Write `install/terminal/select-dev-storage.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_ensure_container <name> <docker run args...>
# Idempotent: does nothing if a container by this name already exists
# (running or stopped) - `docker run` itself is not safe to re-run blindly,
# since it errors out on a name collision rather than no-op (design spec
# §7: "container creation is guarded by a name-existence check").
omawsl_ensure_container() {
  local name="$1"; shift
  if docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    return 0
  fi
  docker run -d --name "$name" --restart unless-stopped "$@"
}

# omawsl_install_storage
# Creates one Docker container per selection in OMAWSL_STORAGE. Nothing is
# pre-selected by default and selecting nothing is a valid, expected state
# (design spec §6, §12) - each branch below no-ops cleanly if its option
# wasn't picked, rather than assuming at least one was. Passwords below are
# a fixed local-dev-only default, not a secret - these containers are only
# reachable from localhost via WSL2's automatic port-forwarding.
omawsl_install_storage() {
  local storage="${OMAWSL_STORAGE:-}"

  if omawsl_list_has "$storage" "MySQL"; then
    omawsl_ensure_container omawsl-mysql \
      -p 3306:3306 \
      -e MYSQL_ROOT_PASSWORD=password \
      -v omawsl-mysql-data:/var/lib/mysql \
      mysql:8
  fi

  if omawsl_list_has "$storage" "Redis"; then
    omawsl_ensure_container omawsl-redis \
      -p 6379:6379 \
      -v omawsl-redis-data:/data \
      redis:7
  fi

  if omawsl_list_has "$storage" "PostgreSQL"; then
    omawsl_ensure_container omawsl-postgresql \
      -p 5432:5432 \
      -e POSTGRES_PASSWORD=password \
      -v omawsl-postgresql-data:/var/lib/postgresql/data \
      postgres:16
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_storage
fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/select_dev_storage_test.bats"
```
Expected: `6 tests, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal/select-dev-storage.sh tests/select_dev_storage_test.bats
git commit -m "feat: add select-dev-storage.sh (MySQL/Redis/PostgreSQL as idempotent containers)"
```

---

### Task 5: Wire `docker.sh` and `select-dev-storage.sh` into `install/terminal.sh`

**Files:**
- Modify: `install/terminal.sh`
- Modify: `tests/terminal_test.bats`

**Interfaces:**
- Consumes: `omawsl_docker` (Task 2), `omawsl_install_storage` (Task 4)

- [ ] **Step 1: Write the failing test**

Replace the `@test` in `tests/terminal_test.bats` and update `setup()`:

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

  # Pre-seed systemd=true so the Docker engine-mode step (§9) doesn't stop
  # this run early asking for a WSL restart - that early-exit path has its
  # own dedicated coverage in docker_test.bats.
  export OMAWSL_WSL_CONF_FILE="$BATS_TEST_TMPDIR/wsl.conf"
  printf '[boot]\nsystemd=true\n' > "$OMAWSL_WSL_CONF_FILE"
  export OMAWSL_DOCKER_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/docker.list"
  export OMAWSL_DOCKER_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  # Pre-seed the apt sources file as already-existing so
  # omawsl_install_docker_ce takes its "already configured" branch and
  # skips the curl|gpg / echo|tee repo-add pipes. Found during Task 5:
  # those pipes' stubbed sudo/curl/gpg exit near-instantly without
  # draining stdin (unlike the real commands), so when this whole script
  # runs as a freshly exec'd process the writer side can lose the SIGPIPE
  # race under pipefail (deterministic 141, not flaky). Both pipes already
  # have dedicated, non-flaky coverage via a direct in-process call in
  # docker_test.bats (tests 9-10), so this loses no coverage.
  : > "$OMAWSL_DOCKER_APT_SOURCES_FILE"
  export USER=testuser
}

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
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/terminal_test.bats"
```
Expected: FAILs (`actual_order` is missing the two new entries).

- [ ] **Step 3: Update `install/terminal.sh`**

Replace the `OMAWSL_TERMINAL_SCRIPTS` array and `SCRIPT_FUNCTIONS` map:

```bash
# Fixed order, sourced (not sub-shelled) so a failure stops the whole run
# immediately (design spec §8). Extended by later phases
# (select-dev-language.sh, cloud-tools.sh, the app-*.sh editor/tool
# scripts) rather than restructured.
OMAWSL_TERMINAL_SCRIPTS=(
  "terminal/required/app-gum.sh"
  "terminal/identification.sh"
  "terminal/a-shell.sh"
  "terminal/apps-terminal.sh"
  "terminal/docker.sh"
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

(The rest of `install/terminal.sh` — the shebang, `set -euo pipefail`, `OMAWSL_INSTALL_DIR`, the `lib.sh` source, and the final `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` guard — is unchanged.)

- [ ] **Step 4: Run test to verify it passes**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/terminal_test.bats"
```
Expected: `1 test, 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add install/terminal.sh tests/terminal_test.bats
git commit -m "feat: wire docker.sh and select-dev-storage.sh into terminal.sh's dispatch table"
```

---

### Task 6: Update `tests/install_test.bats` for full end-to-end coverage

**Files:**
- Modify: `tests/install_test.bats`

**Interfaces:** none new — this task only extends coverage of `install.sh` (Phase 1) now that it exercises Docker + storage too.

- [ ] **Step 1: Write the failing tests**

Replace `tests/install_test.bats` entirely:

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

  export OMAWSL_WSL_CONF_FILE="$BATS_TEST_TMPDIR/wsl.conf"
  printf '[boot]\nsystemd=true\n' > "$OMAWSL_WSL_CONF_FILE"
  export OMAWSL_DOCKER_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/docker.list"
  export OMAWSL_DOCKER_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  # Pre-seed the apt sources file as already-existing so
  # omawsl_install_docker_ce takes its "already configured" branch and
  # skips the curl|gpg / echo|tee repo-add pipes. Found during Task 5:
  # those pipes' stubbed sudo/curl/gpg exit near-instantly without
  # draining stdin (unlike the real commands), so when this whole script
  # runs as a freshly exec'd process the writer side can lose the SIGPIPE
  # race under pipefail (deterministic 141, not flaky). Both pipes already
  # have dedicated, non-flaky coverage via a direct in-process call in
  # docker_test.bats (tests 9-10), so this loses no coverage.
  : > "$OMAWSL_DOCKER_APT_SOURCES_FILE"
  export USER=testuser
}

@test "runs the full install end to end and writes version state" {
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Engine only, inside WSL (recommended)"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  run bash "$REPO_ROOT/install.sh"

  [ "$status" -eq 0 ]
  [[ "$output" == *"install complete"* ]]
  [ -f "$HOME/.bashrc" ]
  [ -f "$HOME/.inputrc" ]
  [ -f "$OMAWSL_STATE_DIR/version" ]
  [ "$(cat "$OMAWSL_STATE_DIR/version")" = "$(cat "$REPO_ROOT/version")" ]
  [ -f "$OMAWSL_STATE_DIR/choices.env" ]
  grep -q '^OMAWSL_NETWORK_MODE="Personal / unrestricted"$' "$OMAWSL_STATE_DIR/choices.env"
  grep -q '^OMAWSL_LANGUAGES=""$' "$OMAWSL_STATE_DIR/choices.env"
  grep -q '^OMAWSL_STORAGE=""$' "$OMAWSL_STATE_DIR/choices.env"
  [[ "$(stub_calls)" == *"sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]
}

@test "choosing Docker Desktop surfaces the pre-install checklist, and declining exits before installing" {
  # Relies on the real test machine not already having a `docker` command
  # reachable (true as of Phase 2 - Docker isn't installed on this instance
  # yet). If that ever changes, this test's premise needs revisiting.
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Desktop for Windows"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  run bash -c "echo n | bash '$REPO_ROOT/install.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker Desktop"* ]]
  [[ "$output" == *"Exiting - nothing has been installed yet"* ]]
  [[ "$output" != *"install complete"* ]]
  [ ! -f "$HOME/.bashrc" ]
}
```

- [ ] **Step 2: Run tests to verify the outcome**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/install_test.bats"
```
Expected: `2 tests, 0 failures`. (No implementation step needed here — Tasks 1–5 already made `install.sh` support this; this task is pure test-coverage catch-up. If the second test fails because the real test machine already has some `docker` binary on PATH, that's a real environment fact to report rather than a bug in Tasks 1–5 — see the note in that test.)

- [ ] **Step 3: Run the entire test suite to confirm nothing regressed**

Run:
```
wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/*.bats"
```
Expected: every file's tests pass, zero failures (51 from Phase 1 + 2 lib + 12 docker + 3 checklist + 6 storage = 74, plus `install_test.bats`'s count is unchanged at 2 and `terminal_test.bats`'s at 1, both already included in the 51 — the important thing is zero failures, not the exact total).

- [ ] **Step 4: Commit**

```bash
git add tests/install_test.bats
git commit -m "test: extend install_test.bats for Docker + storage end-to-end coverage"
```

---

### Task 7: Manual end-to-end verification (human-in-the-loop)

**Files:** none — this task produces no new code, only a verification record.

This is the one step in this plan the agent executing it should **not** attempt: it requires a real `sudo` password against the live test WSL instance, a real `docker-ce` install from Docker's real apt repo, and (likely) a real `wsl --shutdown` restart. Everything up through Task 6 is fully verified by the automated, stubbed test suite — this task is the final "does the real thing actually work, unstubbed" check.

- [x] **Step 1 (human): Run the real install from a clean-enough state**

From inside the WSL Ubuntu terminal itself (not via `wsl.exe -d Ubuntu --`, since this needs to prompt you for your password interactively):

```bash
bash /mnt/c/Users/tcins/vscode-workspace/omawsl/install.sh
```

(Using `install.sh` directly rather than `boot.sh`, same as Phase 1's manual verification — the GitHub repo still doesn't exist yet.)

- [x] **Step 2 (human): Pick Docker Engine-only and at least one storage option**

Answer the Docker prompt with the recommended Engine-only option, and pick at least one storage option (e.g. PostgreSQL) so both new code paths get exercised for real.

- [x] **Step 3 (human): Handle the expected first-run restart**

The first real run will very likely hit the "WSL systemd support was just enabled" message and exit 0 (unless this WSL instance already has `systemd=true` in `/etc/wsl.conf` from some earlier manual poke). If it does:
1. From Windows PowerShell/cmd: `wsl --shutdown`
2. Reopen the WSL terminal
3. Re-run the same command from Step 1

(Not hit on the actual run — this fresh WSL2 Ubuntu 26.04 instance already had `systemd=true`, so the guard was a no-op and the run proceeded straight through.)

- [x] **Step 4 (human): Confirm Docker actually works**

After the run completes with `omawsl: install complete.`:
- `docker --version` succeeds.
- `groups` includes `docker` (may need a new terminal or `newgrp docker` if you haven't opened a fresh shell since the run).
- `docker ps -a` shows the container(s) matching whatever storage you picked in Step 2 (e.g. `omawsl-postgresql`), in the `Up` state.
- Re-run `bash install.sh` a second time end to end (same answers) and confirm it completes cleanly with no errors — this is the idempotency check: the systemd guard, the apt-repo-add, and the container creation should all silently no-op the second time.

- [x] **Step 5 (human): Report back**

Tell me either "it worked, here's what I saw" or paste the exact error/output if something broke. If something breaks, that's the systematic-debugging skill's territory next.

**Outcome: two real bugs found and fixed during this step, neither catchable by the stubbed test suite:**
1. `select-dev-storage.sh` crashed with "permission denied while trying to connect to the docker API" on the first real run. Root cause: `docker.sh`'s `sudo usermod -aG docker "$USER"` doesn't take effect in the already-running install.sh session (Linux only refreshes group membership on next login), and `terminal/*.sh` scripts are sourced into that same session, so the very next script's bare `docker` calls ran without the new group. Fixed by routing `omawsl_ensure_container` through `sudo docker` instead (commit `871a92a`, TDD'd directly on `master`, no worktree needed for a fix this size).
2. After that fix, the human still hit the same permission error running `docker ps` themselves in their own terminal right after `install: complete.` — expected (same group-refresh issue, now for their interactive shell), but the one-time mid-run reminder about it had already scrolled out of view under `terminal/libraries.sh`'s own apt-get output. Fixed by adding `omawsl_docker_final_reminder` and printing it again in `install.sh`'s final summary (commit `abc46e8`), plus hardening an `install_test.bats` test whose PATH-exclusion trick broke once real `docker-ce` ended up installed on the dev machine for real.

Re-ran the full flow (including the idempotency re-run) after both fixes: clean `omawsl: install complete.`, reminder printed at the end, second run showed `0 upgraded, 0 newly installed, 0 to remove` — confirmed idempotent.

- [x] **Step 6 (human, only once Step 5 confirms success): confirm the commit history is clean**

Run `git log --oneline` and check it reads as a clean, incremental history of Tasks 1–6 (no fixup commits needed). If everything's fine, update `docs/superpowers/plans/roadmap.md`'s Phase 2 entry to "DONE, merged to `master`" (matching Phase 1's entry format) and Phase 3 is next.

(History includes the merge commit plus two small follow-up fix commits from real-world verification, `871a92a` and `abc46e8` — expected and consistent with Phase 1's own precedent of the plan being a living document.)

---

## Self-Review Notes

- **Spec coverage:** §9 (Docker: Engine-only native install, systemd guard, PATH-collision guard, Docker Desktop detect-and-defer, the restart-required early exit) → Task 2. §6/§9's Docker Desktop checklist item → Task 3. §12's storage section (MySQL/Redis/PostgreSQL as idempotent Docker containers, nothing pre-selected) → Task 4. §7's "container creation is guarded by a name-existence check" and "sourced, not sub-shelled" error model → Tasks 2, 4, 5. §15's "runnable in isolation" requirement → every task's tests call each script's functions directly with explicit args/env vars, no full-pipeline dependency required. Everything else in the design spec (editors, theming, languages/cloud-tools, Windows-side docs, the rest of `bin/omawsl`) is out of scope for Phase 2 per `docs/superpowers/plans/roadmap.md`.
- **Placeholder scan:** no TBD/TODO markers; every step has complete, runnable code; no "similar to Task N" shortcuts.
- **Type/name consistency check:** `omawsl_docker_reachable` (Task 1) is called identically in Task 2 (`docker.sh`) and Task 3 (`windows-prereq-checklist.sh`). `omawsl_docker` (Task 2) and `omawsl_install_storage` (Task 4) are the exact function names registered in Task 5's `SCRIPT_FUNCTIONS` map. `OMAWSL_WSL_CONF_FILE`, `OMAWSL_DOCKER_APT_SOURCES_FILE`, `OMAWSL_DOCKER_APT_KEYRINGS_DIR` (Task 2) are the exact env vars set in Task 5's and Task 6's test setups. `omawsl_list_has` (Phase 1) is used identically in Task 4.
