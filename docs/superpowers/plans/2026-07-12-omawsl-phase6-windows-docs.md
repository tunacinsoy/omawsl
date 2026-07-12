# Phase 6 (Windows-side deliverables + README) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the Windows-side half of omawsl that's been documented-but-missing since Phase 1: `docs/windows-setup.md` (the one canonical walkthrough every detect-and-defer script and the pre-install checklist already points at), the `windows/` asset tree (font profile fragments with the zellij keybinding fix baked in, a font-source pointer, an optional winget helper script), and `README.md` (exclusions list + "Before you begin"). Also discharge two accumulated obligations flagged by earlier phases: fold in and delete `docs/prerequisites.md` (Phase 4's interim stopgap) and `docs/zellij-keybinding-fixes.md` (Phase 5's interim stopgap), updating the one dangling code reference to the first.

**Architecture:** This phase is almost entirely documentation and static assets, not new bash logic — no new `install/terminal/*.sh` script, no new `install.sh` orchestration step. The only "code" changes are: (1) two ready-made Windows Terminal settings-fragment JSON files under `windows/`, meant to be manually merged by the user per the doc (never auto-applied — `bin/omawsl theme`'s automatic `settings.json` edit, built in Phase 5, only ever touches the `schemes`/`colorScheme` keys, never `font`/`actions`, so there's no collision between the two mechanisms); (2) one one-line reference fix in `install/terminal/app-gh-copilot.sh` (and its test) now that `docs/prerequisites.md` is being folded in and deleted. Everything else is new markdown/JSON/PowerShell content, verified with bats tests that check file existence, JSON validity, and required content/anchors rather than bash behavior.

**Tech Stack:** Markdown, JSON, PowerShell (`windows/setup.ps1`, never invoked by any bash script), `jq` (for JSON-validity tests, already a project dependency since Phase 5), bats-core (already vendored per-worktree).

## Global Constraints

- Windows-side pieces remain **docs + ready-made files, manual apply only** (design spec §2, §13) — nothing this phase adds is ever invoked automatically by `install.sh`/`boot.sh`. `windows/setup.ps1` in particular must never be sourced, curl-piped, or shelled out to from any `.sh` file in this repo.
- `docs/windows-setup.md` is the **single canonical source** for "what do I do on the Windows side" — every pointer elsewhere in the tool (the pre-install checklist, each `app-*.sh`'s detect-and-defer message, `install.sh`'s final summary) links into it rather than restating or paraphrasing its steps (design spec §16).
- The quick-reference table lives in exactly one place (`docs/windows-setup.md`, opening section) and `README.md`'s "Before you begin" section **references it, never copies it** (design spec §16) — two copies of the same table drifting out of sync is exactly what the spec is guarding against.
- Anchor strings referenced by existing code (`docs/windows-setup.md#docker-desktop`, `#vscode`, `#cursor`, `#windows-terminal-theme`) are already hardcoded into shipped, tested code (`install/windows-prereq-checklist.sh`, `install/terminal/docker.sh`, `install/terminal/app-vscode.sh`, `install/terminal/app-cursor.sh`, `bin/omawsl-sub/windows-terminal.sh`) and must not be renamed. **Don't rely on GitHub's auto-generated heading slugs to satisfy them** — `## VS Code` auto-slugs to `#vs-code` (the space becomes a hyphen), not `#vscode`, which would silently break that link once this repo has a GitHub remote (Phase 7). Every section this task adds gets an explicit `<a id="...">` anchor immediately above its heading instead, so the anchor string is exact and independent of however the heading text reads.
- **Out of scope, deliberately:** design spec §5.7 asks `install.sh`'s final summary to "explicitly list every step that was skipped/deferred" — right now each `app-*.sh`/`docker.sh` only prints its own inline deferred-message mid-run (Phases 2-4), with no end-of-run aggregation. This phase does not add that aggregation: design spec §14 already assigns the better-suited, persistent version of this exact job to `bin/omawsl doctor` ("surfaced here every time `doctor` runs — not just once in the original install's scrollback"), which is Phase 7 scope. Building a one-shot final-summary list now would be redundant with what Phase 7 builds properly. Noted here so it isn't mistaken for something Phase 6 forgot.
- No file this plan deletes (`docs/prerequisites.md`, `docs/zellij-keybinding-fixes.md`) may leave a dangling reference anywhere in currently-shipped code or tests — grep the whole repo (excluding historical `docs/superpowers/plans/*.md`, which are a record of what happened and are never edited retroactively) before considering a deletion task done.

## Research (verified against real upstream sources — see citations below)

1. **Omakub's own font install (`install/desktop/fonts.sh`, fetched from `github.com/basecamp/omakub` `master`) does not vendor font binaries into its git repo either** — it downloads `https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip` fresh at install time. Since omawsl already treats every Windows-side step as manual/doc-only (never an automated download), this phase follows the same precedent by *documenting* that exact upstream URL rather than committing a binary font file to the repo — consistent with §7's own note that `windows/` is "documentation and optional assets only."
2. **The correct font family name is `CaskaydiaMono Nerd Font Mono`, not `Cascadia Mono` or `CascadiaMono Nerd Font`.** Confirmed from `ryanoasis/nerd-fonts`'s own `patched-fonts/CascadiaMono/README.md`: Nerd Fonts renames patched fonts to avoid SIL Reserved Font Name conflicts (`Cascadia Mono` → `CaskaydiaMono`), and the `Nerd Font Mono` (not plain `Nerd Font`) suffix is the fixed-width-glyph variant recommended for terminal use (the plain `Nerd Font` variant's icons are ~1.5 cells wide and can misalign monospace grids). The zero-install fallback profile uses the terminal's actual bundled font name, `Cascadia Mono` (confirmed already present as Windows Terminal's shipped default, no install needed).
3. **The zellij/Windows Terminal keybinding collision and its fix are already real-machine-verified**, not a fresh finding — Phase 5's Task 9 (per project memory) applied the `"command": "unbound"` snippet from `docs/zellij-keybinding-fixes.md` to a real Windows Terminal `settings.json` and confirmed `Alt+Left/Down/Up/Right` reached zellij afterward, through a live Windows Terminal + zellij session. `docs/zellij-keybinding-fixes.md`'s own text was never updated post-verification to drop its "not yet verified" hedge (a doc-staleness gap this phase's Task 5 also closes) — Task 1 below writes the confirmed-working form directly into `windows/windows-terminal.json`/`windows-terminal-fallback.json` without re-hedging.
4. **Windows Terminal's real settings.json schema** (cross-referenced against `bin/omawsl-sub/windows-terminal.sh`, built in Phase 5, which already edits `profiles.defaults.colorScheme` and reads/writes real `settings.json` files on this project's own real Windows Terminal installs) uses `profiles.defaults.font.face` for the default font across every profile, and a top-level `actions` array (each entry `{ "command": ..., "keys": ... }`) for keybindings — the modern schema Windows Terminal has used since replacing the older `keybindings`/`command`-string form. `"command": "unbound"` is the documented mechanism to clear a default binding without needing to know its original command name.
5. **No new `OMAWSL_*` env var, first-run prompt, or `install/terminal/*.sh` script is needed for this phase** — confirmed by re-reading design spec §13 and roadmap.md's Phase 6 entry: every deliverable here is either a doc, a static asset, or a one-line reference-string fix in already-shipped code.

---

### Task 1: `windows/windows-terminal.json` and `windows/windows-terminal-fallback.json`

**Files:**
- Create: `windows/windows-terminal.json`
- Create: `windows/windows-terminal-fallback.json`
- Test: `tests/windows_assets_test.bats`

**Interfaces:**
- Produces: two standalone JSON fragments, each containing `profiles.defaults.font.face` and a top-level `actions` array unbinding `alt+left`/`alt+down`/`alt+up`/`alt+right`. Consumed only by a human manually merging them into their own `%LOCALAPPDATA%\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json` (or the unpackaged path) per `docs/windows-setup.md`'s `#fonts` section (Task 3) — never read by any bash script. Distinct from `themes/<name>/windows-terminal-scheme.json` (Phase 5, only `schemes`/color keys, applied automatically by `bin/omawsl theme`).
- Consumes: nothing new.

- [ ] **Step 1: Write `windows/windows-terminal.json`** (Nerd Font / enhanced option)

```json
{
    "profiles": {
        "defaults": {
            "font": {
                "face": "CaskaydiaMono Nerd Font Mono"
            }
        }
    },
    "actions": [
        { "command": "unbound", "keys": "alt+left" },
        { "command": "unbound", "keys": "alt+down" },
        { "command": "unbound", "keys": "alt+up" },
        { "command": "unbound", "keys": "alt+right" }
    ]
}
```

- [ ] **Step 2: Write `windows/windows-terminal-fallback.json`** (Cascadia Mono / zero-install option) — identical keybinding fix, only the font name differs, per design spec §13's requirement that both files resolve the collision identically regardless of font choice:

```json
{
    "profiles": {
        "defaults": {
            "font": {
                "face": "Cascadia Mono"
            }
        }
    },
    "actions": [
        { "command": "unbound", "keys": "alt+left" },
        { "command": "unbound", "keys": "alt+down" },
        { "command": "unbound", "keys": "alt+up" },
        { "command": "unbound", "keys": "alt+right" }
    ]
}
```

- [ ] **Step 3: Write `tests/windows_assets_test.bats`**

```bats
#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "windows-terminal.json and windows-terminal-fallback.json are both valid JSON" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  for f in windows-terminal.json windows-terminal-fallback.json; do
    run jq empty "$REPO_ROOT/windows/$f"
    [ "$status" -eq 0 ]
  done
}

@test "windows-terminal.json uses the Nerd Font Mono family name" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  [[ "$(jq -r '.profiles.defaults.font.face' "$REPO_ROOT/windows/windows-terminal.json")" == "CaskaydiaMono Nerd Font Mono" ]]
}

@test "windows-terminal-fallback.json uses the bundled Cascadia Mono family name" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  [[ "$(jq -r '.profiles.defaults.font.face' "$REPO_ROOT/windows/windows-terminal-fallback.json")" == "Cascadia Mono" ]]
}

@test "both windows-terminal json fragments unbind all four Alt+arrow chords identically" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  for f in windows-terminal.json windows-terminal-fallback.json; do
    local keys
    keys="$(jq -r '[.actions[] | select(.command == "unbound") | .keys] | sort | join(",")' "$REPO_ROOT/windows/$f")"
    [[ "$keys" == "alt+down,alt+left,alt+right,alt+up" ]]
  done
}
```

- [ ] **Step 4: Run the new test file**

Run: `wsl.exe -d Ubuntu -- bash -c "bash '/mnt/c/path/to/repo/tests/.bats-core/bin/bats' '/mnt/c/path/to/repo/tests/windows_assets_test.bats'"` (adjust the repo path; see project memory's multi-layer-quoting lesson — write any throwaway wrapper as a real `.sh` file, don't inline `-c` quoting).
Expected: all 4 tests pass (or skip cleanly if `jq` isn't on the test host's PATH).

- [ ] **Step 5: Commit**

```bash
git add windows/windows-terminal.json windows/windows-terminal-fallback.json tests/windows_assets_test.bats
git commit -m "feat: add Windows Terminal font+keybinding-fix profile fragments"
```

---

### Task 2: `windows/fonts/README.md` and `windows/setup.ps1`

**Files:**
- Create: `windows/fonts/README.md`
- Create: `windows/setup.ps1`
- Modify: `tests/windows_assets_test.bats`

**Interfaces:**
- Produces: a doc-only pointer to the upstream Nerd Font release (no binary vendored — see Research #1), and an optional PowerShell helper never invoked by any bash script.
- Consumes: nothing new.

- [ ] **Step 1: Write `windows/fonts/README.md`**

```markdown
# Fonts

This directory intentionally contains no font binaries — see `docs/windows-setup.md#fonts`
for the two documented options.

If you want the Nerd Font (enhanced) option, download it directly from the same upstream
release Omakub's own font installer uses:

https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip

Unzip it and install every `.ttf` inside (right-click → Install, no admin rights needed in
the common case). The font family name after installing is **`CaskaydiaMono Nerd Font Mono`**
(not `Cascadia Mono` — Nerd Fonts renames patched fonts to avoid a font-license naming
conflict), which is exactly what `../windows-terminal.json` sets as the profile's font face.

If you'd rather not install anything, use the zero-install fallback instead: merge
`../windows-terminal-fallback.json`, which points at `Cascadia Mono`, the font Windows
Terminal already ships with. See `docs/windows-setup.md#fonts` for the full comparison.
```

- [ ] **Step 2: Write `windows/setup.ps1`**

```powershell
<#
.SYNOPSIS
  Optional helper for the winget-installable pieces of omawsl's Windows-side setup.

.DESCRIPTION
  This script is NEVER invoked automatically by boot.sh or install.sh - omawsl's own rule
  (design spec Sections 2 and 13) is that nothing on the Windows side gets installed without
  the user explicitly choosing to. Read this script before running it, the same way you'd
  read any script before piping it into your shell.

  It installs Windows Terminal (if winget can find it - it's usually preinstalled on
  Windows 11) and the Nerd Font used by windows-terminal.json's "enhanced" profile, then
  prints the one manual step this script does NOT do for you: merging windows-terminal.json
  (or windows-terminal-fallback.json, if you skip the font) into your own settings.json.
  See docs/windows-setup.md for that step and everything else covered in this repo.

.NOTES
  Requires winget (bundled with Windows 11 App Installer). On a corporate machine where
  winget itself is blocked or Windows software installs require an IT ticket, skip this
  script entirely and follow docs/windows-setup.md by hand instead - that path needs no
  elevated rights beyond what a normal user already has for a per-user font install.
#>

param(
    [switch]$SkipFont
)

$ErrorActionPreference = "Stop"

function Test-WingetAvailable {
    return [bool](Get-Command winget -ErrorAction SilentlyContinue)
}

function Install-WindowsTerminal {
    Write-Host "Checking for Windows Terminal..."
    $installed = winget list --id Microsoft.WindowsTerminal --source winget 2>$null | Select-String "Microsoft.WindowsTerminal"
    if ($installed) {
        Write-Host "Windows Terminal is already installed."
        return
    }
    Write-Host "Installing Windows Terminal via winget..."
    winget install --id Microsoft.WindowsTerminal --source winget --accept-package-agreements --accept-source-agreements
}

function Install-NerdFont {
    $zipUrl = "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip"
    $tempDir = Join-Path $env:TEMP "omawsl-cascadia-nerd-font"
    $zipPath = Join-Path $env:TEMP "omawsl-cascadia-nerd-font.zip"

    Write-Host "Downloading CaskaydiaMono Nerd Font from $zipUrl ..."
    Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

    Write-Host "Extracting..."
    if (Test-Path $tempDir) { Remove-Item -Recurse -Force $tempDir }
    Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

    # Per-user font install: no admin rights needed, matches docs/windows-setup.md's
    # "right-click -> Install, no admin needed" framing for the manual path.
    $fontsFolder = (New-Object -ComObject Shell.Application).Namespace(0x14)
    $ttfFiles = Get-ChildItem -Path $tempDir -Filter "*.ttf" -Recurse
    foreach ($font in $ttfFiles) {
        Write-Host "Installing $($font.Name)..."
        $fontsFolder.CopyHere($font.FullName, 0x10)
    }

    Remove-Item -Force $zipPath
    Remove-Item -Recurse -Force $tempDir
    Write-Host "Font install complete. Family name: CaskaydiaMono Nerd Font Mono"
}

if (-not (Test-WingetAvailable)) {
    Write-Error "winget isn't available on this machine. Follow docs/windows-setup.md by hand instead."
    exit 1
}

Install-WindowsTerminal

if (-not $SkipFont) {
    Install-NerdFont
} else {
    Write-Host "Skipping font install (-SkipFont). Use windows-terminal-fallback.json instead of windows-terminal.json."
}

Write-Host ""
Write-Host "Done. One manual step left: merge windows-terminal.json (or windows-terminal-fallback.json"
Write-Host "if you used -SkipFont) into your Windows Terminal settings.json - see docs/windows-setup.md#fonts."
```

- [ ] **Step 3: Add asset-hygiene tests to `tests/windows_assets_test.bats`**

```bats
@test "windows/fonts/README.md points at the real upstream nerd-fonts release URL" {
  grep -q "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip" "$REPO_ROOT/windows/fonts/README.md"
}

@test "windows/fonts/ has no vendored font binaries" {
  ! find "$REPO_ROOT/windows/fonts" -iname "*.ttf" -o -iname "*.otf" | grep -q .
}

@test "windows/setup.ps1 is never sourced or invoked by any .sh file in the repo" {
  ! grep -rl "setup\.ps1" "$REPO_ROOT" --include="*.sh" | grep -q .
}
```

- [ ] **Step 4: Run the updated test file**

Run: same bats invocation pattern as Task 1, Step 4, against the whole file.
Expected: all tests pass (or skip cleanly for the jq-dependent ones).

- [ ] **Step 5: Commit**

```bash
git add windows/fonts/README.md windows/setup.ps1 tests/windows_assets_test.bats
git commit -m "feat: add font source doc and optional winget setup helper"
```

---

### Task 3: `docs/windows-setup.md`

**Files:**
- Create: `docs/windows-setup.md`
- Test: `tests/docs_windows_setup_test.bats`

**Interfaces:**
- Produces: the canonical doc every existing pointer in the codebase already targets (`docs/windows-setup.md#docker-desktop`, `#vscode`, `#cursor`, `#windows-terminal-theme`, plus this task's own new `#windows-terminal`, `#fonts`, `#github-copilot-cli`), and the quick-reference table `README.md` (Task 6) links into rather than duplicates.
- Consumes: content folded in from `docs/prerequisites.md` (GitHub Copilot CLI, VS Code/Cursor proactive-install framing) and `docs/zellij-keybinding-fixes.md` (the keybinding collision writeup), both deleted in Tasks 4-5.

- [ ] **Step 1: Write `docs/windows-setup.md`**

(Note: this content contains nested ` ```bash ` fences of its own, so it's wrapped below in a 4-backtick fence purely for this plan document's own rendering — write the file's actual content starting from `# Windows-side setup`, using ordinary 3-backtick fences for its own `bash` blocks, not the 4-backtick wrapper.)

````markdown
# Windows-side setup

omawsl never installs anything on the Windows side automatically - Windows software installs
can require an IT ticket on a locked-down corporate machine, and a local JSON edit is a very
different risk profile than a network install. This doc is the one place all of that manual
setup lives; every "you'll need to do something on Windows" message elsewhere in omawsl (the
pre-install checklist, an editor's detect-and-defer message, `bin/omawsl doctor`) links back
here instead of repeating these steps.

## Quick reference

| If you picked... | You'll need | Steps |
|---|---|---|
| (always) Windows Terminal itself | Install it, set the WSL profile as default | [#windows-terminal](#windows-terminal) |
| (always) A readable font with icon glyphs | Pick Nerd Font (enhanced) or Cascadia Mono (zero-install) | [#fonts](#fonts) |
| Docker backend: Docker Desktop for Windows | Install Docker Desktop, enable WSL integration | [#docker-desktop](#docker-desktop) |
| Editors & AI tooling: VS Code | Install VS Code, enable the WSL extension | [#vscode](#vscode) |
| Editors & AI tooling: Cursor | Install Cursor, connect to this WSL distro once | [#cursor](#cursor) |
| Editors & AI tooling: GitHub Copilot CLI | Run `gh auth login` before `install.sh` | [#github-copilot-cli](#github-copilot-cli) |
| After running `bin/omawsl theme` | Nothing - the color sync happens automatically | [#windows-terminal-theme](#windows-terminal-theme) |

<a id="windows-terminal"></a>
## Windows Terminal

1. Install Windows Terminal from the Microsoft Store. If Store access is blocked on a
   corporate machine, ask your IT team to install it (or provide the winget/MSIX package) -
   there's no way around a genuine software-install restriction from inside WSL.
2. Open Windows Terminal's Settings (`Ctrl+,`), and under **Startup**, set **Default profile**
   to your WSL distro (usually named "Ubuntu"). This makes new tabs/windows open straight into
   WSL instead of PowerShell.

<a id="fonts"></a>
## Fonts

Two complete options - pick based on your own machine's restrictions, not a "correct" answer:

- **Nerd Font (enhanced).** Full icon-glyph rendering: fastfetch's logo, file-type icons,
  powerline-style separators all render as intended. See `windows/fonts/README.md` for where
  to download it (not vendored in this repo - see that file for why) and its exact font family
  name. Once installed, merge `windows/windows-terminal.json` into your Windows Terminal
  `settings.json` (open Settings, click "Open JSON file", merge the `profiles.defaults` and
  `actions` keys from that file into your own - don't just paste over the whole file).
- **Cascadia Mono (zero install).** Nothing to install - Cascadia Mono ships bundled with
  Windows Terminal already. Merge `windows/windows-terminal-fallback.json` instead, the same
  way. Some icon glyphs render as boxes/tofu instead of icons; everything else (text, colors,
  layout) is fully readable and functional. This trade-off is real, not a bug to report.

**Both files also fix a real keybinding collision, not just the font.** Omakub's zellij
keybindings (`configs/zellij.kdl`) bind `Alt+Left/Down/Up/Right` for pane focus - the same four
chords Windows Terminal binds by default for moving focus between *its own* split panes. Since
Windows Terminal owns the keystroke first, it swallows these four chords before zellij (running
inside it) ever sees them. Both JSON files unbind Windows Terminal's default so the keystroke
passes through to zellij - confirmed working on a real Windows Terminal + zellij session (every
other zellij binding was checked too and has no collision). This is independent of which font
option you pick, so it's included in both files identically.

<a id="docker-desktop"></a>
## Docker Desktop

Only needed if you chose "Docker Desktop for Windows" at the first-run picker instead of the
default Engine-only option.

1. Install Docker Desktop from https://www.docker.com/products/docker-desktop/ (Store access
   isn't required for this one - it's a direct installer). On a corporate machine, check
   whether your org already has a license before installing; Docker Desktop's free tier has
   company-size limits that Engine-only (the default) doesn't.
2. In Docker Desktop's Settings → Resources → WSL Integration, enable integration for this
   distro specifically.
3. Back in your WSL terminal, confirm it worked: `docker ps` should return an (possibly empty)
   table, not a "command not found" or connection error.

<a id="vscode"></a>
## VS Code

1. Install VS Code from https://code.visualstudio.com/ (Store, or the direct installer - both
   work; ask IT if Windows software installs are locked down).
2. Install the "WSL" extension (`ms-vscode-remote.remote-wsl`) from the Extensions view, or let
   `install.sh` install it for you automatically once `code` is reachable.
3. Open a folder from inside WSL with `code .` to connect for the first time, or use the
   Remote-WSL "Connect to WSL" command from VS Code's command palette on Windows.
4. Verify: `code --version` from your WSL terminal should print a version, not
   "command not found".

If you run `install.sh` before doing this, nothing fails - the shared settings file still
deploys (it's inert until VS Code connects), and only the one step needing the live `code` CLI
is skipped, with a reminder to come back to it.

<a id="cursor"></a>
## Cursor

1. Install Cursor from https://cursor.com/ on Windows.
2. Connect it to this WSL distro once, the same way you'd connect VS Code (Cursor is a VS Code
   fork and uses the same Remote-WSL-style connection flow).
3. Verify: `cursor --version` from your WSL terminal should print a version.

Cursor shares the same baseline `configs/vscode.json` settings VS Code gets - deployed
automatically regardless of whether `cursor` is reachable yet. Unlike VS Code, omawsl doesn't
attempt an extension install for Cursor: Cursor has its own extension distribution, and
Microsoft's marketplace commonly blocks non-VS-Code products from installing
Microsoft-published extensions, so this repo only deploys what's clearly specified.

<a id="github-copilot-cli"></a>
## GitHub Copilot CLI

Installing GitHub Copilot CLI runs `gh extension install github/gh-copilot`, which needs an
authenticated `gh` session - something a fresh machine doesn't have yet. If you're going to
pick "GitHub Copilot CLI" in the Editors & AI tooling picker, run this **before** `install.sh`:

```bash
gh auth login
```

If you skip this and pick it anyway, nothing else in `install.sh` is affected - the failure is
isolated and reported, not fatal to the rest of the run - but the extension itself won't
install until you run `gh auth login` yourself and then either
`gh extension install github/gh-copilot` or re-run `install.sh`.

<a id="windows-terminal-theme"></a>
## Windows Terminal theme

Unlike everything else on this page, this one **is** automatic: `bin/omawsl theme <name>`
edits your real Windows Terminal `settings.json` directly (the one exception to "omawsl never
touches Windows-side files automatically" - it's a local JSON edit to an already-installed app,
no network call, no admin rights). It always backs up `settings.json` first
(`settings.json.bak`) and skips gracefully - printing this same pointer instead of failing -
if `jq` isn't available or `settings.json` can't be found or parsed. Nothing to do here by
hand unless that skip message shows up, in which case merge the theme's
`themes/<name>/windows-terminal-scheme.json` into your `schemes` array yourself and set it as
`profiles.defaults.colorScheme`.

## Clipboard and GUI apps

No setup needed here - WSL2 + WSLg handle clipboard sharing and Linux GUI app interop with
Windows automatically on Windows 11.
````

- [ ] **Step 2: Write `tests/docs_windows_setup_test.bats`**

```bats
#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DOC="$REPO_ROOT/docs/windows-setup.md"

@test "docs/windows-setup.md exists" {
  [ -f "$DOC" ]
}

@test "docs/windows-setup.md has every heading the shipped code already links to" {
  for heading in "## Windows Terminal" "## Fonts" "## Docker Desktop" "## VS Code" "## Cursor" "## GitHub Copilot CLI" "## Windows Terminal theme"; do
    grep -qF "$heading" "$DOC" || { echo "missing heading: $heading"; return 1; }
  done
}

@test "docs/windows-setup.md opens with a quick-reference table before any numbered section" {
  local table_line section_line
  table_line="$(grep -n '^## Quick reference' "$DOC" | head -1 | cut -d: -f1)"
  section_line="$(grep -n '^## Windows Terminal$' "$DOC" | head -1 | cut -d: -f1)"
  [ -n "$table_line" ]
  [ -n "$section_line" ]
  [ "$table_line" -lt "$section_line" ]
}

@test "docs/windows-setup.md references both windows-terminal json fragments" {
  grep -q "windows/windows-terminal.json" "$DOC"
  grep -q "windows/windows-terminal-fallback.json" "$DOC"
}

@test "every anchor already hardcoded in shipped code has a matching explicit <a id> in this doc" {
  # design spec requires docs/windows-setup.md to be the single canonical target for
  # every pointer already shipped in install/*.sh and bin/omawsl-sub/*.sh. Checking the
  # literal <a id="..."> tag (not a heading-text-derived slug guess) is what actually
  # guarantees the anchor resolves, independent of how the heading text itself reads.
  grep -rhoE 'docs/windows-setup\.md#[a-z0-9-]+' "$REPO_ROOT/install" "$REPO_ROOT/bin" | sed 's/.*#//' | sort -u > "$BATS_TEST_TMPDIR/wanted_anchors"
  while read -r anchor; do
    grep -qF "<a id=\"$anchor\"></a>" "$DOC" || { echo "doc missing <a id=\"$anchor\"> for anchor referenced in code"; return 1; }
  done < "$BATS_TEST_TMPDIR/wanted_anchors"
}
```

- [ ] **Step 3: Run the new test file**

Run: same bats invocation pattern as Task 1, Step 4.
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add docs/windows-setup.md tests/docs_windows_setup_test.bats
git commit -m "docs: add the canonical Windows-side setup walkthrough"
```

---

### Task 4: Fold in and delete `docs/prerequisites.md`

**Files:**
- Delete: `docs/prerequisites.md`
- Modify: `install/terminal/app-gh-copilot.sh:33`
- Modify: `tests/app_gh_copilot_test.bats:53`

**Interfaces:**
- Consumes: `docs/windows-setup.md#github-copilot-cli` (written in Task 3) as the new pointer target.
- Produces: nothing new - this task only removes the interim file and repoints its one live reference.

- [ ] **Step 1: Update the failure message in `install/terminal/app-gh-copilot.sh`**

Change line 33 from:

```bash
    echo "See docs/prerequisites.md#github-copilot-cli for why this needs to happen before install.sh, not after."
```

to:

```bash
    echo "See docs/windows-setup.md#github-copilot-cli for why this needs to happen before install.sh, not after."
```

- [ ] **Step 2: Update the matching assertion in `tests/app_gh_copilot_test.bats`**

Change line 53 from:

```bash
  [[ "$output" == *"docs/prerequisites.md#github-copilot-cli"* ]]
```

to:

```bash
  [[ "$output" == *"docs/windows-setup.md#github-copilot-cli"* ]]
```

- [ ] **Step 3: Delete `docs/prerequisites.md`**

```bash
git rm docs/prerequisites.md
```

- [ ] **Step 4: Grep the whole repo for any remaining live reference**

Run: `grep -rn "docs/prerequisites.md" --include="*.sh" --include="*.bats" .`
Expected: no output (the only historical mentions left are inside already-committed
`docs/superpowers/plans/2026-07-09-omawsl-phase5-theming.md` and `roadmap.md`, which are a
record of what happened and are not edited retroactively).

- [ ] **Step 5: Run the updated gh-copilot test**

Run: same bats invocation pattern as Task 1, Step 4, targeting `tests/app_gh_copilot_test.bats`.
Expected: all tests pass, including the updated assertion.

- [ ] **Step 6: Commit**

```bash
git add install/terminal/app-gh-copilot.sh tests/app_gh_copilot_test.bats
git commit -m "docs: fold docs/prerequisites.md into windows-setup.md and delete it"
```

---

### Task 5: Fold in and delete `docs/zellij-keybinding-fixes.md`

**Files:**
- Delete: `docs/zellij-keybinding-fixes.md`

**Interfaces:**
- Consumes: nothing new - this task's content was already folded into `windows/windows-terminal.json`/`windows-terminal-fallback.json` (Task 1) and `docs/windows-setup.md#fonts` (Task 3).
- Produces: nothing new.

- [ ] **Step 1: Confirm the fold-in is already complete**

`windows/windows-terminal.json` and `windows/windows-terminal-fallback.json` (Task 1) both
carry the `"command": "unbound"` snippet for all four `Alt+arrow` chords, and
`docs/windows-setup.md#fonts` (Task 3) documents the collision and the fix in prose. Confirm
both are present:

```bash
grep -l '"command": "unbound"' windows/windows-terminal.json windows/windows-terminal-fallback.json
grep -q "Alt+Left/Down/Up/Right" docs/windows-setup.md
```

Expected: both commands find matches (the grep for the JSON files lists both paths; the doc
grep succeeds silently).

- [ ] **Step 2: Delete `docs/zellij-keybinding-fixes.md`**

```bash
git rm docs/zellij-keybinding-fixes.md
```

- [ ] **Step 3: Grep the whole repo for any remaining live reference**

Run: `grep -rn "docs/zellij-keybinding-fixes.md" --include="*.sh" --include="*.bats" .`
Expected: no output (same historical-plan-doc exception as Task 4, Step 4).

- [ ] **Step 4: Commit**

```bash
git commit -am "docs: fold zellij-keybinding-fixes.md into windows-setup.md and windows/*.json, delete it"
```

---

### Task 6: `README.md`

**Files:**
- Create: `README.md`
- Test: `tests/readme_test.bats`

**Interfaces:**
- Consumes: `docs/windows-setup.md#quick-reference` (Task 3) as the link target for "Before you begin," rather than duplicating the table.
- Produces: the repo's front door - no other file depends on `README.md`'s content programmatically.

- [ ] **Step 1: Write `README.md`**

(Same note as Task 3, Step 1: this content nests its own ` ```bash `/` ```powershell ` fences, so it's wrapped in a 4-backtick fence here purely for this plan document — write the actual file using ordinary 3-backtick fences.)

````markdown
# omawsl

A single-script installer that turns a fresh WSL2 Ubuntu install into a fully configured
development environment - the same "one script, done" experience
[Omakub](https://github.com/basecamp/omakub) provides for bare-metal Ubuntu, adapted for
WSL2 on Windows 11.

```bash
curl -fsSL https://raw.githubusercontent.com/tunacinsoy/omawsl/master/boot.sh | bash
```

## Before you begin

`install/windows-prereq-checklist.sh` (part of the installer itself) only reacts *after*
you've already reached a fresh WSL bash prompt and made your picker choices. This section is
what gets you there in the first place - and optionally a little further.

1. **Get to time 0.** If you don't already have WSL2 + Ubuntu installed, open PowerShell as
   Administrator and run:

   ```powershell
   wsl --install -d Ubuntu
   ```

   If that fails or behaves oddly (BIOS virtualization disabled, an old Windows build, etc.),
   Microsoft's own WSL install docs are the authoritative troubleshooting source -
   https://learn.microsoft.com/windows/wsl/install - that's a moving target across Windows
   versions omawsl doesn't try to maintain a parallel copy of.

2. **Optional: prep the Windows side first.** If you already know you'll want VS Code, Cursor,
   or Docker Desktop, installing them *now* means `install.sh`'s pre-install checklist will
   have nothing to flag when you get there. See the quick-reference table at the top of
   [`docs/windows-setup.md`](docs/windows-setup.md#quick-reference) for exactly what each
   picker option needs on the Windows side and the numbered steps for each - the same table
   `install.sh` itself points you to if you skip this and hit it reactively instead.

3. **Run it.** The one-liner at the top of this README. Everything from here is interactive
   (`gum` prompts) and unattended after that.

## What you get

Fully automated on the WSL/Linux side: shell and terminal tooling (zellij, btop, fastfetch,
lazygit, lazydocker, `gh`), Docker (native Engine by default, or Docker Desktop detect-and-defer
if you opt in), your choice of language runtimes and cloud CLIs via `mise` (Ruby on Rails,
Node.js, Go, PHP, Python, Elixir, Rust, Java, Terraform, Azure CLI), containerized storage
(MySQL, Redis, PostgreSQL), and your choice of editors/AI tooling (VS Code, Neovim, opencode,
Cursor, Claude Code CLI, Codex CLI, GitHub Copilot CLI, Gemini CLI). Nothing in any picker is
pre-selected - what you get is exactly what you choose, every time.

Ten ported Omakub themes are available via `bin/omawsl theme <name>`, applied consistently
across zellij, btop, Neovim, VS Code/Cursor, opencode (where it has a matching built-in
preset), and - the one exception to "never auto-touch Windows-side files" - Windows Terminal's
own color scheme, synced automatically.

Documented but never automated: Windows Terminal itself, its font, and the zellij keybinding
fix - see [`docs/windows-setup.md`](docs/windows-setup.md).

## What omawsl deliberately excludes

Not every gap here is an oversight - some are deliberate:

- **37signals commercial products** (HEY, Basecamp) - out of scope for a general dev-environment
  installer.
- **The Windows desktop-app layer** (Spotify, Signal, and Linux-desktop-only concepts like
  GNOME, Tactile, Ulauncher) - WSL has no desktop environment of its own, so there's nothing
  for these to run in.
- **Any automatic Windows-side software installation** (winget, PowerShell package installs)
  triggered by the WSL installer - some target machines sit behind a corporate firewall where
  installing Windows software requires an IT ticket; omawsl never assumes that's not the case.
  See [`docs/windows-setup.md`](docs/windows-setup.md) for the manual (or optionally
  `windows/setup.ps1`-assisted) alternative.
- **Typora** - not a 37signals product, but dropped deliberately: there are many alternative
  markdown editors, and it's not central enough to this tool's scope to carry.
- **X11 compose-key mappings** (`xcompose`) - a desktop/X11 input-method feature; Windows owns
  keyboard input for a WSL session, so there's no WSL-side equivalent to configure.

## Status

omawsl is under active development. `bin/omawsl theme` is the first subcommand shipped;
`update`, `migrate`, `uninstall`, `install`, and `doctor` are still to come.
````

- [ ] **Step 2: Write `tests/readme_test.bats`**

```bats
#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DOC="$REPO_ROOT/README.md"

@test "README.md exists" {
  [ -f "$DOC" ]
}

@test "README.md has a Before you begin section" {
  grep -qF "## Before you begin" "$DOC"
}

@test "README.md has a What omawsl deliberately excludes section" {
  grep -qF "## What omawsl deliberately excludes" "$DOC"
}

@test "README.md excludes section names all three required items" {
  grep -q "37signals" "$DOC"
  grep -q "desktop-app layer" "$DOC"
  grep -q "automatic Windows-side software installation" "$DOC"
}

@test "README.md links to windows-setup.md's quick-reference table instead of duplicating it" {
  grep -q "docs/windows-setup.md#quick-reference" "$DOC"
  # guard against accidental duplication: the pipe-table syntax from windows-setup.md's
  # quick-reference table should not also appear verbatim in README.md
  ! grep -q "^| If you picked" "$DOC"
}

@test "README.md contains the real boot.sh one-liner" {
  grep -q "curl -fsSL https://raw.githubusercontent.com/tunacinsoy/omawsl/master/boot.sh | bash" "$DOC"
}
```

- [ ] **Step 3: Run the new test file**

Run: same bats invocation pattern as Task 1, Step 4.
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add README.md tests/readme_test.bats
git commit -m "docs: add README with Before You Begin and exclusions sections"
```

---

### Task 7 (human-only, not for the agent executing this plan): Manual end-to-end verification

**Do not attempt this task as the implementing agent.** Per this project's established
practice (every phase so far has had a final human-verification task - see project memory),
present these steps to the user and wait for them to run it and report back. Do not mark this
phase "DONE" in `docs/superpowers/plans/roadmap.md` until they do - word the roadmap entry as
"merged, verification pending" in the meantime.

Steps for the human to run, against their real Windows 11 + WSL2 Ubuntu machine:

1. Open Windows Terminal's Settings → "Open JSON file", and note the current `profiles.defaults`
   and `actions` content (for comparison/rollback).
2. Before applying anything, press `Alt+Left` while inside a real zellij session in this WSL
   distro - confirm it does **not** currently reach zellij (Windows Terminal intercepts it),
   matching the collision `docs/windows-setup.md#fonts` describes.
3. Pick one font option and merge the corresponding file (`windows/windows-terminal.json` for
   Nerd Font, or `windows/windows-terminal-fallback.json` for Cascadia Mono) into `settings.json`
   by hand, following `docs/windows-setup.md#fonts`'s instructions exactly as written (as a
   first-time reader would, not from prior knowledge of the repo).
4. Restart Windows Terminal. Re-test `Alt+Left/Down/Up/Right` inside zellij - confirm all four
   now reach zellij (pane focus moves) instead of being swallowed by Windows Terminal.
5. If the Nerd Font option was chosen: confirm `windows/fonts/README.md`'s download link and
   font-family name are correct by actually downloading, installing, and confirming icon glyphs
   (fastfetch's logo, file-type icons) render instead of showing as boxes/tofu.
6. Read through `README.md`'s "Before you begin" section and `docs/windows-setup.md` end to end
   as if seeing this repo for the first time - confirm every numbered step is accurate and
   nothing references a file that no longer exists (`docs/prerequisites.md`,
   `docs/zellij-keybinding-fixes.md` should not be mentioned anywhere reachable).
7. If comfortable running it, review `windows/setup.ps1`'s contents, then run it in a PowerShell
   window and confirm it installs (or confirms already-installed) Windows Terminal and the Nerd
   Font without requesting admin elevation, and prints the correct final manual-merge reminder.
8. Report back what happened - including anything that read confusingly, was wrong, or didn't
   match the real Windows Terminal version's actual behavior. Fix any real issues found (same
   as every prior phase's Task N) before the phase is considered closed.

Once confirmed, update `docs/superpowers/plans/roadmap.md`'s Phase 6 entry to "DONE, merged to
`master`" and update project memory accordingly - matching the pattern from Phases 1-5.
