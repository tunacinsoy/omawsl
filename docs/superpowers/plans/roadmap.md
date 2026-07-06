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

2. **Docker + storage — not yet planned.**
   `OMAWSL_DOCKER_MODE` (Engine-only via native `docker-ce`, pre-highlighted default, vs.
   Docker Desktop as an explicit opt-in with detect-and-defer), systemd-support handling,
   the Docker-Desktop/native-engine PATH-collision guard, and the three storage containers
   (MySQL, Redis, PostgreSQL). This phase is expected to populate the first real items in
   `install/windows-prereq-checklist.sh`'s checklist (Docker Desktop, if chosen).

3. **Languages & cloud tools — not yet planned.**
   `mise.sh`, `select-dev-language.sh` (Ruby on Rails, Node.js, Go, PHP, Python, Elixir,
   Rust, Java), `cloud-tools.sh` (Terraform, Azure CLI) with apt-repo-failure isolation so
   one blocked third-party mirror can't cascade into unrelated later steps.

4. **Editors & AI tooling — not yet planned.**
   All 8 `app-*.sh` scripts (VS Code, Neovim, opencode, Cursor, Claude Code CLI, Codex CLI,
   GitHub Copilot CLI, Gemini CLI), with detect-and-defer for the Windows-side GUI apps
   (VS Code, Cursor) — this phase populates the checklist further.

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
