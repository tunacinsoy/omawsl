# Docker Daemon Proxy Auto-Configuration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect a corporate HTTP(S) proxy from the environment and configure `dockerd` (Engine-in-WSL mode only) to use it via its own exclusively-owned systemd drop-in, so image pulls stop silently timing out behind a corp proxy — plus a passive `doctor` check and uninstall symmetry.

**Architecture:** Three small, independently-testable pure-bash functions added to `install/terminal/docker.sh` (env-var detection with upper/lowercase fallback, conflict detection against any *other* file in the drop-in directory, and the idempotent configure/write function itself), wired into the existing `omawsl_docker_engine` install path right after `docker-ce` installs. `uninstall/docker.sh` and `bin/omawsl-sub/doctor.sh` are extended symmetrically. The never-touch corp-safe-config policy gets a narrow, explicit, tested exception for exactly one filename.

**Tech Stack:** Bash (`set -euo pipefail`, matching every existing script in this repo), bats-core (vendored at `tests/.bats-core/bin/bats`), no new dependencies.

## Global Constraints

- Every new/modified function must remain callable both as a real system call (default paths) and with explicit path arguments for tests, matching the existing `omawsl_docker_engine`/`omawsl_install_docker_ce` parameter pattern (positional arg, falling back to an `OMAWSL_*` env var override, falling back to the real system path).
- The managed file is always named exactly `omawsl-proxy.conf` — never `http-proxy.conf` or any other name a corp IT manual might already use.
- omawsl must never write anything to `/etc/systemd/system/docker.service.d/` if any *other* file already in that directory sets a proxy environment variable — back off silently (one informational line only) rather than risk two drop-ins overriding each other.
- `sudo systemctl restart docker` must only run when the drop-in's content actually changed — never on every idempotent re-run.
- Docker Desktop mode is untouched by all of this — its proxy setting is a Windows-side GUI setting, outside anything a WSL script can reach.
- All new tests run via: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/<file>.bats"` (verified working, Bats 1.14.0, at the start of this plan).

---

### Task 1: `omawsl_detect_proxy_env` helper

**Files:**
- Modify: `install/terminal/docker.sh` (add function after `omawsl_check_docker_path_collision`, i.e. after line 55, before the `omawsl_install_docker_ce` comment block at line 57)
- Test: `tests/docker_test.bats` (new section after the "path collision" tests, i.e. after line 95)

**Interfaces:**
- Produces: `omawsl_detect_proxy_env <VAR>` — echoes the value of the uppercase env var named `<VAR>` (e.g. `HTTP_PROXY`) if it's set and non-empty; otherwise echoes the value of its lowercase form (e.g. `http_proxy`); otherwise echoes an empty string. Never errors under `set -euo pipefail` regardless of whether either form is set.

- [ ] **Step 1: Write the failing tests**

Add to `tests/docker_test.bats`, after the path-collision tests (after line 95):

```bash
# --- omawsl_detect_proxy_env ------------------------------------------------

@test "detect_proxy_env: prefers the uppercase form when both are set" {
  export HTTP_PROXY="http://upper:8080"
  export http_proxy="http://lower:8080"
  run omawsl_detect_proxy_env HTTP_PROXY
  [ "$status" -eq 0 ]
  [ "$output" == "http://upper:8080" ]
}

@test "detect_proxy_env: falls back to the lowercase form when uppercase is unset" {
  unset HTTP_PROXY || true
  export http_proxy="http://lower:8080"
  run omawsl_detect_proxy_env HTTP_PROXY
  [ "$status" -eq 0 ]
  [ "$output" == "http://lower:8080" ]
}

@test "detect_proxy_env: empty when neither form is set" {
  unset HTTP_PROXY http_proxy || true
  run omawsl_detect_proxy_env HTTP_PROXY
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/docker_test.bats"`
Expected: the three new tests FAIL with "omawsl_detect_proxy_env: command not found" (or similar); all 16 pre-existing tests still PASS.

- [ ] **Step 3: Write minimal implementation**

Add to `install/terminal/docker.sh`, after `omawsl_check_docker_path_collision`'s closing brace (after line 55):

```bash
# omawsl_detect_proxy_env <VAR>
# Prints the value of the uppercase proxy env var <VAR> (e.g. HTTP_PROXY)
# if it's set and non-empty, else its lowercase form (http_proxy) - a real
# corp environment behind this feature had both set identically, so
# either convention is honored. Prints an empty string if neither is set;
# never errors under `set -u`, since a totally-unset variable can't be
# read via indirect expansion (${!var}) directly - each read is guarded
# with the `:-` default operator.
omawsl_detect_proxy_env() {
  local var="$1"
  local upper_val="${!var:-}"
  if [[ -n "$upper_val" ]]; then
    echo "$upper_val"
    return 0
  fi
  local lower_var; lower_var="$(echo "$var" | tr '[:upper:]' '[:lower:]')"
  echo "${!lower_var:-}"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/docker_test.bats"`
Expected: all 19 tests PASS (16 pre-existing + 3 new).

- [ ] **Step 5: Commit**

```bash
git add install/terminal/docker.sh tests/docker_test.bats
git commit -m "feat: add omawsl_detect_proxy_env helper for docker proxy autoconfig"
```

---

### Task 2: `omawsl_docker_proxy_conflict` helper

**Files:**
- Modify: `install/terminal/docker.sh` (add function after `omawsl_detect_proxy_env`)
- Test: `tests/docker_test.bats` (new section after Task 1's tests)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `omawsl_docker_proxy_conflict <dir> <own_file>` — returns 0 (true, "there is a conflict") if `<dir>` exists and contains at least one `*.conf` file, other than `<own_file>`, whose content matches `Environment=.*PROXY`. Returns 1 (false) if `<dir>` doesn't exist, or exists but no other `.conf` file in it sets a proxy.

- [ ] **Step 1: Write the failing tests**

Add to `tests/docker_test.bats`, after Task 1's tests:

```bash
# --- omawsl_docker_proxy_conflict --------------------------------------------

@test "proxy_conflict: false when the directory doesn't exist yet" {
  run omawsl_docker_proxy_conflict "$BATS_TEST_TMPDIR/nope" "$BATS_TEST_TMPDIR/nope/omawsl-proxy.conf"
  [ "$status" -eq 1 ]
}

@test "proxy_conflict: false when the directory is empty" {
  mkdir -p "$BATS_TEST_TMPDIR/svc-empty"
  run omawsl_docker_proxy_conflict "$BATS_TEST_TMPDIR/svc-empty" "$BATS_TEST_TMPDIR/svc-empty/omawsl-proxy.conf"
  [ "$status" -eq 1 ]
}

@test "proxy_conflict: false when only omawsl's own file sets a proxy" {
  local dir="$BATS_TEST_TMPDIR/svc-own"
  mkdir -p "$dir"
  printf '[Service]\nEnvironment="HTTP_PROXY=http://x:8080"\n' > "$dir/omawsl-proxy.conf"
  run omawsl_docker_proxy_conflict "$dir" "$dir/omawsl-proxy.conf"
  [ "$status" -eq 1 ]
}

@test "proxy_conflict: true when another .conf file already sets a proxy" {
  local dir="$BATS_TEST_TMPDIR/svc-corp"
  mkdir -p "$dir"
  printf '[Service]\nEnvironment="HTTP_PROXY=http://corp:8080"\n' > "$dir/corp-managed.conf"
  run omawsl_docker_proxy_conflict "$dir" "$dir/omawsl-proxy.conf"
  [ "$status" -eq 0 ]
}

@test "proxy_conflict: false when another .conf file exists but doesn't mention a proxy" {
  local dir="$BATS_TEST_TMPDIR/svc-unrelated"
  mkdir -p "$dir"
  printf '[Service]\nEnvironment="SOMETHING_ELSE=1"\n' > "$dir/unrelated.conf"
  run omawsl_docker_proxy_conflict "$dir" "$dir/omawsl-proxy.conf"
  [ "$status" -eq 1 ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/docker_test.bats"`
Expected: the five new tests FAIL ("omawsl_docker_proxy_conflict: command not found"); all 19 prior tests still PASS.

- [ ] **Step 3: Write minimal implementation**

Add to `install/terminal/docker.sh`, after `omawsl_detect_proxy_env`:

```bash
# omawsl_docker_proxy_conflict <dir> <own_file>
# True if some *other* .conf file already in <dir> sets a proxy - e.g. a
# corp IT manual's own drop-in. omawsl backs off entirely in this case
# rather than risk two drop-ins silently overriding each other for the
# same key (design spec
# docs/superpowers/specs/2026-07-29-docker-daemon-proxy-autoconfig-design.md:
# omawsl never edits or competes with a file it doesn't exclusively own).
omawsl_docker_proxy_conflict() {
  local dir="$1" own_file="$2"
  [[ -d "$dir" ]] || return 1
  local f
  for f in "$dir"/*.conf; do
    [[ -f "$f" ]] || continue
    [[ "$f" == "$own_file" ]] && continue
    grep -qE 'Environment=.*PROXY' "$f" 2>/dev/null && return 0
  done
  return 1
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/docker_test.bats"`
Expected: all 24 tests PASS (19 prior + 5 new).

- [ ] **Step 5: Commit**

```bash
git add install/terminal/docker.sh tests/docker_test.bats
git commit -m "feat: add omawsl_docker_proxy_conflict helper for docker proxy autoconfig"
```

---

### Task 3: `omawsl_configure_docker_proxy`

**Files:**
- Modify: `install/terminal/docker.sh` (add function after `omawsl_docker_proxy_conflict`)
- Test: `tests/docker_test.bats` (new section after Task 2's tests)

**Interfaces:**
- Consumes: `omawsl_detect_proxy_env <VAR>` (Task 1), `omawsl_docker_proxy_conflict <dir> <own_file>` (Task 2).
- Produces: `omawsl_configure_docker_proxy [dir]` — `dir` defaults to `${OMAWSL_DOCKER_SERVICE_D_DIR:-/etc/systemd/system/docker.service.d}`. The managed file is always `$dir/omawsl-proxy.conf`. No-ops silently if neither `HTTP_PROXY` nor `HTTPS_PROXY` resolves to a non-empty value. Backs off (removes its own file if present, prints one line, no restart) if `omawsl_docker_proxy_conflict` is true. Otherwise writes the drop-in (via `sudo mkdir -p` + `sudo tee`) only if content changed, then `sudo systemctl daemon-reload && sudo systemctl restart docker`, printing one confirmation line. Later tasks (4, 6) call this by name and rely on this exact signature.

This exact logic was validated end-to-end in a standalone script before being written into this plan (five scenarios: no-proxy no-op, fresh write, idempotent no-restart, conflict backoff, stale-file cleanup when a conflict appears later — all five behaved as specified).

- [ ] **Step 1: Write the failing tests**

Add to `tests/docker_test.bats`, after Task 2's tests. This needs a real-forwarding `sudo` stub (the default `stub_command sudo` from `setup()` only logs calls, it doesn't execute them) so idempotency and conflict-cleanup can be verified against real file content, matching the forwarding-stub pattern already used in `tests/uninstall_docker_test.bats` and `tests/cloud_tools_test.bats`:

```bash
# --- omawsl_configure_docker_proxy -------------------------------------------

_stub_sudo_forwarding() {
  sudo() {
    echo "sudo $*" >> "$STUB_LOG"
    case "$1" in
      mkdir) shift; command mkdir "$@" ;;
      tee) shift; command tee "$@" ;;
      rm) shift; command rm "$@" 2>/dev/null || true ;;
      systemctl) : ;;
      *) : ;;
    esac
  }
  export -f sudo
}

@test "configure_docker_proxy: no-ops when no proxy is set" {
  unset HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy || true
  _stub_sudo_forwarding
  local dir="$BATS_TEST_TMPDIR/svc-noproxy"
  run omawsl_configure_docker_proxy "$dir"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$dir/omawsl-proxy.conf" ]
  [ -z "$(stub_calls)" ]
}

@test "configure_docker_proxy: writes a fresh drop-in when a proxy is set" {
  export HTTP_PROXY="http://webproxy.example:8080"
  export HTTPS_PROXY="http://webproxy.example:8080"
  export NO_PROXY="localhost,127.0.0.1"
  _stub_sudo_forwarding
  local dir="$BATS_TEST_TMPDIR/svc-fresh"
  run omawsl_configure_docker_proxy "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"configured Docker daemon proxy"* ]]
  [ -f "$dir/omawsl-proxy.conf" ]
  [[ "$(cat "$dir/omawsl-proxy.conf")" == *'Environment="HTTP_PROXY=http://webproxy.example:8080"'* ]]
  [[ "$(cat "$dir/omawsl-proxy.conf")" == *'Environment="HTTPS_PROXY=http://webproxy.example:8080"'* ]]
  [[ "$(cat "$dir/omawsl-proxy.conf")" == *'Environment="NO_PROXY=localhost,127.0.0.1"'* ]]
  [[ "$(stub_calls)" == *"sudo mkdir -p $dir"* ]]
  [[ "$(stub_calls)" == *"sudo systemctl daemon-reload"* ]]
  [[ "$(stub_calls)" == *"sudo systemctl restart docker"* ]]
}

@test "configure_docker_proxy: idempotent - unchanged content skips write and restart" {
  export HTTP_PROXY="http://webproxy.example:8080"
  export HTTPS_PROXY="http://webproxy.example:8080"
  unset NO_PROXY no_proxy || true
  _stub_sudo_forwarding
  local dir="$BATS_TEST_TMPDIR/svc-idempotent"
  omawsl_configure_docker_proxy "$dir"
  : > "$STUB_LOG"
  run omawsl_configure_docker_proxy "$dir"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(stub_calls)" ]
}

@test "configure_docker_proxy: backs off when another file already configures a proxy" {
  export HTTP_PROXY="http://webproxy.example:8080"
  _stub_sudo_forwarding
  local dir="$BATS_TEST_TMPDIR/svc-conflict"
  mkdir -p "$dir"
  printf '[Service]\nEnvironment="HTTP_PROXY=http://corp-own:8080"\n' > "$dir/corp-managed.conf"
  run omawsl_configure_docker_proxy "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"leaving it as-is"* ]]
  [ ! -f "$dir/omawsl-proxy.conf" ]
  [[ "$(stub_calls)" != *"systemctl restart docker"* ]]
}

@test "configure_docker_proxy: removes its own stale file once a conflict appears" {
  export HTTP_PROXY="http://webproxy.example:8080"
  _stub_sudo_forwarding
  local dir="$BATS_TEST_TMPDIR/svc-stale"
  mkdir -p "$dir"
  printf '[Service]\nEnvironment="HTTP_PROXY=http://webproxy.example:8080"\n' > "$dir/omawsl-proxy.conf"
  printf '[Service]\nEnvironment="HTTP_PROXY=http://corp-own:8080"\n' > "$dir/corp-managed.conf"
  run omawsl_configure_docker_proxy "$dir"
  [ "$status" -eq 0 ]
  [ ! -f "$dir/omawsl-proxy.conf" ]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/docker_test.bats"`
Expected: the five new tests FAIL ("omawsl_configure_docker_proxy: command not found"); all 24 prior tests still PASS.

- [ ] **Step 3: Write minimal implementation**

Add to `install/terminal/docker.sh`, after `omawsl_docker_proxy_conflict`:

```bash
# omawsl_configure_docker_proxy [dir]
# Detects a corp proxy from the environment and configures dockerd to use
# it via its own exclusively-owned drop-in - never the conventional
# http-proxy.conf name a corp manual would use (design spec
# docs/superpowers/specs/2026-07-29-docker-daemon-proxy-autoconfig-design.md).
# dockerd runs as a systemd service and never inherits the interactive
# shell's HTTP_PROXY/HTTPS_PROXY - confirmed on a real corp machine, where
# curl (proxy-aware) reached registry-1.docker.io fine while `docker pull`
# (proxy-blind) died with `dial tcp ...:443 i/o timeout`. No-ops silently
# if no proxy is set (the common case). Backs off entirely - removing any
# stale file of its own - if another file in `dir` already configures a
# proxy, rather than risk two drop-ins overriding each other for the same
# key. Idempotent: skips the write and the daemon restart if the content
# is already correct, so re-running install.sh never bounces a working
# daemon.
omawsl_configure_docker_proxy() {
  local dir="${1:-${OMAWSL_DOCKER_SERVICE_D_DIR:-/etc/systemd/system/docker.service.d}}"
  local own_file="$dir/omawsl-proxy.conf"

  local http_proxy_val https_proxy_val no_proxy_val
  http_proxy_val="$(omawsl_detect_proxy_env HTTP_PROXY)"
  https_proxy_val="$(omawsl_detect_proxy_env HTTPS_PROXY)"
  no_proxy_val="$(omawsl_detect_proxy_env NO_PROXY)"

  if [[ -z "$http_proxy_val" && -z "$https_proxy_val" ]]; then
    return 0
  fi

  if omawsl_docker_proxy_conflict "$dir" "$own_file"; then
    echo "omawsl: found an existing proxy config elsewhere in $dir - leaving it as-is, not adding omawsl's own."
    sudo rm -f "$own_file"
    return 0
  fi

  local lines=("[Service]")
  [[ -n "$http_proxy_val" ]] && lines+=("Environment=\"HTTP_PROXY=$http_proxy_val\"")
  [[ -n "$https_proxy_val" ]] && lines+=("Environment=\"HTTPS_PROXY=$https_proxy_val\"")
  [[ -n "$no_proxy_val" ]] && lines+=("Environment=\"NO_PROXY=$no_proxy_val\"")
  local content; content="$(printf '%s\n' "${lines[@]}")"

  local existing=""
  [[ -f "$own_file" ]] && existing="$(cat "$own_file")"
  if [[ "$existing" == "$content" ]]; then
    return 0
  fi

  sudo mkdir -p "$dir"
  printf '%s\n' "$content" | sudo tee "$own_file" >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl restart docker
  echo "omawsl: configured Docker daemon proxy from HTTP_PROXY/HTTPS_PROXY."
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/docker_test.bats"`
Expected: all 29 tests PASS (24 prior + 5 new).

- [ ] **Step 5: Commit**

```bash
git add install/terminal/docker.sh tests/docker_test.bats
git commit -m "feat: add omawsl_configure_docker_proxy for docker daemon proxy autoconfig"
```

---

### Task 4: Wire into `omawsl_docker_engine`

**Files:**
- Modify: `install/terminal/docker.sh:81-115` (the `omawsl_docker_engine` function)
- Modify: `tests/docker_test.bats:129-144,170-190,192-210` (the three existing `omawsl_docker_engine` tests need a 4th argument added so they don't touch the real system path)
- Test: `tests/docker_test.bats` (one new test asserting the call happens)

**Interfaces:**
- Consumes: `omawsl_configure_docker_proxy [dir]` (Task 3).
- Produces: `omawsl_docker_engine` now accepts an optional 4th positional arg `docker_service_d_dir` (defaults the same way its other three path args do), and calls `omawsl_configure_docker_proxy "$docker_service_d_dir"` right after `omawsl_install_docker_ce`.

- [ ] **Step 1: Write the failing test**

Add to `tests/docker_test.bats`, in the "omawsl_docker_engine" section (after the existing tests, i.e. after line 210):

```bash
@test "engine mode: configures the docker proxy after installing docker-ce" {
  wsl_conf="$BATS_TEST_TMPDIR/wsl-proxy.conf"
  printf '[boot]\nsystemd=true\n' > "$wsl_conf"

  run bash -c '
    source "'"$REPO_ROOT"'/install/lib.sh"
    source "'"$REPO_ROOT"'/install/terminal/docker.sh"
    omawsl_install_docker_ce() { echo "DOCKER_CE_INSTALLED"; }
    omawsl_configure_docker_proxy() { echo "PROXY_CONFIGURED: $1"; }
    export USER=testuser
    omawsl_docker_engine "'"$wsl_conf"'" "'"$BATS_TEST_TMPDIR"'/docker.list" "'"$BATS_TEST_TMPDIR"'/keyrings" "'"$BATS_TEST_TMPDIR"'/docker.service.d"
  '
  [ "$status" -eq 0 ]
  [[ "$output" == *"DOCKER_CE_INSTALLED"* ]]
  [[ "$output" == *"PROXY_CONFIGURED: $BATS_TEST_TMPDIR/docker.service.d"* ]]
  # docker-ce install must happen before proxy configuration
  [[ "$output" == *"DOCKER_CE_INSTALLED"*"PROXY_CONFIGURED"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/docker_test.bats"`
Expected: the new test FAILS (output won't contain "PROXY_CONFIGURED" since `omawsl_docker_engine` doesn't call it yet); all 29 prior tests still PASS.

- [ ] **Step 3: Wire the call into `omawsl_docker_engine`**

In `install/terminal/docker.sh`, modify the function (lines 81-115):

```bash
# omawsl_docker_engine [wsl_conf_file] [apt_sources_file] [keyrings_dir] [docker_service_d_dir]
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
  local docker_service_d_dir="${4:-${OMAWSL_DOCKER_SERVICE_D_DIR:-/etc/systemd/system/docker.service.d}}"

  # A script running inside the live WSL instance cannot restart the WSL VM
  # itself. Because install/terminal/*.sh scripts are sourced (not
  # sub-shelled) by terminal.sh, this `exit 0` deliberately terminates the
  # entire install.sh run, not just this script - intentional (design spec
  # §9): the remaining steps have no useful work to do until after the
  # restart, so this returns immediately rather than installing docker-ce
  # against a not-yet-systemd WSL instance. Re-running install.sh afterward
  # resumes cleanly since this guard becomes a no-op.
  if ! grep -Eq '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$wsl_conf" 2>/dev/null; then
    printf '[boot]\nsystemd=true\n' | sudo tee -a "$wsl_conf" >/dev/null
    echo "omawsl: WSL systemd support was just enabled."
    echo "Run 'wsl --shutdown' from Windows (PowerShell/cmd), reopen this terminal, then re-run install.sh to finish Docker setup."
    exit 0
  fi

  omawsl_install_docker_ce "$apt_sources_file" "$keyrings_dir"
  omawsl_configure_docker_proxy "$docker_service_d_dir"

  sudo usermod -aG docker "$USER"
  echo "omawsl: open a new terminal (or run 'newgrp docker') before using Docker without sudo."

  omawsl_check_docker_path_collision
}
```

- [ ] **Step 4: Update the three pre-existing `omawsl_docker_engine` tests to pass a 4th arg**

In `tests/docker_test.bats`, update these three `run omawsl_docker_engine ...` calls to pass a 4th temp-dir argument (keeps them from touching the real `/etc/systemd/system/docker.service.d` path, matching this repo's existing convention of always parameterizing real system paths in tests):

- Line ~136 (`"engine mode: enables systemd and stops with a restart message..."`):
  ```bash
  omawsl_docker_engine "'"$wsl_conf"'" "'"$BATS_TEST_TMPDIR"'/docker.list" "'"$BATS_TEST_TMPDIR"'/keyrings" "'"$BATS_TEST_TMPDIR"'/docker.service.d"
  ```
- Line ~179 (`"engine mode: continues past systemd, installs docker..."`):
  ```bash
  omawsl_docker_engine "'"$wsl_conf"'" "'"$BATS_TEST_TMPDIR"'/docker.list" "'"$BATS_TEST_TMPDIR"'/keyrings" "'"$BATS_TEST_TMPDIR"'/docker.service.d"
  ```
- Line ~201 (`"engine mode: recognizes systemd=true with surrounding whitespace..."`):
  ```bash
  omawsl_docker_engine "'"$wsl_conf"'" "'"$BATS_TEST_TMPDIR"'/docker.list" "'"$BATS_TEST_TMPDIR"'/keyrings" "'"$BATS_TEST_TMPDIR"'/docker.service.d"
  ```

- [ ] **Step 5: Run tests to verify everything passes**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/docker_test.bats"`
Expected: all 30 tests PASS (29 prior + 1 new).

- [ ] **Step 6: Commit**

```bash
git add install/terminal/docker.sh tests/docker_test.bats
git commit -m "feat: wire docker daemon proxy autoconfig into omawsl_docker_engine"
```

---

### Task 5: Uninstall symmetry

**Files:**
- Modify: `uninstall/docker.sh:38-58` (the `omawsl_uninstall_docker` function)
- Test: `tests/uninstall_docker_test.bats`

**Interfaces:**
- Consumes: nothing new (just a file path convention matching Task 3/4's `$dir/omawsl-proxy.conf`).
- Produces: `omawsl_uninstall_docker` now accepts an optional 3rd positional arg `docker_service_d_dir` (default `/etc/systemd/system/docker.service.d`) and additionally removes `$docker_service_d_dir/omawsl-proxy.conf` alongside its existing apt-source/keyring cleanup.

- [ ] **Step 1: Write the failing test**

Add to `tests/uninstall_docker_test.bats`, after the existing "purges docker-ce..." test (after line 58):

```bash
@test "omawsl_uninstall_docker removes the proxy drop-in it created, in Engine mode" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Engine only, inside WSL (recommended)"
  stub_command docker
  local sources="$BATS_TEST_TMPDIR/docker.list"
  local keyrings="$BATS_TEST_TMPDIR/keyrings"
  local service_d="$BATS_TEST_TMPDIR/docker.service.d"
  touch "$sources"
  mkdir -p "$service_d"
  printf '[Service]\nEnvironment="HTTP_PROXY=http://x:8080"\n' > "$service_d/omawsl-proxy.conf"
  run omawsl_uninstall_docker "$sources" "$keyrings" "$service_d"
  [ "$status" -eq 0 ]
  [ ! -f "$service_d/omawsl-proxy.conf" ]
}

@test "omawsl_uninstall_docker no-ops cleanly when no proxy drop-in was ever created" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Engine only, inside WSL (recommended)"
  stub_command docker
  local sources="$BATS_TEST_TMPDIR/docker.list"
  local keyrings="$BATS_TEST_TMPDIR/keyrings"
  local service_d="$BATS_TEST_TMPDIR/docker.service.d-missing"
  touch "$sources"
  run omawsl_uninstall_docker "$sources" "$keyrings" "$service_d"
  [ "$status" -eq 0 ]
}
```

- [ ] **Step 2: Run tests to verify the first one fails**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/uninstall_docker_test.bats"`
Expected: "removes the proxy drop-in it created" FAILS (the file is still there, since nothing removes it yet); "no-ops cleanly..." PASSES already (nothing to remove); all 3 prior tests PASS.

- [ ] **Step 3: Implement the removal**

In `uninstall/docker.sh`, modify `omawsl_uninstall_docker` (lines 38-58):

```bash
# omawsl_uninstall_docker [apt_sources_file] [keyrings_dir] [docker_service_d_dir]
# Detect-and-defer's inverse: if OMAWSL_DOCKER_MODE (persisted in
# choices.env, design spec §6) was Docker Desktop, omawsl's docker.sh
# never installed docker-ce (design spec §9) - so there's genuinely
# nothing here for THIS repo to uninstall. Otherwise purges docker-ce and
# its apt source/keyring, same paths omawsl_install_docker_ce writes
# (install/terminal/docker.sh), and removes omawsl-proxy.conf - the one
# file omawsl_configure_docker_proxy might have created (design spec
# docs/superpowers/specs/2026-07-29-docker-daemon-proxy-autoconfig-design.md) -
# never anything else under docker_service_d_dir. Deliberately leaves the
# user's docker group membership in place rather than auto-revoking it -
# that's a broader system change than "undo what omawsl installed."
omawsl_uninstall_docker() {
  local apt_sources_file="${1:-/etc/apt/sources.list.d/docker.list}"
  local keyrings_dir="${2:-/etc/apt/keyrings}"
  local docker_service_d_dir="${3:-/etc/systemd/system/docker.service.d}"

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
  sudo rm -f "$apt_sources_file" "$keyrings_dir/docker.gpg" "$docker_service_d_dir/omawsl-proxy.conf"
  echo "omawsl: docker-ce removed. Your user's docker group membership was left in place - run 'sudo gpasswd -d \"\$USER\" docker' yourself if you want that removed too."
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/uninstall_docker_test.bats"`
Expected: all 5 tests PASS (3 prior + 2 new).

- [ ] **Step 5: Commit**

```bash
git add uninstall/docker.sh tests/uninstall_docker_test.bats
git commit -m "feat: remove docker daemon proxy drop-in on uninstall"
```

---

### Task 6: `doctor.sh` passive check

**Files:**
- Modify: `bin/omawsl-sub/doctor.sh:1-9` (source `docker.sh` for the helper functions), `bin/omawsl-sub/doctor.sh:95-117` (the `omawsl_doctor` function)
- Test: `tests/omawsl_doctor_test.bats`

**Interfaces:**
- Consumes: `omawsl_detect_proxy_env <VAR>` (Task 1), `omawsl_docker_proxy_conflict <dir> <own_file>` (Task 2).
- Produces: `omawsl_doctor_docker_proxy_pending [dir]` — returns 0 (true, "pending") only when Engine mode is active, a proxy is present in the environment, `$dir/omawsl-proxy.conf` doesn't exist, and no other file in `$dir` already provides one. `omawsl_doctor` prints a `[PENDING]` line under "Docker:" when this is true.

- [ ] **Step 1: Write the failing tests**

Add to `tests/omawsl_doctor_test.bats`, after the existing "flags a still-unreachable Docker Desktop selection" test (after line 64):

```bash
@test "omawsl_doctor flags a pending docker daemon proxy config in Engine mode" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Engine only, inside WSL (recommended)"
  export HTTP_PROXY="http://webproxy.example:8080"
  export OMAWSL_DOCKER_SERVICE_D_DIR="$BATS_TEST_TMPDIR/docker.service.d-missing"
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"[PENDING] Docker daemon proxy config"* ]]
  [[ "$output" == *"re-run install.sh"* ]]
}

@test "omawsl_doctor stays silent on docker proxy when already configured" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Engine only, inside WSL (recommended)"
  export HTTP_PROXY="http://webproxy.example:8080"
  local dir="$BATS_TEST_TMPDIR/docker.service.d-configured"
  mkdir -p "$dir"
  printf '[Service]\nEnvironment="HTTP_PROXY=http://webproxy.example:8080"\n' > "$dir/omawsl-proxy.conf"
  export OMAWSL_DOCKER_SERVICE_D_DIR="$dir"
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" != *"Docker daemon proxy config"* ]]
}

@test "omawsl_doctor stays silent on docker proxy when no proxy is set" {
  omawsl_save_choice OMAWSL_DOCKER_MODE "Docker Engine only, inside WSL (recommended)"
  unset HTTP_PROXY HTTPS_PROXY http_proxy https_proxy || true
  export OMAWSL_DOCKER_SERVICE_D_DIR="$BATS_TEST_TMPDIR/docker.service.d-noproxy"
  run omawsl_doctor
  [ "$status" -eq 0 ]
  [[ "$output" != *"Docker daemon proxy config"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/omawsl_doctor_test.bats"`
Expected: "flags a pending docker daemon proxy config" FAILS (no such output yet); the two "stays silent" tests PASS already (nothing prints); all 6 prior tests PASS.

- [ ] **Step 3: Source `docker.sh` and add the check function**

In `bin/omawsl-sub/doctor.sh`, add a source line after the existing `items.sh` source (after line 9):

```bash
# shellcheck source=../../install/terminal/docker.sh
source "$OMAWSL_ROOT_DIR/install/terminal/docker.sh"
```

Add this function after `omawsl_doctor_storage_installed` (after line 68):

```bash
# omawsl_doctor_docker_proxy_pending [dir]
# True if Engine mode is active, a proxy is present in the environment,
# and omawsl hasn't (yet) configured the daemon for it - either the
# choice was made before this feature existed, or the environment's
# proxy changed since the last install.sh run. False (silent) once
# configured, once no proxy is present, or once another file already
# provides one - mirrors omawsl_configure_docker_proxy's own back-off
# logic exactly (design spec
# docs/superpowers/specs/2026-07-29-docker-daemon-proxy-autoconfig-design.md),
# since doctor only ever reports, it never writes anything itself.
omawsl_doctor_docker_proxy_pending() {
  local dir="${1:-${OMAWSL_DOCKER_SERVICE_D_DIR:-/etc/systemd/system/docker.service.d}}"
  [[ "$(omawsl_load_choice OMAWSL_DOCKER_MODE)" == "Docker Desktop for Windows" ]] && return 1
  local http_proxy_val https_proxy_val
  http_proxy_val="$(omawsl_detect_proxy_env HTTP_PROXY)"
  https_proxy_val="$(omawsl_detect_proxy_env HTTPS_PROXY)"
  [[ -n "$http_proxy_val" || -n "$https_proxy_val" ]] || return 1
  [[ -f "$dir/omawsl-proxy.conf" ]] && return 1
  omawsl_docker_proxy_conflict "$dir" "$dir/omawsl-proxy.conf" && return 1
  return 0
}
```

Modify `omawsl_doctor` (lines 95-117) to add the new branch:

```bash
  if [[ "$(omawsl_load_choice OMAWSL_DOCKER_MODE)" == "Docker Desktop for Windows" ]] && ! omawsl_docker_reachable; then
    echo
    echo "Docker:"
    echo "  [PENDING] Docker Desktop for Windows - see docs/windows-setup.md#docker-desktop"
  elif omawsl_doctor_docker_proxy_pending; then
    echo
    echo "Docker:"
    echo "  [PENDING] Docker daemon proxy config - re-run install.sh to pick up your HTTP_PROXY/HTTPS_PROXY"
  fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/omawsl_doctor_test.bats"`
Expected: all 9 tests PASS (6 prior + 3 new).

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/doctor.sh tests/omawsl_doctor_test.bats
git commit -m "feat: doctor reports a pending docker daemon proxy config"
```

---

### Task 7: Narrow the corp-safe never-touch exception + docs

**Files:**
- Modify: `docs/config-safety.md:24-38` (the never-touch list)
- Modify: `tests/config_safety_test.bats` (narrow the `docker.service.d` check, add two pattern-scoped tests)

**Interfaces:** None - this task only affects documentation and a static regression test's grep pattern, no runtime code.

- [ ] **Step 1: Write the failing tests**

In `tests/config_safety_test.bats`, replace the whole file (the single existing `@test` needs its `forbidden` array to drop `docker\.service\.d` from the generic loop, since that path now needs its own narrower check):

```bash
#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# Best-effort static regression guard (design spec
# docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md):
# fails if any install/uninstall/migrations/bin script ever gains a
# write-operation pattern targeting one of the never-touch files. migrations/
# and bin/ are scanned too, not just install/uninstall - migrations/ in
# particular exists solely to write to files under $HOME, so it's exactly
# the kind of directory this guard needs to cover. Not exhaustive - a
# determined write in an unusual shape could slip past a literal-pattern
# grep - but cheap, root-free, and catches the common cases (cp, redirect,
# tee, cat >, append) the same way this project's other static
# doc-consistency tests do (tests/readme_test.bats).
@test "no install/uninstall/migrations/bin script writes to a never-touch corp-managed file" {
  local forbidden=(
    '\.zshrc'
    '/etc/zsh/zshenv'
    '\.oh-my-zsh'
    '\.curlrc'
    '/etc/apt/apt\.conf\.d'
    '/etc/profile\.d'
    '/etc/sudoers'
    '\.m2/settings\.xml'
    '\.git-templates'
    '\.config/direnv/direnvrc'
    'wsl-vpnkit\.service'
  )
  local pattern
  for pattern in "${forbidden[@]}"; do
    if grep -rnE "(cp |> |>> |tee |cat > )[^|]*(${pattern})" "$REPO_ROOT/install" "$REPO_ROOT/uninstall" "$REPO_ROOT/migrations" "$REPO_ROOT/bin" 2>/dev/null; then
      echo "found a write targeting a never-touch path matching: $pattern"
      return 1
    fi
  done
}

# docker.service.d/* is never-touch except omawsl's own exclusively-owned
# omawsl-proxy.conf (design spec
# docs/superpowers/specs/2026-07-29-docker-daemon-proxy-autoconfig-design.md):
# omawsl writes only that one distinctly-named file, never the conventional
# http-proxy.conf name a corp manual would use, and never at all if another
# file in that directory already configures a proxy. This checks the real
# codebase for a write to anything else under docker.service.d/.
@test "docker.service.d writes are limited to omawsl's own omawsl-proxy.conf" {
  local matches
  matches="$(grep -rnE "(cp |> |>> |tee |cat > )[^|]*docker\.service\.d" "$REPO_ROOT/install" "$REPO_ROOT/uninstall" "$REPO_ROOT/migrations" "$REPO_ROOT/bin" 2>/dev/null | grep -v 'omawsl-proxy\.conf' || true)"
  if [[ -n "$matches" ]]; then
    echo "found a write targeting docker.service.d/ that isn't omawsl-proxy.conf:"
    echo "$matches"
    return 1
  fi
}

# Proves the exception above is narrow in both directions, independent of
# whatever the real codebase currently contains: a fixture write to the
# conventional http-proxy.conf name must still be caught, while a fixture
# write to omawsl-proxy.conf must be allowed.
@test "docker.service.d exception: a write to http-proxy.conf would still be caught" {
  local fixture="$BATS_TEST_TMPDIR/fixture.sh"
  echo 'echo "content" | sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf' > "$fixture"
  run bash -c "grep -rnE '(cp |> |>> |tee |cat > )[^|]*docker\.service\.d' '$fixture' | grep -v 'omawsl-proxy\.conf'"
  [ -n "$output" ]
}

@test "docker.service.d exception: a write to omawsl-proxy.conf is allowed" {
  local fixture="$BATS_TEST_TMPDIR/fixture.sh"
  echo 'echo "content" | sudo tee /etc/systemd/system/docker.service.d/omawsl-proxy.conf' > "$fixture"
  run bash -c "grep -rnE '(cp |> |>> |tee |cat > )[^|]*docker\.service\.d' '$fixture' | grep -v 'omawsl-proxy\.conf'"
  [ -z "$output" ]
}
```

- [ ] **Step 2: Run tests to verify current state**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/config_safety_test.bats"`
Expected: all 4 tests PASS already at this point - Task 3/4/5's real code writes only to `omawsl-proxy.conf`, so the narrowed check has nothing to catch, and the two fixture-based tests exercise the grep pattern directly rather than the real repo tree. (This step confirms the rewritten test file is itself correct and non-regressive before moving on - there's no red/green cycle needed here since no forbidden write exists in the codebase to trigger a failure either before or after this task's doc change.)

- [ ] **Step 3: Update `docs/config-safety.md`**

In `docs/config-safety.md`, replace this line (currently line 35):

```markdown
- `/etc/systemd/system/docker.service.d/*`
```

with:

```markdown
- `/etc/systemd/system/docker.service.d/*` - except `omawsl-proxy.conf`, which omawsl
  exclusively creates, rewrites, and removes itself. It's never the conventional
  `http-proxy.conf` name a corp manual would use, and it's never written at all if another
  file in that directory already configures a proxy - see
  `docs/superpowers/specs/2026-07-29-docker-daemon-proxy-autoconfig-design.md`.
```

- [ ] **Step 4: Run the full test suite**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tuna/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/"`
Expected: every test file in the suite PASSES, including all of `docker_test.bats`, `uninstall_docker_test.bats`, `omawsl_doctor_test.bats`, and `config_safety_test.bats` from this plan's earlier tasks.

- [ ] **Step 5: Commit**

```bash
git add docs/config-safety.md tests/config_safety_test.bats
git commit -m "docs: narrow corp-safe never-touch exception for docker proxy drop-in"
```

---

## Self-Review Notes

- **Spec coverage:** every component in the design doc (detect/conflict/configure functions, `omawsl_docker_engine` wiring, uninstall symmetry, doctor check, config-safety exception + tests) has a corresponding task above.
- **Placeholder scan:** no TBD/TODO; every step has literal code, not a description of code.
- **Type/signature consistency:** `omawsl_detect_proxy_env` (Task 1) is called the same way in Task 3 and Task 6. `omawsl_docker_proxy_conflict` (Task 2) is called with the same `<dir> <own_file>` argument order in Task 3 and Task 6. `omawsl_configure_docker_proxy` (Task 3)'s single optional `[dir]` argument matches how Task 4 calls it (`"$docker_service_d_dir"`) and how its default resolves (`OMAWSL_DOCKER_SERVICE_D_DIR` env var, same name used in Task 6's doctor check for consistency). The managed filename `omawsl-proxy.conf` is identical across Tasks 3, 5, 6, and 7.
