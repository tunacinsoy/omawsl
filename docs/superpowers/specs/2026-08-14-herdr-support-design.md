# Herdr Support — Design

## Context

[Issue #10](https://github.com/tunacinsoy/omawsl/issues/10) asks for
[Herdr](https://github.com/herdrdev/herdr) to be added to omawsl's AI-tooling
picker. Herdr is a Rust-based terminal multiplexer purpose-built for running
and monitoring multiple AI coding agents (Claude Code, Codex, Copilot CLI,
Cursor Agent, and others) side by side in one terminal, with real-time agent
state tracking. It ships as a single ~10MB binary with no Node/Electron
dependency.

This is an additive feature: a tenth entry in the "Editors & AI tooling"
picker, following the exact template the last CLI-only addition (Antigravity
CLI) established. No new subsystem, no deviation from existing patterns.

## Install mechanism

Herdr's own recommended install path is a hosted shell script:

```
curl -fsSL https://herdr.dev/install.sh | sh
```

omawsl already runs the equivalent official-installer pattern for Claude Code
CLI, opencode, and Antigravity CLI - piped through `bash` (not `sh`) to match
this repo's existing convention for those three:

```
curl -fsSL https://herdr.dev/install.sh | bash
```

The installer detects OS/arch via `uname`, verifies the downloaded binary
against a SHA-256 checksum manifest, and places the `herdr` binary at
`$HOME/.local/bin/herdr` (`$HERDR_INSTALL_DIR` if set, defaulting to
`~/.local/bin`) - the same directory Claude Code CLI's own installer uses.
`~/.local/bin` is already on `$PATH` via Ubuntu's default `~/.profile`
(confirmed precedent: `apps-terminal.sh`'s comment on `omawsl_install_cli`),
so no PATH wiring is needed, unlike opencode's `~/.opencode/bin` case.

Idempotency guard: `command -v herdr`, matching every other curl-installed
CLI tool in this repo.

`install/terminal/app-herdr.sh` (new file) follows `app-antigravity-cli.sh`'s
exact shape: an unguarded `omawsl_herdr_install_steps` (the install command,
reused by the orphan-tools update path) plus a guarded
`omawsl_install_herdr` (checks `OMAWSL_EDITORS` selection, then the
`command -v` guard).

## Uninstall

Herdr's own CLI has no built-in self-uninstall subcommand. Its installer
places only the binary at `$HOME/.local/bin/herdr`; state/session data lives
under `$HOME/.config/herdr` (session.json, per-named-session subdirectories,
optional pane history) per Herdr's own XDG-convention config docs. Complete
removal:

```
rm -f "$HOME/.local/bin/herdr"
rm -rf "$HOME/.config/herdr"
```

`uninstall/app-herdr.sh` (new file) follows `uninstall/app-antigravity-cli.sh`'s
shape: one function, no guard, removes both paths.

## Picker label

"Herdr" - bare product name, no "CLI" suffix. This matches the label style
used for opencode/Cursor/VS Code (tools whose own branding doesn't append
"CLI" to the product name), as opposed to "Claude Code CLI"/"Codex CLI"/
"GitHub Copilot CLI"/"Antigravity CLI" (tools whose own branding does).
Herdr's own branding and docs refer to it as just "Herdr".

Added to the `OMAWSL_EDITORS` multi-select list in
`install/first-run-choices.sh`, appended at the end - matching how every
prior addition to this list was appended in arrival order (opencode, Cursor,
Claude Code CLI, Codex CLI, GitHub Copilot CLI, Antigravity CLI).

## Orphan-tool update tracking

Herdr has no apt or mise package coverage, so - like opencode, Claude Code
CLI, Antigravity CLI, and Starship - it needs registering as an "orphan
tool" in `bin/omawsl-sub/orphan-tools.sh` so `omawsl update` can detect and
offer to refresh it:

- Slug: `herdr`
- Label: reuses `omawsl_item_label herdr` (added in items.sh, see below)
- Installed check: `command -v herdr`
- Installed version: `herdr --version`, parsed via the existing
  `omawsl_orphan_extract_semver` helper (Herdr documents `herdr --version`
  as "print version")
- Latest version: GitHub Releases API against `herdrdev/herdr`, via the
  existing `omawsl_orphan_latest_from_github` helper (same mechanism as
  opencode/claude/zellij - Herdr publishes real GitHub Releases)
- Apply-update: re-run `omawsl_herdr_install_steps` (the curl installer),
  same as every other curl-installed orphan tool

## No Windows-side dependency

Herdr is purely WSL-side, like Claude Code CLI/Codex CLI/Antigravity CLI -
no Windows-side prerequisite, so `install/windows-prereq-checklist.sh` and
`docs/windows-setup.md` need no changes.

## Full touch points

Mirrors the Antigravity CLI addition file-for-file:

1. `install/terminal/app-herdr.sh` (new) - install script
2. `uninstall/app-herdr.sh` (new) - uninstall script
3. `install/first-run-choices.sh` - add "Herdr" to the `OMAWSL_EDITORS` picker
4. `install/terminal.sh` - add `terminal/app-herdr.sh` to
   `OMAWSL_TERMINAL_SCRIPTS` and its function to `SCRIPT_FUNCTIONS`
5. `bin/omawsl-sub/items.sh` - register the `herdr` slug in
   `omawsl_item_category`, `omawsl_item_label`, and `omawsl_item_slugs editor`
6. `bin/omawsl-sub/install.sh` - add `app-herdr` to the per-editor install
   loop in `omawsl_install_apply_editor`, plus an isolated
   `omawsl_install_herdr || echo ... skipping` call
7. `bin/omawsl-sub/uninstall.sh` - add a `herdr)` dispatch case in
   `omawsl_uninstall_dispatch`
8. `bin/omawsl-sub/doctor.sh` - add a `herdr)` case to
   `omawsl_doctor_editor_installed`
9. `bin/omawsl-sub/orphan-tools.sh` - source `app-herdr.sh`; add `herdr` to
   `omawsl_orphan_tool_slugs`, `omawsl_orphan_tool_installed`,
   `omawsl_orphan_tool_version_installed`, `omawsl_orphan_tool_version_latest`,
   and `omawsl_orphan_tool_apply_update`
10. `tests/app_herdr_test.bats` (new, mirrors `tests/app_antigravity_cli_test.bats`
    and `tests/app_codex_cli_test.bats`) covering: no-op when not selected,
    installs when selected and absent, no-ops when already installed, and
    `omawsl_herdr_install_steps` runs unconditionally. Plus updates to the
    existing aggregate tests that enumerate all editors: `terminal_test.bats`,
    `uninstall_ai_cli_test.bats`, `omawsl_orphan_tools_test.bats`,
    `first_run_choices_test.bats`, `install_test.bats`, `omawsl_doctor_test.bats`,
    `docs_updating_test.bats`
11. `README.md` - mention Herdr in the "editors/AI tooling" sentence in the
    "What you get" section

## Testing

Unit-level bash tests only (bats), following this repo's existing pattern:
network calls (the curl installer, GitHub Releases API) are stubbed via
`tests/helpers/stubs.bash`, never actually invoked in CI. No manual/E2E
verification beyond what the existing `boot_test.bats`/`install_test.bats`
full-flow tests already exercise generically across all editor picks.
