# Corp-Safe Config Editing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop omawsl from ever overwriting pre-existing content in `~/.bashrc`/`~/.inputrc`, harden its one real `/etc/wsl.conf` collision point, and lock in (with docs + a regression test) that it never touches the other files a corporate WSL2 setup manual typically manages.

**Architecture:** omawsl's own shell config stays exactly where it already lives in the repo checkout (`configs/bashrc`, `configs/inputrc`) and is sourced directly from there — never copied. `~/.bashrc` gets at most one small, marker-guarded `source` line, added only if not already present; `~/.inputrc` is never written to at all, with `configs/bashrc` falling back to pointing `$INPUTRC` at omawsl's own file only when the user has none of their own. A new migration converts existing installs (which still have the old, fully-`cp`-overwritten files) to this model without discarding anything that isn't provably omawsl's own prior content.

**Tech Stack:** pure bash (no new dependencies), bats for tests — matching every existing file this plan touches.

## Global Constraints

- omawsl never writes its own content directly into a file it doesn't exclusively own; it touches a shared file only through the smallest possible, idempotent, content-checked addition (spec policy statement).
- Files omawsl fully owns (anything under the repo checkout, e.g. `configs/bashrc`, `configs/inputrc`) may be freely rewritten; nothing else may.
- No new runtime dependencies — every change here is pure bash, matching `install/lib.sh`'s own "kept dependency-free" rule.
- Tests stay root-free and network-free, following every existing `tests/*.bats` file's convention (`stub_init`, isolated `$HOME` under `$BATS_TEST_TMPDIR`, `stub_hide_command` for absent tools).
- Never touch (documented + tested in Task 5): `~/.zshrc`, `/etc/zsh/zshenv`, `~/.oh-my-zsh/**`, `~/.curlrc`, `/etc/apt/apt.conf.d/*`, `/etc/profile.d/*`, `/etc/sudoers*`, `~/.m2/settings.xml`, `~/.git-templates/**`, `~/.config/direnv/direnvrc`, `/etc/systemd/system/wsl-vpnkit.service`, `/etc/systemd/system/docker.service.d/*`.

---

### Task 1: `omawsl_ensure_bashrc_source_line` helper

**Files:**
- Modify: `install/lib.sh`
- Test: `tests/lib_test.bats`

**Interfaces:**
- Produces: `omawsl_ensure_bashrc_source_line <bashrc_file> <target_file>` — appends a marker-delimited guarded `source "<target_file>"` line to `<bashrc_file>`, only if the `# >>> omawsl >>>` marker isn't already present. Creates `<bashrc_file>` if it doesn't exist. Never modifies any other line in `<bashrc_file>`. No return value; always exits 0 on success. Used by Task 2 (`a-shell.sh`) and Task 4 (the migration script).

- [ ] **Step 1: Write the failing tests**

Add to `tests/lib_test.bats` (after the existing `omawsl_list_has` tests, matching the file's existing `setup()`/style):

```bash
@test "omawsl_ensure_bashrc_source_line: creates the file and appends the guarded source line when the file doesn't exist yet" {
  local bashrc="$BATS_TEST_TMPDIR/bashrc_missing"
  omawsl_ensure_bashrc_source_line "$bashrc" "$BATS_TEST_TMPDIR/configs/bashrc"
  [ -f "$bashrc" ]
  grep -qF '# >>> omawsl >>>' "$bashrc"
  grep -qF "[ -f \"$BATS_TEST_TMPDIR/configs/bashrc\" ] && source \"$BATS_TEST_TMPDIR/configs/bashrc\"" "$bashrc"
  grep -qF '# <<< omawsl <<<' "$bashrc"
}

@test "omawsl_ensure_bashrc_source_line: leaves pre-existing content untouched and appends after it" {
  local bashrc="$BATS_TEST_TMPDIR/bashrc_existing"
  printf 'export SOME_CORP_VAR=1\n' > "$bashrc"
  omawsl_ensure_bashrc_source_line "$bashrc" "$BATS_TEST_TMPDIR/configs/bashrc"
  grep -qF 'export SOME_CORP_VAR=1' "$bashrc"
  grep -qF '# >>> omawsl >>>' "$bashrc"
  [ "$(grep -c 'export SOME_CORP_VAR=1' "$bashrc")" -eq 1 ]
}

@test "omawsl_ensure_bashrc_source_line: re-running is idempotent, marker appears exactly once, hand-added lines survive" {
  local bashrc="$BATS_TEST_TMPDIR/bashrc_idempotent"
  omawsl_ensure_bashrc_source_line "$bashrc" "$BATS_TEST_TMPDIR/configs/bashrc"
  printf 'some line the user added by hand\n' >> "$bashrc"
  omawsl_ensure_bashrc_source_line "$bashrc" "$BATS_TEST_TMPDIR/configs/bashrc"
  [ "$(grep -c '# >>> omawsl >>>' "$bashrc")" -eq 1 ]
  grep -qF 'some line the user added by hand' "$bashrc"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/lib_test.bats`
Expected: FAIL — `omawsl_ensure_bashrc_source_line: command not found`

- [ ] **Step 3: Implement the helper**

Add to `install/lib.sh` (after `omawsl_remove_from_csv`, at the end of the file):

```bash

# omawsl_ensure_bashrc_source_line <bashrc_file> <target_file>
# Appends exactly one guarded, marker-delimited `source <target_file>` line
# to <bashrc_file>, only if not already present - the corp-safe config
# editing policy (design spec
# docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md):
# omawsl owns <target_file> outright (freely rewritten elsewhere) but adds
# at most one small, idempotent line to a file it doesn't own, never
# touching anything already there. Creates <bashrc_file> if missing.
omawsl_ensure_bashrc_source_line() {
  local bashrc_file="$1" target_file="$2"
  touch "$bashrc_file"
  if grep -qF '# >>> omawsl >>>' "$bashrc_file"; then
    return 0
  fi
  {
    printf '\n# >>> omawsl >>>\n'
    printf '[ -f "%s" ] && source "%s"\n' "$target_file" "$target_file"
    printf '# <<< omawsl <<<\n'
  } >> "$bashrc_file"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/lib_test.bats`
Expected: PASS (all tests, including the 3 new ones)

- [ ] **Step 5: Commit**

```bash
git add install/lib.sh tests/lib_test.bats
git commit -m "feat: add omawsl_ensure_bashrc_source_line helper for corp-safe config edits"
```

---

### Task 2: `.bashrc`/`.inputrc` — source line instead of overwrite

**Files:**
- Modify: `install/terminal/a-shell.sh`
- Modify: `configs/bashrc:31-33`
- Test: `tests/a_shell_test.bats`

**Interfaces:**
- Consumes: `omawsl_ensure_bashrc_source_line` from Task 1.
- Produces: `omawsl_install_shell_config` (unchanged name/signature) now adds the marker source line instead of copying; `configs/bashrc` (unchanged banner line at line 1, used by Task 4) no longer expects `~/.inputrc` to be an omawsl-authored copy.

- [ ] **Step 1: Write the failing tests**

Replace the two existing tests in `tests/a_shell_test.bats` (lines 24-39, `"copies bashrc and inputrc into HOME"` and `"re-running overwrites deterministically (idempotent)"`) with:

```bash
@test "adds a marker-guarded source line to ~/.bashrc, does not copy configs/bashrc's content in" {
  run bash "$REPO_ROOT/install/terminal/a-shell.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.bashrc" ]
  grep -qF '# >>> omawsl >>>' "$HOME/.bashrc"
  grep -qF "source \"$REPO_ROOT/configs/bashrc\"" "$HOME/.bashrc"
  ! diff -q "$HOME/.bashrc" "$REPO_ROOT/configs/bashrc" >/dev/null 2>&1
  [ ! -f "$HOME/.inputrc" ]
}

@test "re-running is idempotent and never touches pre-existing ~/.bashrc content" {
  printf 'export SOME_CORP_VAR=1\n' > "$HOME/.bashrc"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  echo "some line the user added by hand" >> "$HOME/.bashrc"
  run bash "$REPO_ROOT/install/terminal/a-shell.sh"
  [ "$status" -eq 0 ]
  grep -qF 'export SOME_CORP_VAR=1' "$HOME/.bashrc"
  grep -qF 'some line the user added by hand' "$HOME/.bashrc"
  [ "$(grep -c '# >>> omawsl >>>' "$HOME/.bashrc")" -eq 1 ]
}

@test "INPUTRC points at omawsl's own inputrc when the user has no ~/.inputrc" {
  export HOME="$BATS_TEST_TMPDIR/home_no_inputrc"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo "$INPUTRC"'
  [ "$status" -eq 0 ]
  [[ "$output" == "$REPO_ROOT/configs/inputrc" ]]
}

@test "a pre-existing ~/.inputrc is left untouched and INPUTRC is not overridden" {
  export HOME="$BATS_TEST_TMPDIR/home_own_inputrc"
  mkdir -p "$HOME"
  printf 'set editing-mode vi\n' > "$HOME/.inputrc"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'echo "$INPUTRC"'
  [ "$status" -eq 0 ]
  [[ "$output" != "$REPO_ROOT/configs/inputrc" ]]
  [[ "$(cat "$HOME/.inputrc")" == "set editing-mode vi" ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/a_shell_test.bats`
Expected: FAIL — `.bashrc` still gets fully `cp`-overwritten (no marker line, `diff` against `configs/bashrc` succeeds instead of failing), `.inputrc` still gets created.

- [ ] **Step 3: Update `install/terminal/a-shell.sh`**

Replace its full content with:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib.sh
source "$OMAWSL_REPO_ROOT/install/lib.sh"

# omawsl_install_shell_config
# Corp-safe config editing policy (design spec
# docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md):
# omawsl owns configs/bashrc/configs/inputrc outright in the repo checkout
# (freely updated by `omawsl update`'s git pull, no copy step needed) and
# adds at most one guarded source line to ~/.bashrc - never overwrites it,
# never touches ~/.inputrc at all.
omawsl_install_shell_config() {
  omawsl_ensure_bashrc_source_line "$HOME/.bashrc" "$OMAWSL_REPO_ROOT/configs/bashrc"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_shell_config
fi
```

- [ ] **Step 4: Update `configs/bashrc`'s `INPUTRC` block**

In `configs/bashrc`, replace lines 31-33:

```bash
if [ -f ~/.inputrc ]; then
  export INPUTRC=~/.inputrc
fi
```

with:

```bash
# Only points at omawsl's own inputrc when the user (or a corp policy) has
# no ~/.inputrc of their own - corp-safe config editing policy (design spec
# docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md).
# ${BASH_SOURCE[0]} here resolves to this file's own real path (baked in
# by a-shell.sh's source line), so this needs no separate path variable.
if [ -z "${INPUTRC:-}" ] && [ ! -f "$HOME/.inputrc" ]; then
  export INPUTRC="$(dirname "${BASH_SOURCE[0]}")/inputrc"
fi
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/a_shell_test.bats`
Expected: PASS (all tests — the 4 new/changed ones plus every pre-existing alias/prompt/zellij test, since those all still `source` `configs/bashrc` indirectly via the new marker line and are unaffected)

- [ ] **Step 6: Commit**

```bash
git add install/terminal/a-shell.sh configs/bashrc tests/a_shell_test.bats
git commit -m "fix: stop overwriting ~/.bashrc and ~/.inputrc, source omawsl's own config instead"
```

---

### Task 3: Harden `/etc/wsl.conf` idempotency check

**Files:**
- Modify: `install/terminal/docker.sh:102`
- Test: `tests/docker_test.bats`

**Interfaces:**
- No new interfaces; `omawsl_docker_engine`'s signature and behavior are unchanged except which pre-existing `wsl.conf` content it recognizes as "already satisfied."

- [ ] **Step 1: Write the failing test**

Add to `tests/docker_test.bats`, right after the existing `"engine mode: continues past systemd, installs docker, adds the user to the docker group, when systemd is already enabled"` test (around line 190):

```bash
@test "engine mode: recognizes systemd=true with surrounding whitespace as already enabled" {
  wsl_conf="$BATS_TEST_TMPDIR/wsl-whitespace.conf"
  printf '[boot]\n  systemd = true \n' > "$wsl_conf"

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
  [[ "$output" == *"REACHED_END"* ]]
  [[ "$output" != *"WSL systemd support was just enabled"* ]]
  [[ "$(stub_calls)" != *"sudo tee -a $wsl_conf"* ]]
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bats tests/docker_test.bats`
Expected: FAIL — `^systemd=true` doesn't match `  systemd = true `, so it re-appends and stops early instead of reaching `DOCKER_CE_INSTALLED`.

- [ ] **Step 3: Tighten the regex**

In `install/terminal/docker.sh:102`, change:

```bash
  if ! grep -q "^systemd=true" "$wsl_conf" 2>/dev/null; then
```

to:

```bash
  if ! grep -Eq '^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true[[:space:]]*$' "$wsl_conf" 2>/dev/null; then
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/docker_test.bats`
Expected: PASS (all tests, including the new one and both pre-existing systemd tests)

- [ ] **Step 5: Commit**

```bash
git add install/terminal/docker.sh tests/docker_test.bats
git commit -m "fix: recognize whitespace variants of systemd=true in /etc/wsl.conf"
```

---

### Task 4: Migration for existing installs

**Files:**
- Create: `migrations/1785266018.sh`
- Modify: `version`
- Test: `tests/migration_1785266018_test.bats`

**Interfaces:**
- Consumes: `omawsl_ensure_bashrc_source_line` from Task 1; the omawsl banner line at `configs/bashrc:1` (`# omawsl bashrc - baseline dev environment configuration for WSL2 Ubuntu.`) and `configs/inputrc:1` (`# omawsl inputrc - readline configuration for more usable bash history search.`) from Task 2 — unchanged by this task, used only as detection signatures.
- Produces: `migrations/1785266018.sh`, run automatically by `bin/omawsl migrate` (via the existing `omawsl_migrate` engine in `bin/omawsl-sub/migrate.sh` — no changes needed there, per `migrations/README.md`'s existing timestamp-comparison contract).

- [ ] **Step 1: Write the failing test**

Create `tests/migration_1785266018_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "converts an untouched old-style ~/.bashrc to the new source line, losing nothing" {
  printf '# omawsl bashrc - baseline dev environment configuration for WSL2 Ubuntu.\nsome old omawsl content\n' > "$HOME/.bashrc"
  run bash "$REPO_ROOT/migrations/1785266018.sh"
  [ "$status" -eq 0 ]
  ! grep -qF 'some old omawsl content' "$HOME/.bashrc"
  grep -qF '# >>> omawsl >>>' "$HOME/.bashrc"
  grep -qF "source \"$REPO_ROOT/configs/bashrc\"" "$HOME/.bashrc"
}

@test "leaves a hand-diverged ~/.bashrc alone and just appends the guarded source line" {
  printf 'export SOME_CORP_VAR=1\n' > "$HOME/.bashrc"
  run bash "$REPO_ROOT/migrations/1785266018.sh"
  [ "$status" -eq 0 ]
  grep -qF 'export SOME_CORP_VAR=1' "$HOME/.bashrc"
  grep -qF '# >>> omawsl >>>' "$HOME/.bashrc"
}

@test "no-ops cleanly when ~/.bashrc doesn't exist yet" {
  run bash "$REPO_ROOT/migrations/1785266018.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.bashrc" ]
  grep -qF '# >>> omawsl >>>' "$HOME/.bashrc"
}

@test "deletes an untouched old-style ~/.inputrc, leaving INPUTRC's new fallback to take over" {
  printf '# omawsl inputrc - readline configuration for more usable bash history search.\nset show-all-if-ambiguous on\n' > "$HOME/.inputrc"
  run bash "$REPO_ROOT/migrations/1785266018.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.inputrc" ]
}

@test "leaves a user's own non-omawsl ~/.inputrc completely untouched" {
  printf 'set editing-mode vi\n' > "$HOME/.inputrc"
  run bash "$REPO_ROOT/migrations/1785266018.sh"
  [ "$status" -eq 0 ]
  [ -f "$HOME/.inputrc" ]
  [[ "$(cat "$HOME/.inputrc")" == "set editing-mode vi" ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/migration_1785266018_test.bats`
Expected: FAIL — `migrations/1785266018.sh` doesn't exist yet.

- [ ] **Step 3: Write the migration script**

Create `migrations/1785266018.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"

# Corp-safe config editing migration (design spec
# docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md):
# every prior install/update `cp`-overwrote ~/.bashrc and ~/.inputrc
# wholesale, so a file starting with omawsl's own banner comment is
# entirely omawsl-authored content - safe to replace with the new
# marker-guarded source line/INPUTRC fallback. A file that doesn't start
# with that banner was never omawsl's; left untouched except for the same
# guarded append a fresh install would do.
omawsl_migrate_bashrc_to_source_line() {
  local bashrc="$HOME/.bashrc"
  if [[ -f "$bashrc" ]] && head -n1 "$bashrc" | grep -qF '# omawsl bashrc - baseline dev environment configuration for WSL2 Ubuntu.'; then
    rm -f "$bashrc"
  fi
  omawsl_ensure_bashrc_source_line "$bashrc" "$OMAWSL_ROOT_DIR/configs/bashrc"
}

omawsl_migrate_inputrc_removal() {
  local inputrc="$HOME/.inputrc"
  if [[ -f "$inputrc" ]] && head -n1 "$inputrc" | grep -qF '# omawsl inputrc - readline configuration for more usable bash history search.'; then
    rm -f "$inputrc"
  fi
}

omawsl_migrate_bashrc_to_source_line
omawsl_migrate_inputrc_removal
```

- [ ] **Step 4: Bump the repo version file**

`migrations/README.md`'s timestamp-comparison contract expects the repo's own `version` file to be at or past the latest migration's timestamp (`bin/omawsl-sub/migrate.sh`'s `omawsl_migrate` bumps recorded state to `version`'s content after running pending migrations — keeping it in sync avoids a fresh install's baseline state treating this migration as spuriously pending). Replace `version`'s content:

```
1785266018
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `bats tests/migration_1785266018_test.bats tests/omawsl_migrate_test.bats`
Expected: PASS (the new migration tests, and the pre-existing migration-engine tests remain unaffected since they use their own fixture migration files via `OMAWSL_MIGRATIONS_DIR`)

- [ ] **Step 6: Commit**

```bash
git add migrations/1785266018.sh version tests/migration_1785266018_test.bats
git commit -m "feat: migrate existing installs' .bashrc/.inputrc to the source-line model"
```

---

### Task 5: Never-touch policy — docs + regression tests

**Files:**
- Create: `docs/config-safety.md`
- Test: `tests/docs_config_safety_test.bats`
- Test: `tests/config_safety_test.bats`

**Interfaces:**
- None — this task is documentation plus two static-check test files, no shared functions.

- [ ] **Step 1: Write the failing tests**

Create `tests/docs_config_safety_test.bats`:

```bash
#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DOC="$REPO_ROOT/docs/config-safety.md"

@test "docs/config-safety.md exists" {
  [ -f "$DOC" ]
}

@test "docs/config-safety.md states the core policy" {
  grep -qF "omawsl never writes its own content directly into a file it doesn't exclusively own" "$DOC"
}

@test "docs/config-safety.md lists every never-touch file" {
  for path in '~/.zshrc' '/etc/zsh/zshenv' '~/.oh-my-zsh' '~/.curlrc' '/etc/apt/apt.conf.d' '/etc/profile.d' '/etc/sudoers' '~/.m2/settings.xml' '~/.git-templates' '~/.config/direnv/direnvrc' '/etc/systemd/system/wsl-vpnkit.service' '/etc/systemd/system/docker.service.d'; do
    grep -qF "$path" "$DOC" || { echo "missing never-touch entry: $path"; return 1; }
  done
}
```

Create `tests/config_safety_test.bats`:

```bash
#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# Best-effort static regression guard (design spec
# docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md):
# fails if any install/uninstall script ever gains a write-operation
# pattern targeting one of the never-touch files. Not exhaustive - a
# determined write in an unusual shape could slip past a literal-pattern
# grep - but cheap, root-free, and catches the common cases (cp, redirect,
# tee, cat >, append) the same way this project's other static
# doc-consistency tests do (tests/readme_test.bats).
@test "no install/uninstall script writes to a never-touch corp-managed file" {
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
    'docker\.service\.d'
  )
  local pattern
  for pattern in "${forbidden[@]}"; do
    if grep -rnE "(cp |> |>> |tee |cat > )[^|]*(${pattern})" "$REPO_ROOT/install" "$REPO_ROOT/uninstall" 2>/dev/null; then
      echo "found a write targeting a never-touch path matching: $pattern"
      return 1
    fi
  done
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bats tests/docs_config_safety_test.bats tests/config_safety_test.bats`
Expected: `docs_config_safety_test.bats` FAILs (`docs/config-safety.md` doesn't exist yet); `config_safety_test.bats` PASSes trivially (nothing to find yet, but written first per TDD so it's proven not to false-positive on the current tree before relying on it going forward).

- [ ] **Step 3: Write `docs/config-safety.md`**

```markdown
# Config safety

omawsl runs on machines that are often also managed by a company-specific
WSL2 setup manual - proxy settings, corporate DNS, VPN/mirrored-networking
config, internal Maven/npm mirrors, and more, spread across a fixed list of
files. That list varies from company to company, so omawsl can't special-case
any one of them. Instead it follows one rule, everywhere:

> omawsl never writes its own content directly into a file it doesn't
> exclusively own. Content omawsl needs to provide lives in files under its
> own tree (the repo checkout at `$OMAWSL_HOME`, default
> `~/.local/share/omawsl`) and is freely rewritten there - omawsl is the sole
> owner. Touching a shared file happens only through the smallest possible,
> idempotent, content-checked addition: the format's own drop-in mechanism if
> one exists (`/etc/profile.d/*`, `/etc/apt/apt.conf.d/*`, `/etc/sudoers.d/*`,
> a systemd `*.conf.d/` override directory), a single guarded include/source
> line added only if not already present, or - only for formats with
> neither, like `/etc/wsl.conf` - a content-based check-then-append.

## What this looks like in practice

- `~/.bashrc` gets at most one guarded `source` line pointing at omawsl's own
  `configs/bashrc` in the repo checkout, added only if not already present.
  Everything else already in `~/.bashrc` - corp additions, hand edits - is
  left exactly as-is.
- `~/.inputrc` is never written by omawsl at all. `configs/bashrc` only
  points `$INPUTRC` at omawsl's own copy when the user has no `~/.inputrc`
  of their own.
- `/etc/wsl.conf`'s `[boot] systemd=true` line (needed for Docker Engine
  mode) is appended only if not already present, tolerant of whitespace
  variants - a no-op if a corp manual (or you, by hand) already set it.

## Files omawsl never creates or modifies

- `~/.zshrc`, `/etc/zsh/zshenv`, `~/.oh-my-zsh/**` - omawsl ships bash only.
- `~/.curlrc`
- `/etc/apt/apt.conf.d/*`
- `/etc/profile.d/*`
- `/etc/sudoers*`
- `~/.m2/settings.xml`
- `~/.git-templates/**`
- `~/.config/direnv/direnvrc`
- `/etc/systemd/system/wsl-vpnkit.service`
- `/etc/systemd/system/docker.service.d/*`

Enforced by `tests/config_safety_test.bats`, a static regression guard that
fails the suite if a future change ever adds a write to one of these paths.
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bats tests/docs_config_safety_test.bats tests/config_safety_test.bats`
Expected: PASS (all tests)

- [ ] **Step 5: Run the full suite**

Run: `bats tests/`
Expected: PASS (every test file, confirming nothing else in the repo regressed)

- [ ] **Step 6: Commit**

```bash
git add docs/config-safety.md tests/docs_config_safety_test.bats tests/config_safety_test.bats
git commit -m "docs: add config-safety policy doc and never-touch regression test"
```

---

## Self-Review Notes

- **Spec coverage:** Policy statement → Task 5's doc. `.bashrc`/`.inputrc` mechanism → Task 2. Migration → Task 4. `wsl.conf` hardening → Task 3. Never-touch list + test → Task 5. Every design-doc component maps to a task.
- **Placeholder scan:** none - every step has real, runnable code.
- **Type/interface consistency:** `omawsl_ensure_bashrc_source_line(bashrc_file, target_file)` defined in Task 1 is called identically (same argument order) in Task 2 and Task 4. The omawsl banner-line detection strings in Task 4 match `configs/bashrc:1`/`configs/inputrc:1` verbatim (unchanged by Task 2). The never-touch file list is identical across Global Constraints, `docs/config-safety.md` (Task 5), and `tests/config_safety_test.bats` (Task 5).
