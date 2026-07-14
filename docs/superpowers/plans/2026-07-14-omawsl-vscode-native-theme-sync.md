# Native Windows VS Code/Cursor Theme Sync Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `bin/omawsl theme <name>` also patches the real native Windows-side VS Code and Cursor
`settings.json` (not just the existing Remote-WSL machine-settings files), so the desktop apps
themselves get themed too — safely, even when the file contains hand-written JSONC comments.

**Architecture:** One merge function in `themes/set-vscode-theme.sh` handles all four
settings-file targets (2 existing Remote-WSL files + 2 new native files). It tries a `jq`
fast path for strict JSON, and falls back to a comment-preserving `sed`/`awk` edit — validated
by stripping comments into a throwaway scratch copy before and after — for JSONC files. Native
file paths are resolved via the Windows-profile helper already used for Windows Terminal theme
sync (`omawsl_windows_userprofile`, `install/lib.sh`).

**Tech Stack:** bash, jq, sed, awk, bats (test framework, vendored at `tests/.bats-core`) — no
new dependencies.

## Global Constraints

- No new external dependencies — bash builtins, `jq`, `sed`, `awk` only (matches the rest of the
  codebase's tool choices; see design spec).
- Every settings-file write is backed up first (`<file>.bak`) and re-validated after editing;
  never leave a file that fails re-validation — restore/skip instead (matches the Windows
  Terminal theme-sync precedent in `bin/omawsl-sub/windows-terminal.sh`).
- Never `mv` a temp file across the `/mnt/c` boundary — use `cp` + `rm` (drvfs doesn't support
  the metadata-preserving syscalls `mv` needs; same reasoning already documented in
  `bin/omawsl-sub/windows-terminal.sh`).
- Every failure mode is a graceful skip (print a message pointing at
  `docs/windows-setup.md#vscode-theme`, `return 0`) — never fail the rest of `bin/omawsl theme`.
- Theme names passed in are always the Title Case output of `omawsl_theme_display_name` (letters
  and spaces only, e.g. `"Tokyo Night"`) — no shell-metacharacter or quote-escaping concerns in
  the `sed`/`awk` substitutions below.
- **Run tests via WSL**, from this Windows checkout's own path, since `bats`, `jq`, and this
  project's runtime all target a real WSL2 environment:
  ```bash
  wsl -d Ubuntu -- bash -lc "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && ./tests/.bats-core/bin/bats tests/<file>.bats"
  ```
  One pre-existing, unrelated failure will appear any time `tests/windows_terminal_test.bats`
  runs in this real WSL2 environment: `omawsl_windows_userprofile fails cleanly when cmd.exe
  isn't reachable` fails because `cmd.exe` is genuinely reachable via real Win32 interop here
  (the test's `unset -f cmd.exe` only removes the stub, falling through to the real binary).
  This is not caused by this plan's changes — ignore it, don't try to fix it.
- **Never run `tests/omawsl_cli_test.bats` (or any file outside the ones each task names
  explicitly) as part of this plan.** Two of its tests (`omawsl_theme_apply copies the
  zellij/btop theme files...` and `omawsl_theme_apply only touches neovim's theme.lua...`) don't
  stub `cmd.exe`/`wslpath`, so in this real WSL2 environment `omawsl_windows_userprofile`
  resolves the *real* Windows profile and `omawsl_theme_apply` can write to the user's *real*
  Windows Terminal `settings.json` — and, once Task 2 lands, the user's *real* native VS
  Code/Cursor `settings.json` too. This is a pre-existing test-isolation gap, not something this
  plan introduces or needs to fix; every test command below is scoped to specific files that
  correctly stub `cmd.exe`/`wslpath`, precisely to avoid it. Do not "helpfully" broaden any test
  command to `tests/*.bats` or `bats tests/`.

---

### Task 1: Comment-safe, backed-up settings merge

**Files:**
- Modify: `themes/set-vscode-theme.sh`
- Test: `tests/theme_vscode_test.bats`

**Interfaces:**
- Produces: `omawsl_strip_jsonc_comments <file>` — prints a best-effort comment-stripped copy of
  `<file>` to stdout (used only for structural validation, never written back to any real file).
- Produces (rewritten, same name/signature as today):
  `omawsl_theme_set_vscode_settings <settings_file> <color_theme>` — merges
  `"workbench.colorTheme": "<color_theme>"` into `<settings_file>` in place. No-ops (return 0,
  no output) if `<settings_file>` doesn't exist or `jq` isn't reachable. Always backs up to
  `<settings_file>.bak` before editing. Handles both strict JSON and JSONC (comments) inputs.
  Task 2 calls this unchanged for the 2 new native-path targets.

- [ ] **Step 1: Read current file for context**

Read `themes/set-vscode-theme.sh` in full so the edit in Step 3 has exact surrounding content.

- [ ] **Step 2: Write the new/changed tests**

Add these `@test` blocks to `tests/theme_vscode_test.bats` (after the existing ones, before the
final `omawsl_theme_apply_vscode skips the extension install...` test or after it — append at
end of file):

```bash
@test "omawsl_theme_set_vscode_settings backs up the file before editing" {
  mkdir -p "$HOME/.vscode-server/data/Machine"
  local settings="$HOME/.vscode-server/data/Machine/settings.json"
  cp "$REPO_ROOT/configs/vscode.json" "$settings"
  run omawsl_theme_set_vscode_settings "$settings" "Tokyo Night"
  [ "$status" -eq 0 ]
  [ -f "$settings.bak" ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$settings.bak")" == "Default Dark Modern" ]]
}

@test "omawsl_theme_set_vscode_settings adds workbench.colorTheme to a JSONC file and preserves its comments" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  cat > "$settings" <<'EOF'
{
  // editor settings
  "editor.fontSize": 14,
  "editor.tabSize": 2
}
EOF
  run omawsl_theme_set_vscode_settings "$settings" "Tokyo Night"
  [ "$status" -eq 0 ]
  grep -qF '// editor settings' "$settings"
  [[ "$(omawsl_strip_jsonc_comments "$settings" | jq -r '.["workbench.colorTheme"]')" == "Tokyo Night" ]]
  [[ "$(omawsl_strip_jsonc_comments "$settings" | jq -r '.["editor.tabSize"]')" == "2" ]]
}

@test "omawsl_theme_set_vscode_settings replaces an existing workbench.colorTheme in a JSONC file and preserves its comments" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  cat > "$settings" <<'EOF'
{
  "workbench.colorTheme": "Default Dark Modern", // active theme
  "editor.fontSize": 14
}
EOF
  run omawsl_theme_set_vscode_settings "$settings" "Tokyo Night"
  [ "$status" -eq 0 ]
  grep -qF '// active theme' "$settings"
  [[ "$(omawsl_strip_jsonc_comments "$settings" | jq -r '.["workbench.colorTheme"]')" == "Tokyo Night" ]]
  [[ "$(omawsl_strip_jsonc_comments "$settings" | jq -r '.["editor.fontSize"]')" == "14" ]]
}

@test "omawsl_theme_set_vscode_settings skips gracefully when the file isn't valid JSON even after stripping comments" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  printf 'not valid json {{{\n' > "$settings"
  run omawsl_theme_set_vscode_settings "$settings" "Tokyo Night"
  [ "$status" -eq 0 ]
  [[ "$output" == *"isn't valid JSON"* ]]
  [[ "$(cat "$settings")" == "not valid json {{{" ]]
}

@test "omawsl_theme_set_vscode_settings rolls back and leaves the file untouched if its own edit would corrupt the JSON" {
  local settings="$BATS_TEST_TMPDIR/settings.json"
  cat > "$settings" <<'EOF'
// use { as a note
{
  "editor.fontSize": 14
}
EOF
  local original; original="$(cat "$settings")"
  run omawsl_theme_set_vscode_settings "$settings" "Tokyo Night"
  [ "$status" -eq 0 ]
  [[ "$output" == *"invalid JSON"* ]]
  [ -f "$settings.bak" ]
  [[ "$(cat "$settings")" == "$original" ]]
}
```

- [ ] **Step 3: Run the new tests to verify they fail**

```bash
wsl -d Ubuntu -- bash -lc "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && ./tests/.bats-core/bin/bats tests/theme_vscode_test.bats"
```

Expected: the 4 pre-existing tests still pass; the 5 new tests fail (missing backup, no comment
handling yet, `omawsl_strip_jsonc_comments: command not found`, etc.).

- [ ] **Step 4: Rewrite `themes/set-vscode-theme.sh`**

Replace the file's contents with:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_strip_jsonc_comments <file>
# Prints a best-effort comment-stripped copy of <file> to stdout, for
# structural validation only - the result is never written back to any
# real file, so hand-written comments in the actual settings.json are
# never touched or lost. Strips '//' line comments (but not when the
# '//' is immediately preceded by ':', so "http://..." inside a string
# value survives) and single-line '/* ... */' block comments. Known
# limitation: doesn't handle multi-line block comments, or a '//'/'/*'
# elsewhere inside a string value - both just make the stripped copy
# fail to parse as JSON, which makes the caller skip gracefully rather
# than risk corrupting anything real.
omawsl_strip_jsonc_comments() {
  sed -E 's#/\*.*\*/##g; s#(^|[^:])//.*$#\1#' "$1"
}

# omawsl_theme_set_vscode_settings <settings_file> <color_theme>
# Merges "workbench.colorTheme" into an existing VS Code/Cursor-shaped
# settings.json, whether it's strict JSON (every omawsl-deployed
# Remote-WSL machine-settings file) or JSONC with comments (typical of
# a hand-edited native settings.json - design spec "Sync theme to
# native Windows-side VS Code/Cursor" §"The JSONC problem"). No-ops if
# the settings file doesn't exist yet or if jq isn't reachable. Always
# backs up to <settings_file>.bak first and re-validates its own edit
# before committing - a corrupted settings.json breaks the user's whole
# editor, not just the theme.
omawsl_theme_set_vscode_settings() {
  local settings_file="$1" color_theme="$2"
  [[ -f "$settings_file" ]] || return 0
  command -v jq &>/dev/null || return 0

  cp "$settings_file" "$settings_file.bak"

  # Fast path: strict JSON, no comments - merge directly with jq.
  if jq empty "$settings_file" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    jq --arg theme "$color_theme" '.["workbench.colorTheme"] = $theme' "$settings_file" > "$tmp"
    cp "$tmp" "$settings_file"
    rm -f "$tmp"
    return 0
  fi

  # JSONC fallback: jq couldn't parse it directly (comments, most
  # likely). Strip comments into a throwaway scratch copy purely to (a)
  # confirm the file is otherwise structurally valid and (b) check
  # whether the key already exists - the real edit below never touches
  # the scratch copy, only the original comment-containing file.
  local stripped
  stripped="$(mktemp)"
  omawsl_strip_jsonc_comments "$settings_file" > "$stripped"

  if ! jq empty "$stripped" 2>/dev/null; then
    echo "omawsl: $settings_file isn't valid JSON - skipping the color sync."
    echo "See docs/windows-setup.md#vscode-theme for the manual steps."
    rm -f "$stripped"
    return 0
  fi

  local tmp_edited
  tmp_edited="$(mktemp)"
  if jq -e 'has("workbench.colorTheme")' "$stripped" >/dev/null; then
    sed -E "s/(\"workbench\.colorTheme\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"/\1\"$color_theme\"/" "$settings_file" > "$tmp_edited"
  else
    awk -v val="$color_theme" '
      !done && /\{/ {
        sub(/\{/, "{\n  \"workbench.colorTheme\": \"" val "\",")
        done = 1
      }
      { print }
    ' "$settings_file" > "$tmp_edited"
  fi

  # Re-validate the result before committing - if our own edit produced
  # something that no longer parses (e.g. a literal '{' inside a
  # comment threw off the insert point), roll back rather than leave a
  # broken settings.json in place.
  local recheck
  recheck="$(mktemp)"
  omawsl_strip_jsonc_comments "$tmp_edited" > "$recheck"
  if jq empty "$recheck" 2>/dev/null; then
    cp "$tmp_edited" "$settings_file"
  else
    echo "omawsl: the color sync edit to $settings_file produced invalid JSON - leaving it untouched (backup at $settings_file.bak)." >&2
  fi

  rm -f "$stripped" "$tmp_edited" "$recheck"
}

# omawsl_theme_apply_vscode <color_theme> <extension_id>
# Applies the theme to VS Code's and Cursor's Remote-WSL settings.json
# (whichever exist) and, if a Windows profile can be resolved, to their
# native Windows-side settings.json too (design spec "Sync theme to
# native Windows-side VS Code/Cursor" - Cursor reads the same
# workbench.colorTheme key and shares this same step). Installs the VS
# Code extension via `code --install-extension` only when `code` is
# reachable - matches app-vscode.sh's own detect-and-defer shape
# (Phase 4). Deliberately does NOT attempt `cursor --install-extension`,
# same reasoning as app-cursor.sh (Phase 4): Cursor has its own
# extension distribution and commonly blocks Microsoft-published
# extensions from its marketplace, so this only touches what's clearly
# specified (shared settings keys).
omawsl_theme_apply_vscode() {
  local color_theme="$1" extension_id="$2"

  omawsl_theme_set_vscode_settings "$HOME/.vscode-server/data/Machine/settings.json" "$color_theme"
  omawsl_theme_set_vscode_settings "$HOME/.cursor-server/data/Machine/settings.json" "$color_theme"

  if omawsl_code_reachable; then
    # NODE_NO_WARNINGS=1: VS Code's `code` CLI is itself a Node.js binary
    # and emits a `[DEP0169] DeprecationWarning: url.parse()...` to
    # stderr on every fresh extension install - confirmed Microsoft's own
    # tooling noise (reproduced in isolation, unrelated to omawsl), but
    # real, alarming-looking, and repeated on every `bin/omawsl theme`
    # call. This is the standard Node.js env var for suppressing runtime
    # deprecation warnings without touching stderr for genuine errors.
    NODE_NO_WARNINGS=1 code --install-extension "$extension_id" >/dev/null
  fi
}
```

(Task 2 adds the native-path calls to `omawsl_theme_apply_vscode` — leave it exactly as above
for this task; the existing `omawsl_theme_apply_vscode` tests must keep passing unchanged.)

- [ ] **Step 5: Run the tests again to verify they pass**

```bash
wsl -d Ubuntu -- bash -lc "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && ./tests/.bats-core/bin/bats tests/theme_vscode_test.bats"
```

Expected: all 9 tests pass (`1..9`, all `ok`).

- [ ] **Step 6: Commit**

```bash
git add themes/set-vscode-theme.sh tests/theme_vscode_test.bats
git commit -m "$(cat <<'EOF'
feat: preserve JSONC comments when merging VS Code theme settings

omawsl_theme_set_vscode_settings now backs up every settings.json it
touches and falls back to a comment-preserving sed/awk edit when jq
can't parse the file directly (typical of a hand-edited settings.json
with // comments), instead of silently failing on any file with
comments.
EOF
)"
```

---

### Task 2: Native Windows-side Code/Cursor settings sync

**Files:**
- Modify: `themes/set-vscode-theme.sh`
- Test: `tests/theme_vscode_windows_test.bats` (new)

**Interfaces:**
- Consumes: `omawsl_windows_userprofile` (from `install/lib.sh`, already sourced by
  `themes/set-vscode-theme.sh` — prints the Windows user profile dir as a WSL path, e.g.
  `/mnt/c/Users/<name>`, or fails/returns 1 with no output).
- Consumes: `omawsl_theme_set_vscode_settings <settings_file> <color_theme>` (Task 1, unchanged
  signature).
- Modifies: `omawsl_theme_apply_vscode <color_theme> <extension_id>` — now also syncs the two
  native paths when the Windows profile resolves.

- [ ] **Step 1: Write the failing tests**

Create `tests/theme_vscode_windows_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  WINHOME="$BATS_TEST_TMPDIR/winhome"
  mkdir -p "$WINHOME"

  cmd.exe() {
    if [[ "$*" == *USERPROFILE* ]]; then
      printf 'C:\\Users\\testuser\r\n'
    fi
  }
  export -f cmd.exe

  wslpath() {
    echo "$WINHOME"
  }
  export -f wslpath

  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/themes/set-vscode-theme.sh"
  command -v jq &>/dev/null || skip "jq not installed on this test host"
}

@test "omawsl_theme_apply_vscode patches the native Windows Code and Cursor settings.json when they exist" {
  local code_dir="$WINHOME/AppData/Roaming/Code/User"
  local cursor_dir="$WINHOME/AppData/Roaming/Cursor/User"
  mkdir -p "$code_dir" "$cursor_dir"
  echo '{"editor.fontSize": 14}' > "$code_dir/settings.json"
  echo '{"editor.fontSize": 14}' > "$cursor_dir/settings.json"

  run omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$code_dir/settings.json")" == "Tokyo Night" ]]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$cursor_dir/settings.json")" == "Tokyo Night" ]]
  [ -f "$code_dir/settings.json.bak" ]
  [ -f "$cursor_dir/settings.json.bak" ]
}

@test "omawsl_theme_apply_vscode preserves comments in a native settings.json with JSONC content" {
  local code_dir="$WINHOME/AppData/Roaming/Code/User"
  mkdir -p "$code_dir"
  cat > "$code_dir/settings.json" <<'EOF'
{
  // native user settings
  "editor.fontSize": 14
}
EOF

  run omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
  [ "$status" -eq 0 ]
  grep -qF '// native user settings' "$code_dir/settings.json"
  [[ "$(omawsl_strip_jsonc_comments "$code_dir/settings.json" | jq -r '.["workbench.colorTheme"]')" == "Tokyo Night" ]]
}

@test "omawsl_theme_apply_vscode skips the native sync when neither native settings.json exists" {
  run omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
  [ "$status" -eq 0 ]
  [ ! -d "$WINHOME/AppData/Roaming/Code" ]
  [ ! -d "$WINHOME/AppData/Roaming/Cursor" ]
}

@test "omawsl_theme_apply_vscode skips the native sync entirely when the Windows profile can't be resolved, but still syncs Remote-WSL settings" {
  unset -f cmd.exe
  mkdir -p "$HOME/.vscode-server/data/Machine"
  cp "$REPO_ROOT/configs/vscode.json" "$HOME/.vscode-server/data/Machine/settings.json"

  run omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$HOME/.vscode-server/data/Machine/settings.json")" == "Tokyo Night" ]]
}
```

- [ ] **Step 2: Run the new tests to verify they fail**

```bash
wsl -d Ubuntu -- bash -lc "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && ./tests/.bats-core/bin/bats tests/theme_vscode_windows_test.bats"
```

Expected: all 4 tests fail (native paths not synced yet — `workbench.colorTheme` stays absent).

- [ ] **Step 3: Add the native-path sync to `omawsl_theme_apply_vscode`**

In `themes/set-vscode-theme.sh`, replace the body of `omawsl_theme_apply_vscode` (written in
Task 1 Step 4) with:

```bash
omawsl_theme_apply_vscode() {
  local color_theme="$1" extension_id="$2"

  omawsl_theme_set_vscode_settings "$HOME/.vscode-server/data/Machine/settings.json" "$color_theme"
  omawsl_theme_set_vscode_settings "$HOME/.cursor-server/data/Machine/settings.json" "$color_theme"

  local profile
  if profile="$(omawsl_windows_userprofile)"; then
    omawsl_theme_set_vscode_settings "$profile/AppData/Roaming/Code/User/settings.json" "$color_theme"
    omawsl_theme_set_vscode_settings "$profile/AppData/Roaming/Cursor/User/settings.json" "$color_theme"
  fi

  if omawsl_code_reachable; then
    NODE_NO_WARNINGS=1 code --install-extension "$extension_id" >/dev/null
  fi
}
```

Also update its doc comment (directly above the function) to mention the native sync — replace
the existing comment block with:

```bash
# omawsl_theme_apply_vscode <color_theme> <extension_id>
# Applies the theme to VS Code's and Cursor's Remote-WSL settings.json
# (whichever exist) and, if a Windows profile can be resolved via
# omawsl_windows_userprofile, to their native Windows-side
# settings.json too (design spec "Sync theme to native Windows-side VS
# Code/Cursor" - Cursor reads the same workbench.colorTheme key and
# shares this same step). Silently skips the native sync if the
# profile can't be resolved (e.g. not real WSL2) - the Remote-WSL sync
# and extension install below are unaffected either way. Installs the
# VS Code extension via `code --install-extension` only when `code` is
# reachable - matches app-vscode.sh's own detect-and-defer shape
# (Phase 4). Deliberately does NOT attempt `cursor --install-extension`,
# same reasoning as app-cursor.sh (Phase 4): Cursor has its own
# extension distribution and commonly blocks Microsoft-published
# extensions from its marketplace, so this only touches what's clearly
# specified (shared settings keys).
```

- [ ] **Step 4: Run both test files to verify everything passes**

```bash
wsl -d Ubuntu -- bash -lc "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && ./tests/.bats-core/bin/bats tests/theme_vscode_test.bats tests/theme_vscode_windows_test.bats"
```

Expected: `1..13`, all `ok` (9 from Task 1's file + 4 new).

- [ ] **Step 5: Commit**

```bash
git add themes/set-vscode-theme.sh tests/theme_vscode_windows_test.bats
git commit -m "$(cat <<'EOF'
feat: sync theme to native Windows-side VS Code and Cursor

bin/omawsl theme now also patches the real
%APPDATA%\Code\User\settings.json and
%APPDATA%\Cursor\User\settings.json on Windows, alongside the existing
Remote-WSL settings.json sync - so the desktop app itself picks up the
theme, not just a Remote-WSL session. Resolved via the same
Windows-profile helper Windows Terminal theme sync already uses;
skips gracefully if the profile can't be resolved or the native
settings.json doesn't exist yet.
EOF
)"
```

---

### Task 3: Docs

**Files:**
- Modify: `docs/windows-setup.md`
- Modify: `tests/docs_windows_setup_test.bats`

**Interfaces:**
- None (documentation + doc-lint test only).

- [ ] **Step 1: Write the failing test changes**

In `tests/docs_windows_setup_test.bats`:

1. Add `"## VS Code and Cursor theme"` to the heading list in the
   `"docs/windows-setup.md has every heading the shipped code already links to"` test, so it
   reads:

```bash
@test "docs/windows-setup.md has every heading the shipped code already links to" {
  for heading in "## Windows Terminal" "## Fonts" "## Docker Desktop" "## VS Code" "## Cursor" "## GitHub Copilot CLI" "## Windows Terminal theme" "## VS Code and Cursor theme"; do
    grep -qF "$heading" "$DOC" || { echo "missing heading: $heading"; return 1; }
  done
}
```

2. Add `"$REPO_ROOT/themes"` to the directories scanned in the
   `"every anchor already hardcoded in shipped code has a matching explicit <a id> in this doc"`
   test (its skip messages now live partly in `themes/set-vscode-theme.sh`, not just
   `install/` and `bin/`), so the `grep -rhoE` line reads:

```bash
  grep -rhoE 'docs/windows-setup\.md#[a-z0-9-]+' "$REPO_ROOT/install" "$REPO_ROOT/bin" "$REPO_ROOT/themes" | sed 's/.*#//' | sort -u > "$BATS_TEST_TMPDIR/wanted_anchors"
```

- [ ] **Step 2: Run the doc tests to verify they fail**

```bash
wsl -d Ubuntu -- bash -lc "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && ./tests/.bats-core/bin/bats tests/docs_windows_setup_test.bats"
```

Expected: the heading test fails (`missing heading: ## VS Code and Cursor theme`) and the anchor
test fails (`doc missing <a id="vscode-theme">`).

- [ ] **Step 3: Update the quick-reference table**

In `docs/windows-setup.md`, replace this line:

```
| After running `bin/omawsl theme` | Nothing - the color sync happens automatically | [#windows-terminal-theme](#windows-terminal-theme) |
```

with these two:

```
| After running `bin/omawsl theme` (Windows Terminal) | Nothing - the color sync happens automatically | [#windows-terminal-theme](#windows-terminal-theme) |
| After running `bin/omawsl theme` (VS Code / Cursor, if installed natively on Windows) | Nothing - the color sync happens automatically | [#vscode-theme](#vscode-theme) |
```

- [ ] **Step 4: Add the new section**

In `docs/windows-setup.md`, immediately after the `## Windows Terminal theme` section and before
`## Clipboard and GUI apps`, insert:

```markdown
<a id="vscode-theme"></a>
## VS Code and Cursor theme

Also automatic, the same way the Windows Terminal color sync above is: `bin/omawsl theme <name>`
edits the real native settings.json for VS Code and Cursor if they're installed on Windows -
`%APPDATA%\Code\User\settings.json` and `%APPDATA%\Cursor\User\settings.json` - setting
`"workbench.colorTheme"` to the theme's name. This is on top of (not instead of) the existing
Remote-WSL settings sync, so both a Remote-WSL session and the native app end up themed.

It always backs up each file first (`settings.json.bak`) and skips gracefully - printing this
same pointer instead of failing - if `jq` isn't available, the file can't be found, or its
contents can't be confidently parsed (this includes some JSONC comment styles it doesn't handle,
like multi-line `/* */` blocks). Nothing to do here by hand unless that skip message shows up, in
which case set `"workbench.colorTheme"` to the theme's Title Case name (e.g. `"Tokyo Night"`) in
the relevant settings.json yourself.
```

- [ ] **Step 5: Run the doc tests again to verify they pass**

```bash
wsl -d Ubuntu -- bash -lc "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && ./tests/.bats-core/bin/bats tests/docs_windows_setup_test.bats"
```

Expected: `1..5`, all `ok`.

- [ ] **Step 6: Commit**

```bash
git add docs/windows-setup.md tests/docs_windows_setup_test.bats
git commit -m "$(cat <<'EOF'
docs: document native VS Code/Cursor theme sync

Adds the #vscode-theme section docs/windows-setup.md's own code
pointers already require, and extends the doc-lint test's scanned
directories to cover themes/ now that it also emits a
docs/windows-setup.md pointer.
EOF
)"
```

---

### Task 4: Full regression pass

**Files:** none (verification only).

- [ ] **Step 1: Re-run every test file this plan touched, together**

Per **Global Constraints**, do not broaden this to `tests/*.bats` — `tests/omawsl_cli_test.bats`
has a pre-existing gap (unrelated to this plan) that can write to the user's real Windows-side
settings files in this real WSL2 environment.

```bash
wsl -d Ubuntu -- bash -lc "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && ./tests/.bats-core/bin/bats tests/theme_vscode_test.bats tests/theme_vscode_windows_test.bats tests/docs_windows_setup_test.bats tests/windows_terminal_test.bats"
```

Expected: every test passes except the one pre-existing, unrelated failure called out in
**Global Constraints** above (`omawsl_windows_userprofile fails cleanly when cmd.exe isn't
reachable`). If any *other* test fails, stop and investigate before proceeding — don't assume
it's unrelated.

- [ ] **Step 2: Manually exercise a real theme switch (human verification)**

This step needs a real interactive terminal in the actual WSL2 environment with VS Code and/or
Cursor installed on Windows and a native `settings.json` already present (with or without
comments) — flag it back to the user rather than attempting it programmatically:

1. Open VS Code or Cursor natively on Windows (not via Remote-WSL) at least once, so its
   `settings.json` exists.
2. From a WSL terminal in this omawsl checkout, run `bin/omawsl theme "Tokyo Night"` (or any
   other theme name).
3. Confirm the already-open native VS Code/Cursor window's color theme changes (may need a
   reload/restart to pick up the settings.json change, same as any external settings.json edit).
4. If the user has a hand-edited `settings.json` with `//` comments, confirm those comments are
   still present afterward.
