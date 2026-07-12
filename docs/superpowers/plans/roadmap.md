# omawsl Implementation Roadmap

Source of truth for the full product design: `docs/superpowers/specs/2026-07-05-omawsl-design.md`.

That spec's scope was too large for a single implementation plan (17 sections, ~25 install
scripts, 10 themes, a multi-command CLI, an uninstall tree, Windows-side docs), so it was
broken into 7 sequential phases when execution started. Each phase gets its own plan document
under `docs/superpowers/plans/` immediately before it's implemented — not all upfront, since
what's learned building one phase can (and did, for Phase 1) change details worth locking into
the next phase's plan.

## Phases

1. **Core skeleton — DONE, merged to `master`.**
   Plan: `docs/superpowers/plans/2026-07-06-omawsl-phase1-core-skeleton.md`
   `boot.sh`, `install.sh` orchestration, `check-version.sh` (WSL2 detection, floor-only
   version check), gum bootstrap, all 5 first-run prompts + choices persistence, the
   pre-install Windows-prereq checklist (a real extension point, no items populated yet),
   and the always-on terminal setup (git identification, shell config, terminal tools via
   apt, native build libraries). 51 bats tests, verified end-to-end against a real WSL2
   Ubuntu 26.04 instance.

2. **Docker + storage — DONE, merged to `master`.**
   Plan: `docs/superpowers/plans/2026-07-07-omawsl-phase2-docker-storage.md`
   `docker.sh` (`OMAWSL_DOCKER_MODE` branch: Engine-only native `docker-ce` install with
   systemd-support handling and a Docker-Desktop/native-engine PATH-collision guard, vs.
   Docker Desktop detect-and-defer), the first real item in
   `install/windows-prereq-checklist.sh`'s checklist (Docker Desktop, when chosen and not
   yet reachable), and `select-dev-storage.sh` (MySQL/Redis/PostgreSQL as idempotent Docker
   containers). 79 bats tests, all passing. Implemented via subagent-driven-development;
   task-by-task review plus a final whole-branch review caught a cross-task integration gap
   (storage crashing instead of deferring when Docker Desktop mode's `docker` isn't yet
   reachable) before merge. Manual end-to-end verification against a real fresh WSL2 Ubuntu
   26.04 instance (Task 7) is complete, including a second idempotent re-run. It surfaced
   two real bugs the stubbed suite couldn't catch — a stale-group-cache permission-denied
   crash in `select-dev-storage.sh` (fixed in `871a92a` via `sudo docker`), and a
   post-install reminder that scrolled out of view before the run finished (fixed in
   `abc46e8` by repeating it in `install.sh`'s final summary) — both fixed and verified
   directly on `master` after the phase's own merge.

3. **Languages & cloud tools — DONE, merged to `master`.**
   Plan: `docs/superpowers/plans/2026-07-07-omawsl-phase3-languages-cloud-tools.md`
   `mise.sh` (bootstraps the mise version manager, exports the current session's PATH for
   `select-dev-language.sh` to use), `select-dev-language.sh` (Ruby on Rails, Node.js, Go,
   PHP, Python, Elixir, Rust, Java, all via `mise use --global`), `cloud-tools.sh`
   (Terraform, Azure CLI via their own apt repos) with apt-repo-failure isolation so one
   blocked third-party mirror can't cascade into unrelated later steps. Implemented via
   subagent-driven-development in an isolated worktree; task-by-task
   review found and fixed two real bash `set -e`/pipe bugs in `cloud-tools.sh`'s own sample
   code, and the final whole-branch review caught a critical cross-task gap (Ruby on Rails'
   `gem install rails` wouldn't have found `gem` on PATH after a mise-only Ruby install,
   which would have aborted the entire `install.sh` run for that selection) — fixed before
   merge. **Manual end-to-end verification (Task 6) ran against a real WSL2 instance
   (Go + Ruby on Rails + Terraform/Azure CLI) and found two more real bugs the stubbed
   suite couldn't catch:** `configs/bashrc` checked for `mise` before exporting the PATH
   entry that makes it reachable, so `mise activate` never ran in any interactive shell —
   `go`/`ruby`/`rails`/`gem` stayed unreachable even though `mise ls` showed them installed
   (fixed in `7e9b10b`); and a failed Azure CLI repo-add (Microsoft's apt repo has no
   Release file yet for Ubuntu 26.04's "resolute" codename) left a broken apt source
   behind, which poisoned `libraries.sh`'s own later `apt-get update` and silently aborted
   the whole `install.sh` run under `set -e` (fixed in `18134f5`, which also hardened
   several tests against this WSL instance's newly-real `docker-ce`/`terraform`/`mise`
   installs — commits `18134f5`, `ba6a01b`). A follow-up re-run then hit a third bug:
   `gpg --dearmor` without `--yes` interactively prompts to overwrite an
   already-existing keyring file (left over from the original pre-fix failure) and
   hangs a non-interactive script forever — fixed in all three call sites (`docker.sh`
   and both `cloud-tools.sh` functions) in `7105055`. 110 bats tests, all passing.
   Confirmed clean on a subsequent re-run — Phase 3 is closed out.

4. **Editors & AI tooling — DONE, merged to `master`, including real-world verification.**
   Plan: `docs/superpowers/plans/2026-07-07-omawsl-phase4-editors-ai-tooling.md`
   All 8 `app-*.sh` scripts (VS Code, Neovim, opencode, Cursor, Claude Code CLI, Codex CLI,
   GitHub Copilot CLI, Gemini CLI) wired into `install/terminal.sh`'s dispatch table, each
   gated on `OMAWSL_EDITORS` membership via `omawsl_list_has`. VS Code and Cursor share one
   baseline `configs/vscode.json` deployed to their Remote-WSL/WSL-integration "Machine"
   settings, with detect-and-defer for the live CLI (two new checklist items,
   `omawsl_code_reachable`/`omawsl_cursor_reachable` in `lib.sh`); Codex CLI and Gemini CLI
   (npm-only) each use a private `mise exec node@lts`-managed install plus an explicit
   `$HOME/.local/bin` wrapper rather than mise's shim mechanism, after Phase 3's Rails/`gem`
   bug. Also folded in six always-on terminal tools the roadmap had never scheduled to any
   phase (`gh`, `btop`, `fastfetch`, `lazygit` via apt; `lazydocker`, `zellij` via their own
   installers) — a gap found while planning this phase, fixed per explicit user decision.
   Implemented via subagent-driven-development in an isolated worktree; all 12 tasks passed
   individual review, and the final whole-branch review (opus) specifically scrutinized a
   hand-resolved merge conflict from a mid-flight bug fix (see below) and found it correct.
   147 bats tests, all passing.
   **Two real bugs surfaced from real `install.sh` runs, both fixed directly on `master`:**
   1. `install/terminal.sh`'s dispatch order ran `select-dev-language.sh` (triggers `mise`'s
      ruby-build backend to compile Ruby, and its OpenSSL dependency, from source) *before*
      `libraries.sh` (installs `build-essential`, the C toolchain) — so picking Ruby failed
      with "No C compiler found." Found on the pre-Phase-4 `master` (before this phase's own
      scripts were even wired in) and fixed by moving `libraries.sh` to run right after
      `docker.sh` (`ae6d5e7`), merged into the Phase 4 branch before it landed.
   2. **Task 13 (manual end-to-end verification) found a severe bug in this phase's own new
      surface:** `app-gh-copilot.sh`'s `gh extension install github/gh-copilot` has no
      failure isolation, and requires an authenticated `gh` session that a fresh install
      never has (nobody runs `gh auth login` before their *first* `install.sh`). Since the
      script runs under `set -euo pipefail`, sourced (not sub-shelled) into `terminal.sh`,
      this single failure silently aborted the entire rest of the run - confirmed by
      file-mtime forensics showing Codex CLI (installed right before it) succeeded while
      Gemini CLI (the very last script, right after it) never ran at all, and
      `install complete` never printed. Fixed (`d3df812`) with the same failure-isolation
      pattern Phase 3 established for Terraform/Azure CLI, plus a `gh extension list`
      idempotency guard. Also hardened `a_shell_test.bats`'s `nvim`-not-installed test
      against real host state (`da6982e`) - same recurring class of fragility as
      docker/terraform/mise - and added `docs/prerequisites.md` documenting the `gh auth
      login` prerequisite up front, referenced from the failure message (`bceffa5`).
   A follow-up real run also hit Azure CLI's already-known, already-isolated
   repo-unreachable limitation (Microsoft's own apt repo, not an omawsl bug) - confirmed
   Phase 3's failure-isolation handled it correctly. **After both fixes, the user re-ran
   `gh auth login` + `install.sh` end to end and confirmed it now completes cleanly** -
   Phase 4 is closed out.

5. **Theming — DONE, merged to `master`.**
   Plan: `docs/superpowers/plans/2026-07-09-omawsl-phase5-theming.md`
   All 10 Omakub themes ported to `themes/<name>/` (`neovim.lua`, `zellij.kdl`, `btop.theme`,
   `vscode.sh`, plus a new `windows-terminal-scheme.json` hand-derived from each theme's real
   upstream Alacritty colors, since Windows Terminal replaces Alacritty). `bin/omawsl theme
   <name>` (the first `bin/omawsl` subcommand - Phase 7 adds the rest) applies a theme across
   zellij, btop, Neovim, VS Code/Cursor, opencode (best-effort - 6 of 10 themes have a real
   built-in opencode preset, confirmed via research; the other 4 no-op by design), and Windows
   Terminal's own `settings.json` via `jq` (the one exception in this whole project to "never
   auto-edit Windows-side files" - a local JSON edit only, backed up first). Also closed a real
   Phase-1 gap: `configs/zellij.kdl` (Omakub's actual keybindings) and a minimal
   `configs/btop.conf` were listed as Phase-1 deliverables but never actually ported - Task 1
   ported both for real. 192 bats tests, all passing. Implemented via subagent-driven-development
   in an isolated worktree; task-by-task review found and fixed two trailing-whitespace
   transcription slips in theme data files, a Windows Terminal `settings.json` malformed-JSON
   abort bug (now skips gracefully instead), and the final whole-branch review found a `set -e`
   dead-code bug in the `gum choose` cancel path (fixed, re-reviewed clean).
   **Task 9 (manual end-to-end verification) is complete, run against the real WSL2 Ubuntu
   instance, confirmed clean by the user.** It surfaced three things, none of them Phase 5 code
   bugs: (1) a pre-existing interrupted-dpkg state on the test machine blocked the very first
   `sudo apt-get` call in `install.sh` (unrelated to any omawsl code - resolved via
   `sudo dpkg --configure -a`); (2) a Node.js deprecation warning during `code
   --install-extension`, confirmed via direct reproduction to originate from VS Code's own CLI
   binary, not any omawsl script - cosmetic, extension installs succeed regardless; (3) the
   assistant's own Task 9 checklist wording was wrong (said `q` exits zellij's scroll mode - the
   real ported keybindings, verified byte-for-byte against upstream in Task 1, have no such
   binding; the real exit keys are `Esc`/`Enter`/`Ctrl+c`) - confirmed working once corrected,
   not a code issue. Windows Terminal sync was independently verified twice (once by the
   assistant directly inspecting the real `settings.json`, once by the user visually confirming
   the rendered terminal) - real Windows username resolved correctly, schemes replace instead of
   duplicating across repeated applies, zellij keybinding-fidelity (§15) and the
   `Alt+Left/Down/Up/Right` collision fix (see below) both confirmed working through a live
   Windows Terminal + zellij session.

6. **Windows-side deliverables + README — merged to `master`, verification pending.**
   Plan: `docs/superpowers/plans/2026-07-12-omawsl-phase6-windows-docs.md`
   `docs/windows-setup.md` (the new canonical Windows-side doc, opening with a quick-reference
   table, using explicit `<a id="...">` anchors rather than relying on GitHub's auto-generated
   heading slugs, since at least one heading - `## VS Code` - would auto-slug to `#vs-code`, not
   the already-shipped `#vscode` every detect-and-defer script hardcodes), `windows/` assets
   (`windows-terminal.json` for the Nerd Font/enhanced option, `windows-terminal-fallback.json`
   for the zero-install Cascadia Mono option - both carry the identical zellij/Windows-Terminal
   `Alt+Left/Down/Up/Right` keybinding-unbind fix, `windows/fonts/README.md` - a doc-only pointer
   to the same upstream `ryanoasis/nerd-fonts` release Omakub's own `fonts.sh` downloads from,
   deliberately not vendoring a font binary into this repo, `windows/setup.ps1` - an optional,
   never-auto-invoked winget helper), and `README.md` (the repo's first - "Before you begin" and
   "What omawsl deliberately excludes" sections per design spec §16, linking to rather than
   duplicating `docs/windows-setup.md`'s quick-reference table). Folded in and deleted both
   interim stopgap docs flagged by earlier phases: `docs/prerequisites.md` (Phase 4) and
   `docs/zellij-keybinding-fixes.md` (Phase 5), repointing `install/terminal/app-gh-copilot.sh`'s
   one live reference to the new canonical doc. Built via subagent-driven-development in an
   isolated worktree (`.worktrees/phase6-windows-docs`); all 7 tasks (6 content tasks + the
   plan-doc commit) passed individual review, and the final whole-branch review found one real
   Minor inconsistency - the doc's own "Quick reference" heading was the one section relying on
   GitHub's auto-slug instead of an explicit anchor, against the plan's own stated principle
   (harmless today since the auto-slug happens to resolve correctly, but fixed for consistency
   before merge). 210 bats tests, 209 passing - the one failure is the same pre-existing,
   environment-specific flake documented in Phase 5's entry above (`windows_terminal_test.bats`'s
   "cmd.exe isn't reachable" test, unrelated to this phase, not investigated further). **Manual
   end-to-end verification (Task 7) has not yet run** - see the plan document's final task for
   the exact steps (merging one of the two JSON files into a real Windows Terminal
   `settings.json`, confirming the keybinding fix and font render for real, reading the new docs
   end to end as a first-time user). Do not mark this phase DONE until that's confirmed.

7. **`bin/omawsl` CLI completion — not yet planned.**
   `update`, `migrate`, `uninstall`, `install`, `doctor` subcommands, plus the `uninstall/`
   tree.

## How to continue

For each phase: use the `writing-plans` skill to draft that phase's plan (only once the prior
phase is merged — decisions can shift based on what was actually learned building it, as
happened during Phase 1), then `subagent-driven-development` to execute it, same pattern as
Phase 1.

Operational lessons learned during Phase 1 that apply to every later phase (git/WSL pitfalls,
the `.gitattributes` CRLF fix, `sudo` needing a human, no GitHub remote yet) are recorded in
this project's persistent assistant memory — read that first if picking this back up in a new
session.
