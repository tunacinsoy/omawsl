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

4. **Editors & AI tooling — merged to `master`, manual end-to-end verification (Task 13) pending.**
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
   145 bats tests, all passing. **A real end-to-end run by the human (on the pre-Phase-4
   `master`, picking Ruby on Rails) surfaced one more bug the stubbed suite couldn't catch:**
   `install/terminal.sh`'s dispatch order ran `select-dev-language.sh` (which triggers
   `mise`'s ruby-build backend to compile Ruby, and its OpenSSL dependency, from source)
   *before* `libraries.sh` (which installs `build-essential`, the C toolchain) — so picking
   Ruby failed with "No C compiler found" on a real WSL2 instance that had no compiler yet.
   Fixed directly on `master` (`ae6d5e7`, moving `libraries.sh` to run right after
   `docker.sh`) and merged into the Phase 4 branch before it landed. A follow-up real run
   also hit Azure CLI's already-known, already-isolated repo-unreachable limitation
   (Microsoft's own apt repo, not an omawsl bug) — confirmed the failure-isolation from
   Phase 3 handled it correctly and the run still completed. **Both of those were found
   incidentally on the pre-Phase-4 `master`, before this phase's own scripts were wired
   into `terminal.sh` — they don't constitute verification of Phase 4's actual new surface.**
   Per this plan's own Task 13, that verification (VS Code/Cursor settings deploy, Neovim's
   LazyVim bootstrap, Claude Code CLI's real install location, the Codex/Gemini CLI
   mise-wrapper mechanism, gh-copilot, lazydocker/zellij) is human-in-the-loop by design and
   still outstanding — this entry should only be reworded to "DONE" once that's run and
   reported back (matching Phases 2-3's own Task 7/Task 6 pattern).

5. **Theming — not yet planned.**
   All 10 ported Omakub themes, `bin/omawsl theme`, the Windows Terminal JSON edit (`jq` +
   backup + Windows-username resolution), and the zellij keybinding-fidelity verification
   this spec has flagged as unverified since design time.

6. **Windows-side deliverables + README — not yet planned.**
   `docs/windows-setup.md`, `windows/` assets (both the Nerd Font and zero-install Cascadia
   Mono profile variants), and `README.md`'s required sections (exclusions list, "Before you
   begin").

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
