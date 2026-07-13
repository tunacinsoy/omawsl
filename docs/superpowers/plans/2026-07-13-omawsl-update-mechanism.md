# omawsl Update Mechanism Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `bin/omawsl update` to cover the 7 "orphan" tools that have no native updater of their own (zellij, lazydocker, opencode, Claude Code CLI, Codex CLI, Gemini CLI, GitHub Copilot CLI), via a two-phase version-check + `gum choose` picker, and document the full apt/mise/omawsl three-... four-way split in a new `docs/updating.md`.

**Architecture:** A new `bin/omawsl-sub/orphan-tools.sh` holds the orphan-tool registry (slugs/labels/installed-check), version-check adapters (GitHub Releases API for binary-download tools, npm registry for the two mise-exec'd npm globals), and the two-phase picker/apply orchestration - kept separate from `bin/omawsl-sub/items.sh` (the install/uninstall/doctor picker registry) since zellij/lazydocker are always-on, not picker targets. Each of the 7 existing `install/terminal/app-*.sh` (and `apps-terminal.sh`'s zellij/lazydocker) install functions is split into a guarded `_ensure_installed` entry point (unchanged behavior) and an unguarded `_install_steps` function, so `update` can force a fresh install/update without touching normal `install.sh` behavior. `bin/omawsl-sub/update.sh` gains one new call after its existing self-update + migrate steps.

**Tech Stack:** Bash (`set -euo pipefail`), `gum choose --no-limit --selected` (existing pre-selection convention from `bin/omawsl-sub/install.sh`), `curl` + `jq` (both already always-on dependencies per `apps-terminal.sh`) for GitHub Releases API lookups, `mise exec node@lts -- npm view` for the two npm-distributed tools, `gh extension list`/`gh extension upgrade` for GitHub Copilot CLI, bats-core for tests (`tests/helpers/stubs.bash`).

## Global Constraints

- Every new/modified script starts with `#!/usr/bin/env bash` + `set -euo pipefail`, matching every existing script in this repo.
- Comma-delimited list membership always goes through `omawsl_list_has` (`install/lib.sh`) — never a bare substring/`==` check.
- `omawsl update` never wraps `apt upgrade` or `mise upgrade` (design spec §2, and the original project design spec's own "Division of responsibility" constraint) — it owns exactly the 7 orphan tools in spec §3, nothing else.
- Every version-check network call (GitHub Releases API, npm registry) must degrade to an empty/`"unknown"` result on failure or timeout — never block the rest of the run, never abort under `set -e`.
- Do **not** use the external `timeout` command to bound any network call that goes through this repo's own bash-function command stubbing (`curl`, `mise`) — `timeout cmd` execs `cmd` directly via the real binary lookup, bypassing bash's function table entirely, so `export -f`-based stubs (`tests/helpers/stubs.bash`) become invisible to it. Bound timing at the background-job (`&`/`wait`/`kill`) level instead (Task 3).
- Every new `_install_steps`/`_update_steps` function must be callable standalone (no dependency on its sibling `_ensure_installed` guard already having run) — `omawsl update`'s apply phase calls these directly, bypassing the guard.
- One tool's failed update must not abort any other selected tool's update, or the rest of `omawsl update` — same `{ ... } || ok=0` isolation idiom as `install/terminal/cloud-tools.sh`.
- **Never run git commands through `wsl.exe`** — this repo lives on the Windows filesystem; only plain Windows-native `git` is safe here. `wsl.exe` is only for running bash scripts/bats tests.
- **Do NOT run `git clean` for any reason** inside any worktree used for this work — a stray `git clean` deleted an untracked plan file mid-phase once already (Phase 5).
- Source of truth: `docs/superpowers/specs/2026-07-13-omawsl-update-mechanism-design.md`. Section references (`§N`) below point there.

---

## File structure for this feature

```
bin/
├── omawsl-sub/
│   ├── orphan-tools.sh          # NEW - registry, version adapters, picker/apply orchestration (Tasks 1,2,3,8,9)
│   └── update.sh                # extend - call orphan-tools update after migrate (Task 9)
install/terminal/
├── apps-terminal.sh              # split zellij/lazydocker (Task 4)
├── app-opencode.sh                # split (Task 5)
├── app-claude-cli.sh              # split (Task 5)
├── app-codex-cli.sh               # split (Task 6)
├── app-gemini-cli.sh              # split (Task 6)
└── app-gh-copilot.sh              # split + distinct update_steps (Task 7)
docs/
├── updating.md                    # NEW (Task 10)
README.md                          # link to docs/updating.md (Task 10)
tests/
├── omawsl_orphan_tools_test.bats  # NEW (Tasks 1,2,3,8,9)
├── omawsl_update_test.bats        # extended (Task 9)
├── docs_updating_test.bats        # NEW (Task 10)
├── readme_test.bats               # extended (Task 10)
├── apps_terminal_test.bats        # extended (Task 4)
├── app_opencode_test.bats         # extended (Task 5)
├── app_claude_cli_test.bats       # extended (Task 5)
├── app_codex_cli_test.bats        # extended (Task 6)
├── app_gemini_cli_test.bats       # extended (Task 6)
└── app_gh_copilot_test.bats       # extended (Task 7)
```

---

### Task 1: Orphan-tool registry (slugs, labels, installed-check)

**Files:**
- Create: `bin/omawsl-sub/orphan-tools.sh`
- Test: `tests/omawsl_orphan_tools_test.bats`

**Interfaces:**
- Consumes: `omawsl_item_label` (`bin/omawsl-sub/items.sh`, existing).
- Produces: `omawsl_orphan_tool_slugs` (no args, prints 7 slugs one per line), `omawsl_orphan_tool_label <slug>` (prints label or returns 1), `omawsl_orphan_tool_installed <slug>` (return 0/1).

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/omawsl_orphan_tools_test.bats <<'EOF'
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/items.sh"
  source "$REPO_ROOT/bin/omawsl-sub/orphan-tools.sh"
}

@test "omawsl_orphan_tool_slugs lists all 7 orphan tools" {
  run omawsl_orphan_tool_slugs
  [ "$status" -eq 0 ]
  [[ "$output" == *"zellij"* ]]
  [[ "$output" == *"lazydocker"* ]]
  [[ "$output" == *"opencode"* ]]
  [[ "$output" == *"claude"* ]]
  [[ "$output" == *"codex"* ]]
  [[ "$output" == *"gemini"* ]]
  [[ "$output" == *"gh-copilot"* ]]
  [ "$(omawsl_orphan_tool_slugs | wc -l)" -eq 7 ]
}

@test "omawsl_orphan_tool_label returns Zellij/LazyDocker directly and reuses items.sh for the rest" {
  [ "$(omawsl_orphan_tool_label zellij)" = "Zellij" ]
  [ "$(omawsl_orphan_tool_label lazydocker)" = "LazyDocker" ]
  [ "$(omawsl_orphan_tool_label codex)" = "$(omawsl_item_label codex)" ]
  [ "$(omawsl_orphan_tool_label gh-copilot)" = "GitHub Copilot CLI" ]
}

@test "omawsl_orphan_tool_label fails for an unknown slug" {
  run omawsl_orphan_tool_label nonsense
  [ "$status" -ne 0 ]
}

@test "omawsl_orphan_tool_installed checks zellij/lazydocker via command -v" {
  stub_hide_command zellij lazydocker
  run omawsl_orphan_tool_installed zellij
  [ "$status" -ne 0 ]
  stub_command zellij
  run omawsl_orphan_tool_installed zellij
  [ "$status" -eq 0 ]
}

@test "omawsl_orphan_tool_installed checks gh-copilot via gh extension list" {
  stub_command gh
  run omawsl_orphan_tool_installed gh-copilot
  [ "$status" -ne 0 ]
}
EOF
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_orphan_tools_test.bats"`
Expected: FAIL — `bin/omawsl-sub/orphan-tools.sh` does not exist yet (source error).

- [ ] **Step 3: Write minimal implementation**

```bash
cat > bin/omawsl-sub/orphan-tools.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=items.sh
source "$SCRIPT_DIR/items.sh"

# Registry + version-check adapters for omawsl's "orphan" tools - tools
# omawsl installs that have no native update command of their own (no
# apt/mise coverage), per
# docs/superpowers/specs/2026-07-13-omawsl-update-mechanism-design.md §3.
# Deliberately separate from items.sh: items.sh is the install/uninstall/
# doctor picker registry (language/editor/storage categories only);
# zellij and lazydocker are always-on, not picker targets, so they don't
# belong there.

# omawsl_orphan_tool_slugs
# All 7 orphan-tool slugs, in a fixed display order.
omawsl_orphan_tool_slugs() {
  printf '%s\n' zellij lazydocker opencode claude codex gemini gh-copilot
}

# omawsl_orphan_tool_label <slug>
# zellij/lazydocker aren't in items.sh (always-on, not a picker target),
# so they get their own labels here; the other 5 slugs are already
# registered there under the exact same slug names install/uninstall/
# doctor use - reused via omawsl_item_label rather than duplicating the
# same 5 label strings a second time.
omawsl_orphan_tool_label() {
  case "$1" in
    zellij) echo "Zellij" ;;
    lazydocker) echo "LazyDocker" ;;
    opencode|claude|codex|gemini|gh-copilot) omawsl_item_label "$1" ;;
    *) return 1 ;;
  esac
}

# omawsl_orphan_tool_installed <slug>
# Is this orphan tool actually present right now? zellij/lazydocker get a
# direct command -v check (they're not in items.sh, so
# bin/omawsl-sub/doctor.sh's own per-slug checks don't cover them
# either); the other 5 repeat the same one-line checks doctor.sh and
# each tool's own install-script guard already use - this repo already
# has that exact check duplicated in at least two places per tool
# (app-codex-cli.sh's own guard, doctor.sh's omawsl_doctor_editor_installed),
# so a third one-line copy here matches existing precedent rather than
# reaching across into doctor.sh's file for a shared helper.
omawsl_orphan_tool_installed() {
  local slug="$1"
  case "$slug" in
    zellij) command -v zellij &>/dev/null ;;
    lazydocker) command -v lazydocker &>/dev/null ;;
    opencode) command -v opencode &>/dev/null ;;
    claude) command -v claude &>/dev/null ;;
    codex) command -v codex &>/dev/null ;;
    gemini) command -v gemini &>/dev/null ;;
    gh-copilot) gh extension list 2>/dev/null | grep -q 'github/gh-copilot' ;;
    *) return 1 ;;
  esac
}
EOF
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_orphan_tools_test.bats"`
Expected: PASS (5 tests)

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/orphan-tools.sh tests/omawsl_orphan_tools_test.bats
git commit -m "feat: add orphan-tool registry for the update mechanism"
```

---

### Task 2: Version-check adapters (installed + latest, per tool)

**Files:**
- Modify: `bin/omawsl-sub/orphan-tools.sh`
- Test: `tests/omawsl_orphan_tools_test.bats`

**Interfaces:**
- Consumes: nothing new from other tasks.
- Produces: `omawsl_orphan_extract_semver <text>`, `omawsl_orphan_latest_from_github <owner/repo>`, `omawsl_orphan_latest_from_npm <package>`, `omawsl_orphan_tool_version_installed <slug>`, `omawsl_orphan_tool_version_latest <slug>` — all used by Task 3's parallel runner and Task 9's orchestration.

- [ ] **Step 1: Write the failing test**

```bash
cat >> tests/omawsl_orphan_tools_test.bats <<'EOF'

@test "omawsl_orphan_extract_semver pulls the first X.Y.Z token out of arbitrary text" {
  [ "$(omawsl_orphan_extract_semver "zellij 0.44.3")" = "0.44.3" ]
  [ "$(omawsl_orphan_extract_semver $'Version: 0.25.2\nGit commit: abc123')" = "0.25.2" ]
  [ "$(omawsl_orphan_extract_semver "2.1.207 (Claude Code)")" = "2.1.207" ]
  [ "$(omawsl_orphan_extract_semver "")" = "" ]
}

@test "omawsl_orphan_latest_from_github strips a leading v from the release tag" {
  curl() { echo '{"tag_name":"v0.44.3"}'; }
  export -f curl
  [ "$(omawsl_orphan_latest_from_github zellij-org/zellij)" = "0.44.3" ]
}

@test "omawsl_orphan_latest_from_github returns empty on a curl failure" {
  curl() { return 1; }
  export -f curl
  [ "$(omawsl_orphan_latest_from_github zellij-org/zellij)" = "" ]
}

@test "omawsl_orphan_latest_from_github returns empty on malformed JSON" {
  curl() { echo 'not json'; }
  export -f curl
  [ "$(omawsl_orphan_latest_from_github zellij-org/zellij)" = "" ]
}

@test "omawsl_orphan_latest_from_npm uses the private mise Node runtime, not a bare npm" {
  stub_command mise
  omawsl_orphan_latest_from_npm "@openai/codex"
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm view @openai/codex version"* ]]
}

@test "omawsl_orphan_tool_version_installed dispatches per tool" {
  zellij() { echo "zellij 0.44.3"; }
  export -f zellij
  [ "$(omawsl_orphan_tool_version_installed zellij)" = "0.44.3" ]
}

@test "omawsl_orphan_tool_version_latest dispatches to github for binary-release tools and npm for the two npm globals" {
  curl() { echo '{"tag_name":"v9.9.9"}'; }
  export -f curl
  [ "$(omawsl_orphan_tool_version_latest zellij)" = "9.9.9" ]
  [ "$(omawsl_orphan_tool_version_latest claude)" = "9.9.9" ]

  stub_command mise
  gum_stub_init 2>/dev/null || true
  mise() { echo "8.8.8"; }
  export -f mise
  [ "$(omawsl_orphan_tool_version_latest codex)" = "8.8.8" ]
  [ "$(omawsl_orphan_tool_version_latest gemini)" = "8.8.8" ]
}
EOF
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_orphan_tools_test.bats"`
Expected: FAIL — the new `omawsl_orphan_*` functions don't exist yet.

- [ ] **Step 3: Write minimal implementation**

Append to `bin/omawsl-sub/orphan-tools.sh` (before the final `if [[ "${BASH_SOURCE[0]}"...` guard, if one existed — this file has none yet, so just append at the end):

```bash
cat >> bin/omawsl-sub/orphan-tools.sh <<'EOF'

# omawsl_orphan_extract_semver <text>
# Pulls the first X.Y.Z-shaped token out of arbitrary command output -
# shared by every "installed version" check below, since each tool's own
# --version output format differs (single line vs. multi-line, with or
# without a leading tool name) but all of them contain a plain semver
# token somewhere in the output. The trailing `|| true` matters: under
# this file's own `set -euo pipefail`, a `grep` with no match exits 1,
# and pipefail propagates that through `| head -n1` even though head
# itself "succeeds" - which would abort any caller capturing this via
# `result="$(...)"` for the common case of a tool that isn't installed
# at all. Found by task review during implementation (Task 2).
omawsl_orphan_extract_semver() {
  grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<< "$1" | head -n1 || true
}

# omawsl_orphan_latest_from_github <owner/repo>
# Latest release tag from the public GitHub REST API, unauthenticated -
# this must work on a fresh machine before any `gh auth login` has
# happened (the exact same real constraint already documented for
# gh-copilot's own install in app-gh-copilot.sh). Empty output on any
# failure (network, rate limit, malformed JSON) rather than erroring -
# the caller (Task 3) is what bounds the wait, not this function itself.
omawsl_orphan_latest_from_github() {
  local repo="$1"
  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null)" || tag=""
  echo "${tag#v}"
}

# omawsl_orphan_latest_from_npm <package>
# Latest published version from the npm registry, via the same private
# mise-managed Node runtime app-codex-cli.sh/app-gemini-cli.sh already
# use to install these two tools (`mise exec node@lts`) - never a bare
# `npm`, which isn't guaranteed on PATH at all (design spec §5).
omawsl_orphan_latest_from_npm() {
  local package="$1"
  mise exec node@lts -- npm view "$package" version 2>/dev/null || echo ""
}

# omawsl_orphan_tool_version_installed <slug>
omawsl_orphan_tool_version_installed() {
  local slug="$1"
  case "$slug" in
    zellij) omawsl_orphan_extract_semver "$(zellij --version 2>/dev/null || true)" ;;
    lazydocker) omawsl_orphan_extract_semver "$(lazydocker --version 2>/dev/null || true)" ;;
    opencode) omawsl_orphan_extract_semver "$(opencode --version 2>/dev/null || true)" ;;
    claude) omawsl_orphan_extract_semver "$(claude --version 2>/dev/null || true)" ;;
    codex) omawsl_orphan_extract_semver "$(codex --version 2>/dev/null || true)" ;;
    gemini) omawsl_orphan_extract_semver "$(gemini --version 2>/dev/null || true)" ;;
    gh-copilot) omawsl_orphan_extract_semver "$(gh extension list 2>/dev/null | grep 'github/gh-copilot' || true)" ;;
  esac
}

# omawsl_orphan_tool_version_latest <slug>
# GitHub Releases API for the 5 binary/curl-script-distributed tools
# (repo slugs confirmed live: zellij-org/zellij, jesseduffield/lazydocker,
# anomalyco/opencode [formerly sst/opencode - GitHub redirects the old
# path], anthropics/claude-code, github/gh-copilot); npm registry for the
# 2 tools installed via a private mise-managed Node runtime.
omawsl_orphan_tool_version_latest() {
  local slug="$1"
  case "$slug" in
    zellij) omawsl_orphan_latest_from_github zellij-org/zellij ;;
    lazydocker) omawsl_orphan_latest_from_github jesseduffield/lazydocker ;;
    opencode) omawsl_orphan_latest_from_github anomalyco/opencode ;;
    claude) omawsl_orphan_latest_from_github anthropics/claude-code ;;
    codex) omawsl_orphan_latest_from_npm "@openai/codex" ;;
    gemini) omawsl_orphan_latest_from_npm "@google/gemini-cli" ;;
    gh-copilot) omawsl_orphan_latest_from_github github/gh-copilot ;;
  esac
}
EOF
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_orphan_tools_test.bats"`
Expected: PASS (12 tests)

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/orphan-tools.sh tests/omawsl_orphan_tools_test.bats
git commit -m "feat: add version-check adapters for orphan tools"
```

---

### Task 3: Bounded-wait timeout helper + parallel version-check runner

**Files:**
- Modify: `bin/omawsl-sub/orphan-tools.sh`
- Test: `tests/omawsl_orphan_tools_test.bats`

**Interfaces:**
- Consumes: `omawsl_orphan_tool_version_installed`, `omawsl_orphan_tool_version_latest` (Task 2).
- Produces: `omawsl_orphan_wait_with_timeout <pid> <limit_seconds>` (returns 0 if the process exited on its own, 1 if it had to be killed), `omawsl_orphan_tools_check_versions <tmp_dir> <timeout_seconds> <slug...>` (writes `<tmp_dir>/<slug>.result` as `installed<TAB>latest` for every given slug, blocking until every job settles or times out) — both consumed by Task 9's orchestration.

- [ ] **Step 1: Write the failing test**

```bash
cat >> tests/omawsl_orphan_tools_test.bats <<'EOF'

@test "omawsl_orphan_wait_with_timeout returns 0 for a process that exits on its own" {
  sleep 0.2 &
  run omawsl_orphan_wait_with_timeout "$!" 5
  [ "$status" -eq 0 ]
}

@test "omawsl_orphan_wait_with_timeout kills and returns 1 for a process that outlives the limit" {
  sleep 30 &
  local pid=$!
  run omawsl_orphan_wait_with_timeout "$pid" 1
  [ "$status" -eq 1 ]
  ! kill -0 "$pid" 2>/dev/null
}

@test "omawsl_orphan_tools_check_versions writes one result file per slug in parallel" {
  zellij() { echo "zellij 1.2.3"; }
  export -f zellij
  lazydocker() { echo "Version: 4.5.6"; }
  export -f lazydocker
  curl() { echo '{"tag_name":"v9.9.9"}'; }
  export -f curl

  local tmp_dir="$BATS_TEST_TMPDIR/results"
  mkdir -p "$tmp_dir"
  omawsl_orphan_tools_check_versions "$tmp_dir" 5 zellij lazydocker
  [ "$(cat "$tmp_dir/zellij.result")" = "$(printf '1.2.3\t9.9.9')" ]
  [ "$(cat "$tmp_dir/lazydocker.result")" = "$(printf '4.5.6\t9.9.9')" ]
}

@test "omawsl_orphan_tools_check_versions falls back to empty/empty when a job times out" {
  omawsl_orphan_tool_version_latest() { sleep 30; echo "9.9.9"; }
  export -f omawsl_orphan_tool_version_latest

  local tmp_dir="$BATS_TEST_TMPDIR/results-timeout"
  mkdir -p "$tmp_dir"
  omawsl_orphan_tools_check_versions "$tmp_dir" 1 zellij
  [ "$(cat "$tmp_dir/zellij.result")" = "$(printf '\t')" ]
}
EOF
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_orphan_tools_test.bats"`
Expected: FAIL — `omawsl_orphan_wait_with_timeout`/`omawsl_orphan_tools_check_versions` don't exist yet.

- [ ] **Step 3: Write minimal implementation**

```bash
cat >> bin/omawsl-sub/orphan-tools.sh <<'EOF'

# omawsl_orphan_wait_with_timeout <pid> <limit_seconds>
# Polls a background pid every 0.1s, killing it once <limit_seconds> has
# elapsed. Deliberately a poll loop, not the external `timeout` command:
# `timeout cmd` execs `cmd` directly via a real binary lookup, invisible
# to this repo's export -f-based command stubbing (tests/helpers/stubs.bash)
# - a stubbed `curl` bash function would never be seen by a real `timeout`
# process. Returns 0 if the process exited on its own before the
# deadline, 1 if it had to be killed (caller treats that result as
# unknown/empty).
omawsl_orphan_wait_with_timeout() {
  local pid="$1" limit="$2"
  local waited=0 max_iterations=$((limit * 10))
  while kill -0 "$pid" 2>/dev/null; do
    if (( waited >= max_iterations )); then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 0.1
    ((waited++))
  done
  wait "$pid" 2>/dev/null || true
  return 0
}

# omawsl_orphan_tools_check_versions <tmp_dir> <timeout_seconds> <slug...>
# Launches one background job per slug - each resolving both the
# installed and latest version and writing "installed<TAB>latest" to
# <tmp_dir>/<slug>.result - so the network-bound "latest" lookups run in
# parallel rather than one after another. Blocks until every job has
# either finished or been killed by omawsl_orphan_wait_with_timeout, so
# the total wait is bounded by the single slowest per-tool timeout, not
# the sum of every tool's timeout. A killed job leaves no result file
# behind (its own subshell never reached the `printf`), so this function
# backfills an empty/empty result for it - a wholesale timeout (as
# opposed to just the network half being slow) is rare enough that
# falling back to "everything unknown" for that one tool is an
# acceptable, clearly-labeled degradation.
omawsl_orphan_tools_check_versions() {
  local tmp_dir="$1" timeout_seconds="$2"; shift 2
  local slugs=("$@")
  local slug
  local pids=()
  for slug in "${slugs[@]}"; do
    (
      local installed latest
      installed="$(omawsl_orphan_tool_version_installed "$slug" 2>/dev/null || true)"
      latest="$(omawsl_orphan_tool_version_latest "$slug" 2>/dev/null || true)"
      printf '%s\t%s\n' "$installed" "$latest" > "$tmp_dir/$slug.result"
    ) &
    pids+=($!)
  done
  local i
  for i in "${!pids[@]}"; do
    omawsl_orphan_wait_with_timeout "${pids[$i]}" "$timeout_seconds" || true
    [[ -f "$tmp_dir/${slugs[$i]}.result" ]] || printf '\t\n' > "$tmp_dir/${slugs[$i]}.result"
  done
}
EOF
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_orphan_tools_test.bats"`
Expected: PASS (16 tests)

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/orphan-tools.sh tests/omawsl_orphan_tools_test.bats
git commit -m "feat: add bounded-wait timeout and parallel version-check runner"
```

---

### Task 4: Split zellij + lazydocker into ensure/steps

**Files:**
- Modify: `install/terminal/apps-terminal.sh:26-55`
- Test: `tests/apps_terminal_test.bats`

**Interfaces:**
- Consumes: nothing.
- Produces: `omawsl_zellij_install_steps`, `omawsl_lazydocker_install_steps` (both callable standalone, no guard) — consumed by Task 8's apply dispatcher. `omawsl_install_zellij`/`omawsl_install_lazydocker` keep their exact existing names/behavior (guard + delegate to the new `_install_steps` function), so every existing test in `tests/apps_terminal_test.bats` keeps passing unmodified.

- [ ] **Step 1: Write the failing test**

```bash
cat >> tests/apps_terminal_test.bats <<'EOF'

@test "omawsl_zellij_install_steps runs unconditionally, even if zellij is already installed" {
  stub_command zellij
  run omawsl_zellij_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"unknown-linux-musl"* ]]
}

@test "omawsl_lazydocker_install_steps runs unconditionally, even if lazydocker is already installed" {
  stub_command lazydocker
  run omawsl_lazydocker_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"install_update_linux.sh"* ]]
}
EOF
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/apps_terminal_test.bats"`
Expected: FAIL — `omawsl_zellij_install_steps`/`omawsl_lazydocker_install_steps` don't exist yet.

- [ ] **Step 3: Write minimal implementation**

Replace lines 26-55 of `install/terminal/apps-terminal.sh` (the `omawsl_install_lazydocker` and `omawsl_install_zellij` functions):

```bash
# omawsl_lazydocker_install_steps
# The actual install command, no guard - called both by
# omawsl_install_lazydocker below (guarded, unchanged behavior) and by
# bin/omawsl update's orphan-tool apply phase (guard bypassed, so an
# already-installed lazydocker gets a genuine fresh install rather than
# a no-op).
omawsl_lazydocker_install_steps() {
  curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
}

# omawsl_install_lazydocker
# No Ubuntu package exists for lazydocker - installs via its official
# script (jesseduffield/lazydocker), which installs to $HOME/.local/bin
# by default (already on PATH via configs/bashrc). The script itself
# always re-downloads/reinstalls unconditionally - this command -v guard
# is what actually makes THIS entry point idempotent.
omawsl_install_lazydocker() {
  if command -v lazydocker &>/dev/null; then
    return 0
  fi
  omawsl_lazydocker_install_steps
}

# omawsl_zellij_install_steps
# The actual install command, no guard - same split rationale as
# omawsl_lazydocker_install_steps above.
omawsl_zellij_install_steps() {
  local arch
  arch="$(uname -m)"
  curl -fsSL "https://github.com/zellij-org/zellij/releases/latest/download/zellij-${arch}-unknown-linux-musl.tar.gz" | tar -xz -C /tmp
  sudo install -m 0755 /tmp/zellij /usr/local/bin/zellij
  rm -f /tmp/zellij
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
  omawsl_zellij_install_steps
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/apps_terminal_test.bats"`
Expected: PASS (all existing tests + 2 new ones)

- [ ] **Step 5: Commit**

```bash
git add install/terminal/apps-terminal.sh tests/apps_terminal_test.bats
git commit -m "refactor: split zellij/lazydocker install into ensure/steps"
```

---

### Task 5: Split opencode + Claude Code CLI into ensure/steps

**Files:**
- Modify: `install/terminal/app-opencode.sh`
- Modify: `install/terminal/app-claude-cli.sh`
- Test: `tests/app_opencode_test.bats`
- Test: `tests/app_claude_cli_test.bats`

**Interfaces:**
- Consumes: nothing.
- Produces: `omawsl_opencode_install_steps`, `omawsl_claude_cli_install_steps` (both standalone) — consumed by Task 8.

- [ ] **Step 1: Write the failing test**

```bash
cat >> tests/app_opencode_test.bats <<'EOF'

@test "omawsl_opencode_install_steps runs unconditionally, even if opencode is already installed" {
  stub_command opencode
  run omawsl_opencode_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"opencode.ai/install"* ]]
}
EOF
cat >> tests/app_claude_cli_test.bats <<'EOF'

@test "omawsl_claude_cli_install_steps runs unconditionally, even if claude is already installed" {
  stub_command claude
  run omawsl_claude_cli_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"claude.ai/install.sh"* ]]
}
EOF
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/app_opencode_test.bats tests/app_claude_cli_test.bats"`
Expected: FAIL — the two `_install_steps` functions don't exist yet.

- [ ] **Step 3: Write minimal implementation**

Replace `omawsl_install_opencode` in `install/terminal/app-opencode.sh` (lines 8-25):

```bash
# omawsl_opencode_install_steps
# The actual install command, no guard - called both by
# omawsl_install_opencode below (guarded) and by bin/omawsl update's
# orphan-tool apply phase (guard bypassed).
omawsl_opencode_install_steps() {
  curl -fsSL https://opencode.ai/install | bash
}

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

  omawsl_opencode_install_steps
}
```

Replace `omawsl_install_claude_cli` in `install/terminal/app-claude-cli.sh` (lines 8-23):

```bash
# omawsl_claude_cli_install_steps
# The actual install command, no guard - same split rationale as
# omawsl_opencode_install_steps above.
omawsl_claude_cli_install_steps() {
  curl -fsSL https://claude.ai/install.sh | bash
}

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

  omawsl_claude_cli_install_steps
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/app_opencode_test.bats tests/app_claude_cli_test.bats"`
Expected: PASS (all existing tests + 2 new ones)

- [ ] **Step 5: Commit**

```bash
git add install/terminal/app-opencode.sh install/terminal/app-claude-cli.sh tests/app_opencode_test.bats tests/app_claude_cli_test.bats
git commit -m "refactor: split opencode/Claude Code CLI install into ensure/steps"
```

---

### Task 6: Split Codex CLI + Gemini CLI into ensure/steps

**Files:**
- Modify: `install/terminal/app-codex-cli.sh`
- Modify: `install/terminal/app-gemini-cli.sh`
- Test: `tests/app_codex_cli_test.bats`
- Test: `tests/app_gemini_cli_test.bats`

**Interfaces:**
- Consumes: nothing.
- Produces: `omawsl_codex_cli_install_steps`, `omawsl_gemini_cli_install_steps` (both standalone, include the wrapper-writing step) — consumed by Task 8.

- [ ] **Step 1: Write the failing test**

```bash
cat >> tests/app_codex_cli_test.bats <<'EOF'

@test "omawsl_codex_cli_install_steps runs unconditionally and (re)writes the wrapper" {
  stub_command codex
  rm -f "$HOME/.local/bin/codex"
  run omawsl_codex_cli_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @openai/codex"* ]]
  [ -x "$HOME/.local/bin/codex" ]
}
EOF
cat >> tests/app_gemini_cli_test.bats <<'EOF'

@test "omawsl_gemini_cli_install_steps runs unconditionally and (re)writes the wrapper" {
  stub_command gemini
  rm -f "$HOME/.local/bin/gemini"
  run omawsl_gemini_cli_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"mise exec node@lts -- npm install -g @google/gemini-cli"* ]]
  [ -x "$HOME/.local/bin/gemini" ]
}
EOF
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/app_codex_cli_test.bats tests/app_gemini_cli_test.bats"`
Expected: FAIL — the two `_install_steps` functions don't exist yet. (`tests/app_gemini_cli_test.bats` already has a `setup()` sourcing `app-gemini-cli.sh` and stubbing `mise`, identical in shape to `app_codex_cli_test.bats` — confirmed, the appended test above needs no setup changes.)

- [ ] **Step 3: Write minimal implementation**

Replace `omawsl_install_codex_cli` in `install/terminal/app-codex-cli.sh` (lines 21-35):

```bash
# omawsl_codex_cli_install_steps
# The actual install + wrapper-write commands, no guard - called both by
# omawsl_install_codex_cli below (guarded) and by bin/omawsl update's
# orphan-tool apply phase (guard bypassed). Re-running this always
# re-installs the npm package at whatever version @openai/codex currently
# resolves to and rewrites the wrapper unconditionally (cheap, and keeps
# it in sync if this file's own wrapper contents ever change).
omawsl_codex_cli_install_steps() {
  mise exec node@lts -- npm install -g @openai/codex

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/codex" <<'WRAPPER'
#!/usr/bin/env bash
exec mise exec node@lts -- codex "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/codex"
}

# omawsl_install_codex_cli
# OpenAI Codex CLI - purely WSL-side, no Windows dependency (design spec
# §10). Its only distribution channel is npm (@openai/codex), so this
# uses a private mise-managed Node runtime to install it (`mise exec
# node@lts`), rather than depending on whether the user separately picked
# Node.js in the language picker - that picker is about the user's own
# project runtime, not an implementation detail of an unrelated tool
# (design spec §10). Idempotent via a command -v guard.
omawsl_install_codex_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Codex CLI"; then
    return 0
  fi

  if command -v codex &>/dev/null; then
    return 0
  fi

  omawsl_codex_cli_install_steps
}
```

Replace `omawsl_install_gemini_cli` in `install/terminal/app-gemini-cli.sh` (lines 8-30):

```bash
# omawsl_gemini_cli_install_steps
# The actual install + wrapper-write commands, no guard - same split
# rationale as omawsl_codex_cli_install_steps above.
omawsl_gemini_cli_install_steps() {
  mise exec node@lts -- npm install -g @google/gemini-cli

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/gemini" <<'WRAPPER'
#!/usr/bin/env bash
exec mise exec node@lts -- gemini "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/gemini"
}

# omawsl_install_gemini_cli
# Same shape as app-codex-cli.sh: Gemini CLI's only distribution channel
# is npm (@google/gemini-cli), so this uses a private mise-managed Node
# runtime plus an explicit $HOME/.local/bin/gemini wrapper.
omawsl_install_gemini_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Gemini CLI"; then
    return 0
  fi

  if command -v gemini &>/dev/null; then
    return 0
  fi

  omawsl_gemini_cli_install_steps
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/app_codex_cli_test.bats tests/app_gemini_cli_test.bats"`
Expected: PASS (all existing tests + 2 new ones)

- [ ] **Step 5: Commit**

```bash
git add install/terminal/app-codex-cli.sh install/terminal/app-gemini-cli.sh tests/app_codex_cli_test.bats tests/app_gemini_cli_test.bats
git commit -m "refactor: split Codex CLI/Gemini CLI install into ensure/steps"
```

---

### Task 7: Split GitHub Copilot CLI — install_steps + a distinct update_steps

**Files:**
- Modify: `install/terminal/app-gh-copilot.sh`
- Test: `tests/app_gh_copilot_test.bats`

**Interfaces:**
- Consumes: nothing.
- Produces: `omawsl_gh_copilot_install_steps` (first-time install, standalone), `omawsl_gh_copilot_update_steps` (genuinely different command — `gh extension upgrade`, not `install`, since `gh extension install` errors on an already-present extension rather than upgrading it) — `_update_steps` is what Task 8's apply dispatcher calls for this one tool.

- [ ] **Step 1: Write the failing test**

```bash
cat >> tests/app_gh_copilot_test.bats <<'EOF'

@test "omawsl_gh_copilot_install_steps runs the install command directly" {
  stub_command gh
  run omawsl_gh_copilot_install_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gh extension install github/gh-copilot"* ]]
}

@test "omawsl_gh_copilot_update_steps runs 'gh extension upgrade', not 'install'" {
  stub_command gh
  run omawsl_gh_copilot_update_steps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gh extension upgrade gh-copilot"* ]]
  [[ "$(stub_calls)" != *"extension install"* ]]
}
EOF
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/app_gh_copilot_test.bats"`
Expected: FAIL — the two new functions don't exist yet.

- [ ] **Step 3: Write minimal implementation**

Replace `omawsl_install_gh_copilot` in `install/terminal/app-gh-copilot.sh` (lines 29-43):

```bash
# omawsl_gh_copilot_install_steps
# The actual first-time install command, no guard. Not reused for
# updates: `gh extension install` errors on an already-present extension
# rather than upgrading it in place, so bin/omawsl update's apply phase
# calls omawsl_gh_copilot_update_steps below instead of this function.
omawsl_gh_copilot_install_steps() {
  gh extension install github/gh-copilot
}

# omawsl_gh_copilot_update_steps
# The actual update command for an already-installed GitHub Copilot CLI.
# Genuinely a different command from the install step above, not just
# the same command with a guard removed - `gh extension upgrade` is
# gh's own dedicated update path for an extension already present.
omawsl_gh_copilot_update_steps() {
  gh extension upgrade gh-copilot
}

# omawsl_install_gh_copilot
# GitHub Copilot CLI, installed as a gh extension - depends only on gh
# itself, which apps-terminal.sh installs unconditionally regardless of
# any picker. Idempotent via `gh extension list` (installing an
# already-present extension errors instead of no-opping). Failure-isolated
# the same way cloud-tools.sh isolates a repo-add failure: confirmed on a
# real WSL2 run that `gh extension install` itself needs an authenticated
# session, not just Copilot usage afterward - `gh auth login` hasn't run
# yet on a fresh install, so this is the default case, not an edge case.
#
# The idempotency check matches on the "github/gh-copilot" repo-slug
# column, not the extension's invocation-name column - `gh extension
# list`'s first column is actually "gh copilot" (space-separated, the
# invocation name), not "gh-copilot" (hyphenated).
omawsl_install_gh_copilot() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "GitHub Copilot CLI"; then
    return 0
  fi

  if gh extension list 2>/dev/null | grep -q 'github/gh-copilot'; then
    return 0
  fi

  if ! omawsl_gh_copilot_install_steps; then
    echo "omawsl: GitHub Copilot CLI install failed (gh not authenticated yet?) - skipping, continuing with the rest of the run."
    echo "Run 'gh auth login', then 'gh extension install github/gh-copilot' yourself, or re-run install.sh."
    echo "See docs/windows-setup.md#github-copilot-cli for why this needs to happen before install.sh, not after."
  fi
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/app_gh_copilot_test.bats"`
Expected: PASS (all existing tests + 2 new ones)

- [ ] **Step 5: Commit**

```bash
git add install/terminal/app-gh-copilot.sh tests/app_gh_copilot_test.bats
git commit -m "refactor: split GitHub Copilot CLI install, add distinct update_steps"
```

---

### Task 8: Format-line helper + apply-update dispatcher

**Files:**
- Modify: `bin/omawsl-sub/orphan-tools.sh`
- Test: `tests/omawsl_orphan_tools_test.bats`

**Interfaces:**
- Consumes: `omawsl_orphan_tool_label` (Task 1), `omawsl_zellij_install_steps`/`omawsl_lazydocker_install_steps` (Task 4), `omawsl_opencode_install_steps`/`omawsl_claude_cli_install_steps` (Task 5), `omawsl_codex_cli_install_steps`/`omawsl_gemini_cli_install_steps` (Task 6), `omawsl_gh_copilot_update_steps` (Task 7).
- Produces: `omawsl_orphan_tools_format_line <slug> <installed> <latest>` (one rendered status string), `omawsl_orphan_tool_apply_update <slug>` (re-runs that tool's update, isolated) — both consumed by Task 9.

- [ ] **Step 1: Write the failing test**

```bash
cat >> tests/omawsl_orphan_tools_test.bats <<'EOF'

@test "omawsl_orphan_tools_format_line reports update available when versions differ" {
  run omawsl_orphan_tools_format_line codex "0.38.1" "0.41.0"
  [[ "$output" == *"Codex CLI"* ]]
  [[ "$output" == *"current: 0.38.1"* ]]
  [[ "$output" == *"latest: 0.41.0"* ]]
  [[ "$output" == *"update available"* ]]
}

@test "omawsl_orphan_tools_format_line reports up to date when versions match" {
  run omawsl_orphan_tools_format_line gemini "2.1.0" "2.1.0"
  [[ "$output" == *"up to date"* ]]
}

@test "omawsl_orphan_tools_format_line reports unknown when latest is empty" {
  run omawsl_orphan_tools_format_line zellij "0.44.3" ""
  [[ "$output" == *"unknown"* ]]
}

@test "omawsl_orphan_tool_apply_update dispatches to the right tool's steps function" {
  omawsl_codex_cli_install_steps() { echo "codex-updated" >> "$STUB_LOG"; }
  export -f omawsl_codex_cli_install_steps
  run omawsl_orphan_tool_apply_update codex
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"codex-updated"* ]]
}

@test "omawsl_orphan_tool_apply_update calls gh_copilot's update_steps, not install_steps" {
  omawsl_gh_copilot_update_steps() { echo "gh-copilot-updated" >> "$STUB_LOG"; }
  export -f omawsl_gh_copilot_update_steps
  omawsl_gh_copilot_install_steps() { echo "gh-copilot-installed" >> "$STUB_LOG"; }
  export -f omawsl_gh_copilot_install_steps
  run omawsl_orphan_tool_apply_update gh-copilot
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gh-copilot-updated"* ]]
  [[ "$(stub_calls)" != *"gh-copilot-installed"* ]]
}

@test "omawsl_orphan_tool_apply_update isolates a failure and keeps a zero exit" {
  omawsl_codex_cli_install_steps() { return 1; }
  export -f omawsl_codex_cli_install_steps
  run omawsl_orphan_tool_apply_update codex
  [ "$status" -eq 0 ]
  [[ "$output" == *"failed to update"* ]]
}
EOF
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_orphan_tools_test.bats"`
Expected: FAIL — `omawsl_orphan_tools_format_line`/`omawsl_orphan_tool_apply_update` don't exist yet.

- [ ] **Step 3: Write minimal implementation**

Add near the top of `bin/omawsl-sub/orphan-tools.sh`'s source block (after the existing `source "$SCRIPT_DIR/items.sh"` line), source the 6 install scripts whose `_install_steps`/`_update_steps` functions this file's apply dispatcher needs:

```bash
# shellcheck source=../../install/terminal/apps-terminal.sh
source "$OMAWSL_ROOT_DIR/install/terminal/apps-terminal.sh"
# shellcheck source=../../install/terminal/app-opencode.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-opencode.sh"
# shellcheck source=../../install/terminal/app-claude-cli.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-claude-cli.sh"
# shellcheck source=../../install/terminal/app-codex-cli.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-codex-cli.sh"
# shellcheck source=../../install/terminal/app-gemini-cli.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-gemini-cli.sh"
# shellcheck source=../../install/terminal/app-gh-copilot.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-gh-copilot.sh"
```

Then append the two new functions:

```bash
cat >> bin/omawsl-sub/orphan-tools.sh <<'EOF'

# omawsl_orphan_tools_format_line <slug> <installed> <latest>
# One rendered status line for a single orphan tool, given its already-
# resolved installed/latest versions (empty string for either means
# "unknown" - a genuine lookup failure/timeout, not a real "0" version).
# Shared by the picker labels and (Task 9) the live-redraw status phase,
# so they can never drift out of sync with each other.
omawsl_orphan_tools_format_line() {
  local slug="$1" installed="$2" latest="$3"
  local label; label="$(omawsl_orphan_tool_label "$slug")"
  local status
  if [[ -z "$latest" ]]; then
    status="unknown"
  elif [[ "$installed" == "$latest" ]]; then
    status="up to date"
  else
    status="update available"
  fi
  printf '%-22s current: %-10s latest: %-10s (%s)' \
    "$label" "${installed:-unknown}" "${latest:-unknown}" "$status"
}

# omawsl_orphan_tool_apply_update <slug>
# Re-runs the given orphan tool's install steps, guard bypassed, so an
# already-installed tool gets a genuine fresh install/update rather than
# the no-op its normal command -v guard would otherwise produce.
# gh-copilot is the one exception: its own "steps" function for THIS
# purpose is omawsl_gh_copilot_update_steps (`gh extension upgrade`), not
# omawsl_gh_copilot_install_steps (`gh extension install`, which errors
# on an already-present extension rather than upgrading it - Task 7).
# Isolated per tool (cloud-tools.sh's own `{ ... } || ok=0` pattern) so
# one tool's failed update doesn't abort the rest of the selected
# updates or the overall omawsl update run.
omawsl_orphan_tool_apply_update() {
  local slug="$1"
  local label; label="$(omawsl_orphan_tool_label "$slug")"
  local ok=1
  case "$slug" in
    zellij) omawsl_zellij_install_steps || ok=0 ;;
    lazydocker) omawsl_lazydocker_install_steps || ok=0 ;;
    opencode) omawsl_opencode_install_steps || ok=0 ;;
    claude) omawsl_claude_cli_install_steps || ok=0 ;;
    codex) omawsl_codex_cli_install_steps || ok=0 ;;
    gemini) omawsl_gemini_cli_install_steps || ok=0 ;;
    gh-copilot) omawsl_gh_copilot_update_steps || ok=0 ;;
  esac
  if [[ "$ok" -eq 0 ]]; then
    echo "omawsl: failed to update $label - skipping, continuing with the rest."
  else
    echo "omawsl: updated $label."
  fi
}
EOF
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_orphan_tools_test.bats"`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/orphan-tools.sh tests/omawsl_orphan_tools_test.bats
git commit -m "feat: add orphan-tool status formatting and update dispatcher"
```

---

### Task 9: Two-phase orchestration + wire into `omawsl update`

**Files:**
- Modify: `bin/omawsl-sub/orphan-tools.sh`
- Modify: `bin/omawsl-sub/update.sh:1-46`
- Test: `tests/omawsl_orphan_tools_test.bats`
- Test: `tests/omawsl_update_test.bats`

**Interfaces:**
- Consumes: everything from Tasks 1-3 and 8.
- Produces: `omawsl_orphan_tools_installed_slugs` (prints installed slugs, registry order), `omawsl_orphan_tools_live_check` (TTY-only status redraw, wraps Task 3's runner), `omawsl_orphan_tools_update` (the full entry point: detect installed tools, check versions — live-redrawn on a real TTY, silent otherwise — skip-or-show picker, apply selected updates) — called by `omawsl_update` after its existing migrate step.

- [ ] **Step 1: Write the failing test**

```bash
cat >> tests/omawsl_orphan_tools_test.bats <<'EOF'

@test "omawsl_orphan_tools_installed_slugs lists only what's actually installed" {
  stub_hide_command zellij lazydocker opencode claude codex gemini gh
  stub_command zellij
  stub_command codex
  run omawsl_orphan_tools_installed_slugs
  [ "$status" -eq 0 ]
  [[ "$output" == *"zellij"* ]]
  [[ "$output" == *"codex"* ]]
  [[ "$output" != *"lazydocker"* ]]
}

@test "omawsl_orphan_tools_update no-ops cleanly when no orphan tool is installed" {
  stub_hide_command zellij lazydocker opencode claude codex gemini gh
  run omawsl_orphan_tools_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"no orphan tools installed"* ]]
}

@test "omawsl_orphan_tools_update skips the picker when everything is confirmed up to date" {
  stub_hide_command lazydocker opencode claude codex gemini gh
  stub_command zellij
  zellij() { echo "zellij 1.0.0"; }
  export -f zellij
  omawsl_orphan_tool_version_latest() { echo "1.0.0"; }
  export -f omawsl_orphan_tool_version_latest
  run omawsl_orphan_tools_update
  [ "$status" -eq 0 ]
  [[ "$output" == *"already up to date"* ]]
  [[ "$(stub_calls)" != *"gum choose"* ]]
}

@test "omawsl_orphan_tools_update shows the picker, pre-selecting only outdated tools, and applies what's picked" {
  stub_hide_command lazydocker opencode claude codex gemini gh
  stub_command zellij
  gum_stub_init
  zellij() { echo "zellij 1.0.0"; }
  export -f zellij
  omawsl_orphan_tool_version_latest() { echo "2.0.0"; }
  export -f omawsl_orphan_tool_version_latest
  omawsl_zellij_install_steps() { echo "zellij-updated" >> "$STUB_LOG"; }
  export -f omawsl_zellij_install_steps
  gum_stub_respond "$(omawsl_orphan_tools_format_line zellij 1.0.0 2.0.0)"

  run omawsl_orphan_tools_update
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gum choose"* ]]
  [[ "$(stub_calls)" == *"--selected"* ]]
  [[ "$(stub_calls)" == *"zellij-updated"* ]]
}

@test "omawsl_orphan_tools_update still shows the picker when a tool is unknown, even with none confirmed outdated" {
  stub_hide_command lazydocker opencode claude codex gemini gh
  stub_command zellij
  gum_stub_init
  zellij() { echo "zellij 1.0.0"; }
  export -f zellij
  omawsl_orphan_tool_version_latest() { echo ""; }
  export -f omawsl_orphan_tool_version_latest
  gum_stub_respond ""

  run omawsl_orphan_tools_update
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"gum choose"* ]]
}

@test "omawsl_orphan_tools_live_check eventually prints the resolved version line" {
  local tmp_dir="$BATS_TEST_TMPDIR/live-check"
  mkdir -p "$tmp_dir"
  zellij() { echo "zellij 1.0.0"; }
  export -f zellij
  omawsl_orphan_tool_version_latest() { echo "2.0.0"; }
  export -f omawsl_orphan_tool_version_latest
  run omawsl_orphan_tools_live_check "$tmp_dir" 5 zellij
  [ "$status" -eq 0 ]
  [[ "$output" == *"current: 1.0.0"* ]]
  [[ "$output" == *"latest: 2.0.0"* ]]
}
EOF
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_orphan_tools_test.bats"`
Expected: FAIL — `omawsl_orphan_tools_installed_slugs`/`omawsl_orphan_tools_update`/`omawsl_orphan_tools_live_check` don't exist yet.

- [ ] **Step 3: Write minimal implementation**

Append to `bin/omawsl-sub/orphan-tools.sh`:

```bash
cat >> bin/omawsl-sub/orphan-tools.sh <<'EOF'

# omawsl_orphan_tools_installed_slugs
# Which of the 7 orphan tools are actually installed right now, in
# registry order.
omawsl_orphan_tools_installed_slugs() {
  local slug
  while IFS= read -r slug; do
    omawsl_orphan_tool_installed "$slug" && echo "$slug"
  done < <(omawsl_orphan_tool_slugs)
  return 0
}

# omawsl_orphan_tools_live_check <tmp_dir> <timeout_seconds> <slug...>
# TTY-only companion to omawsl_orphan_tools_check_versions (Task 3):
# prints a "checking..." placeholder line per tool immediately, runs the
# real check via that same function in the background (reused as-is, not
# reimplemented - this function only adds a live terminal redraw on top),
# and redraws the whole block in place every 0.2s using tput cursor
# movement until the background check itself exits. `tput` calls are
# each `|| true`-guarded so a terminal that doesn't support cursor
# movement degrades to extra scrollback rather than an error.
omawsl_orphan_tools_live_check() {
  local tmp_dir="$1" timeout_seconds="$2"; shift 2
  local slugs=("$@")
  local slug label installed latest

  for slug in "${slugs[@]}"; do
    label="$(omawsl_orphan_tool_label "$slug")"
    printf '%-22s checking...\n' "$label"
  done

  omawsl_orphan_tools_check_versions "$tmp_dir" "$timeout_seconds" "${slugs[@]}" &
  local runner_pid=$!

  while kill -0 "$runner_pid" 2>/dev/null; do
    sleep 0.2
    tput cuu "${#slugs[@]}" 2>/dev/null || true
    for slug in "${slugs[@]}"; do
      tput el 2>/dev/null || true
      if [[ -f "$tmp_dir/$slug.result" ]]; then
        IFS=$'\t' read -r installed latest < "$tmp_dir/$slug.result"
        omawsl_orphan_tools_format_line "$slug" "$installed" "$latest"
        echo
      else
        label="$(omawsl_orphan_tool_label "$slug")"
        printf '%-22s checking...\n' "$label"
      fi
    done
  done
  wait "$runner_pid" 2>/dev/null || true

  tput cuu "${#slugs[@]}" 2>/dev/null || true
  for slug in "${slugs[@]}"; do
    tput el 2>/dev/null || true
    IFS=$'\t' read -r installed latest < "$tmp_dir/$slug.result"
    omawsl_orphan_tools_format_line "$slug" "$installed" "$latest"
    echo
  done
}

# omawsl_orphan_tools_update
# Entry point called from omawsl_update (bin/omawsl-sub/update.sh) after
# its existing self-update + migrate steps (design spec §4). No-ops
# cleanly if no orphan tool is installed. Uses the live-redraw status
# phase only when connected to a real terminal (design spec §6 - `gum
# choose` itself can't live-update rows once shown, so this is a
# separate phase before the picker, not part of it); bats' `run` never
# provides a real TTY, so tests always exercise the plain
# omawsl_orphan_tools_check_versions path deterministically, while a real
# interactive run gets the live "checking..." -> resolved-version redraw.
omawsl_orphan_tools_update() {
  local slugs=() slug
  while IFS= read -r slug; do slugs+=("$slug"); done < <(omawsl_orphan_tools_installed_slugs)

  if [[ "${#slugs[@]}" -eq 0 ]]; then
    echo "omawsl: no orphan tools installed - nothing to check."
    return 0
  fi

  local tmp_dir; tmp_dir="$(mktemp -d)"
  if [[ -t 1 ]]; then
    omawsl_orphan_tools_live_check "$tmp_dir" 5 "${slugs[@]}"
  else
    omawsl_orphan_tools_check_versions "$tmp_dir" 5 "${slugs[@]}"
  fi

  local any_available=0 any_unknown=0
  local options=() selected=()
  for slug in "${slugs[@]}"; do
    local installed latest line
    IFS=$'\t' read -r installed latest < "$tmp_dir/$slug.result"
    line="$(omawsl_orphan_tools_format_line "$slug" "$installed" "$latest")"
    options+=("$line")
    if [[ -z "$latest" ]]; then
      any_unknown=1
    elif [[ "$installed" != "$latest" ]]; then
      any_available=1
      selected+=("$line")
    fi
  done
  rm -rf "$tmp_dir"

  if [[ "$any_available" -eq 0 && "$any_unknown" -eq 0 ]]; then
    echo "omawsl: everything is already up to date."
    return 0
  fi

  local preselected=""
  if [[ "${#selected[@]}" -gt 0 ]]; then
    preselected="$(printf '%s\n' "${selected[@]}" | paste -sd, -)"
  fi

  local picked
  picked="$(gum choose --no-limit --selected "$preselected" --header "Update orphan tools (no native updater of their own)" "${options[@]}")" || picked=""
  [[ -n "$picked" ]] || return 0

  local chosen_line
  while IFS= read -r chosen_line; do
    [[ -z "$chosen_line" ]] && continue
    for slug in "${slugs[@]}"; do
      if [[ "$chosen_line" == "$(omawsl_orphan_tool_label "$slug")"* ]]; then
        omawsl_orphan_tool_apply_update "$slug"
        break
      fi
    done
  done <<< "$picked"
}
EOF
```

Modify `bin/omawsl-sub/update.sh`: add the source line and the new call. Full replacement:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=migrate.sh
source "$SCRIPT_DIR/migrate.sh"
# shellcheck source=orphan-tools.sh
source "$SCRIPT_DIR/orphan-tools.sh"

# omawsl_update
# Entry point for `bin/omawsl update` (design spec §14, extended by
# docs/superpowers/specs/2026-07-13-omawsl-update-mechanism-design.md
# §4): git pull inside $OMAWSL_HOME, runs pending migrations, then offers
# to update the 7 "orphan" tools that have no native updater of their
# own (§3 of that spec) - never wraps `apt upgrade`/`mise upgrade`
# themselves. Detects a dirty working tree first (someone hand-edited a
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

  omawsl_orphan_tools_update

  echo "omawsl: languages/cloud tools -> mise upgrade, or 'omawsl install language <x>'. System packages -> sudo apt upgrade. Full breakdown: docs/updating.md."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_update
fi
```

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/omawsl_orphan_tools_test.bats tests/omawsl_update_test.bats"`
Expected: PASS (all tests, including the 3 pre-existing `omawsl_update_test.bats` tests — none of them stub `gum`/orphan-tool commands, so with every orphan tool absent, `omawsl_orphan_tools_update` prints its "nothing installed" no-op line and returns immediately without needing a `gum` stub)

- [ ] **Step 5: Commit**

```bash
git add bin/omawsl-sub/orphan-tools.sh bin/omawsl-sub/update.sh tests/omawsl_orphan_tools_test.bats tests/omawsl_update_test.bats
git commit -m "feat: wire orphan-tool update picker into bin/omawsl update"
```

---

### Task 10: `docs/updating.md` + README link + closing pointer

**Files:**
- Create: `docs/updating.md`
- Modify: `README.md`
- Test: `tests/docs_updating_test.bats`
- Test: `tests/readme_test.bats`

**Interfaces:**
- Consumes: nothing new (the closing pointer text was already added to `update.sh` in Task 9).
- Produces: nothing consumed by later tasks — this is the final documentation deliverable.

- [ ] **Step 1: Write the failing test**

```bash
cat > tests/docs_updating_test.bats <<'EOF'
#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DOC="$REPO_ROOT/docs/updating.md"

@test "docs/updating.md exists" {
  [ -f "$DOC" ]
}

@test "docs/updating.md documents all four update groups" {
  grep -qi "omawsl update" "$DOC"
  grep -qi "mise upgrade" "$DOC"
  grep -qi "apt upgrade" "$DOC"
  grep -qi "VS Code" "$DOC"
  grep -qi "own update" "$DOC"
}

@test "docs/updating.md lists all 7 orphan tools by name" {
  for tool in Zellij LazyDocker opencode "Claude Code CLI" "Codex CLI" "Gemini CLI" "GitHub Copilot CLI"; do
    grep -qF "$tool" "$DOC" || { echo "missing tool: $tool"; return 1; }
  done
}
EOF
cat >> tests/readme_test.bats <<'EOF'

@test "README.md links to docs/updating.md" {
  grep -q "docs/updating.md" "$DOC"
}
EOF
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/docs_updating_test.bats tests/readme_test.bats"`
Expected: FAIL — `docs/updating.md` doesn't exist yet, README doesn't link to it.

- [ ] **Step 3: Write minimal implementation**

```bash
cat > docs/updating.md <<'EOF'
# Updating what omawsl installed

`omawsl update` pulls the latest omawsl and runs any pending migrations - but not everything
omawsl installs is updated the same way. Four groups, four answers:

## omawsl itself

Run `omawsl update`. This is always the first thing it does: `git pull` inside your omawsl
checkout, then pending migrations.

## Language runtimes & cloud tools

Ruby, Node.js, Go, PHP, Python, Elixir, Rust, Java, Terraform, Azure CLI - all managed by
[mise](https://mise.jdx.dev). Either run `mise upgrade` yourself, or re-run
`omawsl install language <name>` (e.g. `omawsl install language go`), which re-pins to the
latest release the same way the first install did.

## System packages

Everything installed via `apt` - fzf, ripgrep, bat, eza, zoxide, Docker Engine, Neovim,
LazyGit, and the rest of the always-on terminal tool set. Run `sudo apt upgrade` like you would
for anything else on the system.

**Windows-side GUI apps** (VS Code, Cursor) aren't touched by omawsl at all, ever - they run
their own update lifecycle on Windows (VS Code's built-in updater, Cursor's own auto-update),
the same way omawsl never auto-installs them in the first place.

## The rest: `omawsl update`

Seven tools have no update command of their own - no apt package, no mise tool, nothing to
run yourself. `omawsl update` checks each one that's currently installed against its real
latest release, then offers a picker (pre-checked for anything outdated) to bring them
current:

- Zellij
- LazyDocker
- opencode
- Claude Code CLI
- Codex CLI
- Gemini CLI
- GitHub Copilot CLI

If everything here is already confirmed up to date, `omawsl update` says so and skips the
picker - there's nothing for it to offer.
EOF
```

Edit `README.md`: in the "What you get" section, after the existing paragraph ending "...Windows Terminal's own color scheme, synced automatically.", add a new sentence with the link (matching the file's existing style of linking to `docs/windows-setup.md` rather than duplicating its content):

```bash
python3 - <<'PYEOF'
import pathlib
p = pathlib.Path("README.md")
text = p.read_text()
marker = "Windows Terminal's\nown color scheme, synced automatically.\n"
addition = marker + "\nSee [`docs/updating.md`](docs/updating.md) for how to keep everything current - omawsl itself, " \
    "language runtimes, system packages, and the handful of tools with no native updater of their own.\n"
assert marker in text, "marker not found in README.md"
p.write_text(text.replace(marker, addition, 1))
PYEOF
```

(If `python3` isn't available in the implementer's shell, make the equivalent one-paragraph addition directly with the Edit tool instead — the exact inserted text is what matters, not the mechanism.)

- [ ] **Step 4: Run test to verify it passes**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/docs_updating_test.bats tests/readme_test.bats"`
Expected: PASS (all tests)

- [ ] **Step 5: Commit**

```bash
git add docs/updating.md README.md tests/docs_updating_test.bats tests/readme_test.bats
git commit -m "docs: add docs/updating.md and link it from README"
```

---

### Task 11: Full regression run + manual end-to-end verification (human-only)

**Files:** none (verification only).

**Interfaces:** none — this task consumes the whole feature and produces nothing further.

- [ ] **Step 1: Run the complete bats suite**

Run: `wsl.exe -d Ubuntu -- bash -ic "cd '$(wslpath -u "$(pwd)")' && tests/.bats-core/bin/bats tests/*.bats"`
Expected: every test passes (aside from the pre-existing, unrelated `windows_terminal_test.bats` `cmd.exe`-reachability flake already documented as expected on this machine).

- [ ] **Step 2: Commit any fixes found**

If the full-suite run surfaces a real regression (e.g. an interaction between two of this feature's tasks not caught by running each task's own test file in isolation), fix it and commit with a `fix:` message describing exactly what the full-suite run caught.

- [ ] **Step 3: Hand off for human verification**

This plan's automated tasks cover everything that can be stubbed. Two things genuinely need a human on the real WSL2 test instance, because they depend on real network calls and a real terminal, per this project's established Task-N convention (see `docs/superpowers/specs/2026-07-13-omawsl-update-mechanism-design.md` §5, §6):

1. Install at least one orphan tool at an older version if possible (or just use whatever's currently installed), then run `omawsl update` for real and confirm: the version-check phase resolves real current/latest versions against the real GitHub Releases API / npm registry (not stubbed), the picker pre-checks exactly the outdated tool(s), and applying an update actually brings that tool current (re-check its `--version` afterward).
2. Confirm the TTY live-redraw status phase (the "checking..." → real-version redraw, §6 of the design spec) actually looks right in a real interactive terminal — this is the one piece of this feature with no automated test coverage at all (bats' `run` never provides a real TTY), by design (Global Constraints, Task 9).

Do not consider this feature done until this task is reported back — do not write "DONE" anywhere based on the automated suite alone.
