# omawsl — Curriculum Outline

**Baseline level:** true-beginner
**Derived from:** git history

omawsl is a single-script installer that turns a fresh WSL2 Ubuntu install into a
configured dev environment (shell/terminal tooling, Docker, language runtimes, cloud
CLIs, editors/AI CLIs, themes, and a `bin/omawsl` maintenance CLI). It was built as 7
sequential, plan-documented phases (`docs/superpowers/plans/roadmap.md`), then extended
by 14 further feature/hardening rounds, each with its own commit cluster. That gives 21
natural phases below. Phases 1-7 are the core build (largest, most foundational —
recommended minimum for a first pass). Phases 8-21 are real, valuable, but smaller and
more independent; the operator may want to trim or merge some of these before Phase 2
generates lessons for all of them.

## Phase 1: core-skeleton
**Teaches:** The shape every later phase reuses: a `boot.sh` entry point that
clone-or-pulls the repo and hands off to `install.sh`; an orchestrator script that
chains version/OS checks, a TUI-prompt tool (`gum`), first-run choice prompts, and
per-concern sub-scripts; a `lib.sh` of shared bash helpers (version compare, WSL2
detection, choices persistence); and the bats-core test harness with stubbed commands
so installer logic can be tested without really installing anything. This is the
foundational vocabulary (orchestration, idempotent sub-scripts, `set -euo pipefail`
discipline, stubbed testing) every later phase assumes.
**Grounded in:** `docs/superpowers/plans/2026-07-06-omawsl-phase1-core-skeleton.md`;
`boot.sh`, `install.sh`, `install/check-version.sh`, `install/lib.sh`,
`install/first-run-choices.sh`, `install/windows-prereq-checklist.sh`,
`install/terminal.sh`, `install/terminal/a-shell.sh`,
`install/terminal/identification.sh`, `install/terminal/apps-terminal.sh`,
`install/terminal/libraries.sh`, `configs/bashrc`, `configs/inputrc`,
`tests/` (bats-core + `tests/helpers/stubs.bash`); commit range `2754f99..a2054b2`
plus fixups through `5f66e63`.
**Side effects:** installs system packages via `apt-get`, downloads and installs the
`gum` binary, writes to `~/.bashrc` and `~/.inputrc`, sets git's global
`user.name`/`user.email`.

## Phase 2: docker-and-storage
**Teaches:** Branching install logic driven by a user choice
(`OMAWSL_DOCKER_MODE`: native Engine vs. Docker Desktop detect-and-defer), the
detect-and-defer pattern itself (don't install what's already reachable; queue a
checklist item instead), and running idempotent local dev databases as Docker
containers rather than native packages. Also the first real lesson in "tests pass but
reality doesn't": two bugs (a stale-group `sudo` permission crash, a summary message
scrolling out of view) only showed up on a real machine, teaching why phases end in
manual end-to-end verification, not just green tests.
**Grounded in:** `docs/superpowers/plans/2026-07-07-omawsl-phase2-docker-storage.md`;
`install/terminal/docker.sh`, `install/terminal/select-dev-storage.sh`,
`install/lib.sh`'s `omawsl_docker_reachable`; commit range `a70f01b..2bd8d01`.
**Side effects:** installs `docker-ce` (or detects Docker Desktop) via apt/system
packages, adds the user to the `docker` group, starts Docker containers that bind
local ports (MySQL/Redis/PostgreSQL).

## Phase 3: languages-and-cloud-tools
**Teaches:** Bootstrapping a version manager (`mise`) and driving it non-interactively
to install user-chosen language runtimes; installing tools from third-party apt
repositories safely, with failure isolation so one blocked/broken repo can't `set -e`
abort the rest of the run; and three more real-world bugs (PATH export ordering so a
freshly-mise-installed tool is actually reachable in the *next* shell, a broken apt
source left behind by a failed repo add poisoning a later unrelated `apt-get update`,
and `gpg --dearmor` hanging on a re-run without `--yes`) — a concentrated lesson in
why idempotent, re-runnable scripts are harder than they look.
**Grounded in:**
`docs/superpowers/plans/2026-07-07-omawsl-phase3-languages-cloud-tools.md`;
`install/terminal/mise.sh`, `install/terminal/select-dev-language.sh`,
`install/terminal/cloud-tools.sh`; commit range `c836f72..4d8c0da`.
**Side effects:** adds third-party apt repositories and GPG keyring files, installs
system packages, installs language runtimes into `~/.local/share/mise`, appends PATH
exports to `~/.bashrc`.

## Phase 4: editors-and-ai-tooling
**Teaches:** Fanning one orchestrator out to many independent, same-shaped install
scripts (8 `app-*.sh` scripts, one per editor/AI CLI) gated on user selection; sharing
one baseline config across two similar tools (VS Code and Cursor) instead of
duplicating it; picking the right install strategy per tool (official native-binary
installer vs. a private mise-managed Node.js + explicit wrapper, chosen specifically to
avoid a Phase-3-class PATH bug); and a severe real-world bug (one unisolated `gh`
extension failure under `set -euo pipefail`, sourced rather than sub-shelled, silently
killing the rest of the install) that becomes the case study for "isolate every
external command that can fail, even if the one before it worked."
**Grounded in:**
`docs/superpowers/plans/2026-07-07-omawsl-phase4-editors-ai-tooling.md`;
`install/terminal/app-vscode.sh`, `install/terminal/app-cursor.sh`,
`install/terminal/app-neovim.sh`, `install/terminal/app-opencode.sh`,
`install/terminal/app-claude-cli.sh`, `install/terminal/app-codex-cli.sh`,
`install/terminal/app-gemini-cli.sh` (later replaced, see Phase 14),
`install/terminal/app-gh-copilot.sh`, `configs/vscode.json`; commit range
`06cbdac..f229bff` plus the cross-phase ordering fix `ae6d5e7`.
**Side effects:** installs each selected editor/CLI's own binary (native installers,
npm-via-mise, or `gh extension install`), writes VS Code/Cursor's Remote-WSL "Machine"
settings, installs the Neovim/LazyVim starter config into `~/.config/nvim`.

## Phase 5: theming
**Teaches:** Porting external theme data (10 Omakub themes) into a consistent internal
format spanning five very different config file formats (Lua, KDL, an ini-like
`.theme` file, a shell script, JSON), then writing one `apply` command that pushes the
same logical theme across all of them plus, uniquely in this project, one real edit to
a Windows-side file (Windows Terminal's `settings.json`, via `jq`, backed up first) —
the single deliberate exception to "never touch Windows files" and the lesson in why
that exception was made narrowly and safely (malformed JSON is skipped, not aborted
on).
**Grounded in:** `docs/superpowers/plans/2026-07-09-omawsl-phase5-theming.md`;
`themes/*/`, `bin/omawsl-sub/theme.sh`, `bin/omawsl` (theme subcommand added);
commit range `10dcbc5..dac1505`.
**Side effects:** writes theme config files into `~/.config` (zellij, btop, Neovim,
opencode) and into VS Code/Cursor's settings, edits the real Windows Terminal
`settings.json` (backed up first).

## Phase 6: windows-docs-and-readme
**Teaches:** Writing the user-facing "get to time zero" documentation for the one part
of the stack the installer can't touch (the Windows side), and why: a WSL installer
cannot script Windows Terminal itself or install fonts without leaving the sandboxed,
"never silently touch the host" boundary the whole project holds to — so this phase
is pure documentation plus optional, never-auto-invoked helper assets, not automation.
Also a lesson in doc maintenance: closing out two interim stopgap docs earlier phases
had deliberately left unfinished, and using explicit HTML anchors instead of relying on
a heading's auto-generated slug.
**Grounded in:** `docs/superpowers/plans/2026-07-12-omawsl-phase6-windows-docs.md`;
`docs/windows-setup.md`, `windows/windows-terminal.json`,
`windows/windows-terminal-fallback.json`, `windows/fonts/README.md`,
`windows/setup.ps1`, `README.md`; commit range `0658adc..d325b9d`.
**Side effects:** none (repo-internal doc/asset files only; `windows/setup.ps1` is an
optional helper never invoked automatically by any omawsl script).

## Phase 7: cli-completion
**Teaches:** Turning a one-shot installer into a maintainable long-lived tool: a
shared slug/label/category registry so `install`, `uninstall`, and `doctor` can never
drift on what a name means; `update`/`migrate` as a pull-and-run-pending-migrations
pair; `doctor` as a read-only state report; and `uninstall` as installers run in
reverse, one script per installed thing. Closes with a real product gap the user
caught after using it for real (`uninstall` not removing its item from the persisted
choices file) — a lesson that "done" means used, not just tested.
**Grounded in:**
`docs/superpowers/plans/2026-07-12-omawsl-phase7-cli-completion.md`;
`bin/omawsl`, `bin/omawsl-sub/items.sh`, `bin/omawsl-sub/update.sh`,
`bin/omawsl-sub/migrate.sh`, `bin/omawsl-sub/install.sh`,
`bin/omawsl-sub/uninstall.sh`, `bin/omawsl-sub/doctor.sh`, `uninstall/*.sh`; commit
range `26d5849..0d936dd` plus the follow-up fix `821743c`.
**Side effects:** removes installed packages/binaries and their config on `uninstall`,
runs migrations that rewrite `~/.bashrc`/`~/.inputrc`/version state, reads and rewrites
the persisted `choices.env` in the omawsl config directory under `$HOME`.

## Phase 8: self-update-mechanism
**Teaches:** Building a registry-driven update system for tools that have no native
updater of their own — a table of "orphan tools," a version-check adapter per tool, a
bounded-wait/parallel runner so N slow network checks don't serialize, and a picker UI
that shows current-vs-latest per tool before acting.
**Grounded in:** `docs/superpowers/specs/2026-07-13-omawsl-update-mechanism-design.md`,
`docs/superpowers/plans/2026-07-13-omawsl-update-mechanism.md`;
`bin/omawsl-sub/update.sh`, orphan-tool registry/adapter code; commit range
`8ffa70f..b97d712`.
**Side effects:** makes network calls to check each tool's latest version, and
installs/updates the chosen tool's own binary on disk.

## Phase 9: aliases-and-demo-docs
**Teaches:** Porting a curated set of shell aliases from an upstream project, and
writing scripted, reproducible "live demo" documentation for two different audiences
(personal PC vs. locked-down corporate PC) — a lesson in documentation as a tested
artifact, not an afterthought.
**Grounded in:** `docs/superpowers/specs/2026-07-14-omawsl-aliases-parity-design.md`,
`docs/superpowers/specs/2026-07-14-omawsl-demo-docs-design.md`,
`docs/superpowers/plans/2026-07-14-omawsl-demo-docs.md`; `configs/bashrc`,
`docs/demo-personal.md`, `docs/demo-corporate.md`; commit range `84c52fe..d109efc`.
**Side effects:** none beyond Phase 1's existing `~/.bashrc` edit (this phase only adds
more alias lines to the same file).

## Phase 10: real-world-hardening-round-1
**Teaches:** A cluster of bugs that only a real `curl | bash` run exposes: a crash
specific to piping a script into bash (no seekable stdin for later prompts), a
confirmation prompt that silently misreads terminal input under the same pipe, a
cosmetic warning that looks like a failure, and a docker-reachability check with a
false positive. The throughline: "works when I run it locally" and "works via the
documented one-liner" are different claims, and the second one needs its own testing.
**Grounded in:** commit range `94d858e..f063442`.
**Side effects:** none beyond the existing installer side effects already covered in
earlier phases (these are bug fixes to existing installer code paths, not new external
writes).

## Phase 11: native-vscode-cursor-theme-sync
**Teaches:** Reaching across the WSL/Windows boundary a second time (after Phase 5's
Windows Terminal exception) to sync theme colors into the *native Windows-side*
VS Code/Cursor settings — and doing it without destroying the user's own settings:
merging JSON while preserving JSONC comments, backing up before writing, and isolating
a failing `code --install-extension` call so one missing extension can't abort a theme
apply.
**Grounded in:**
`docs/superpowers/specs/2026-07-14-omawsl-vscode-native-theme-sync-design.md`,
`docs/superpowers/plans/2026-07-14-omawsl-vscode-native-theme-sync.md`; theme-sync
helper code in `bin/omawsl-sub/theme.sh` and `install/lib.sh`; commit range
`b97280e..854fd3f`.
**Side effects:** writes to the native Windows-side VS Code/Cursor `settings.json`
(outside WSL, backed up first) and installs the theme's VS Code extension into the
native (non-Remote-WSL) extension store.

## Phase 12: language-toolchain-hardening
**Teaches:** The class of bug where a language's compiled extensions need native
system libraries that aren't installed yet (PHP's sqlite3/curl/GD/intl/zip/mbstring
extensions each needing their own `-dev` package), why install *order* matters when
one runtime depends on another being present first (Erlang before Elixir), and two
narrow environment-specific workarounds (a WSL2/WSLg `XDG_RUNTIME_DIR` bug, an Azure
CLI apt-repo codename fallback).
**Grounded in:** commit range `05b5a27..869664c`.
**Side effects:** installs additional system `-dev` packages via apt.

## Phase 13: cloud-clis-menu
**Teaches:** Splitting one picker option (a general "cloud tools" checkbox that only
covered Terraform+Azure) into its own dedicated menu (Azure/AWS/GCP), and the
mechanical cost of that kind of refactor: moving Azure CLI's install *and* uninstall
code to a new home without breaking either, adding the new category consistently to
`install`, `uninstall`, and `doctor` at once, and updating the orphan-tools registry
and tests to match.
**Grounded in:** `docs/superpowers/specs/2026-07-17-omawsl-cloud-clis-menu-design.md`,
`docs/superpowers/plans/2026-07-17-omawsl-cloud-clis-menu.md`;
`install/terminal/cloud-clis.sh`, `uninstall/cloud-clis.sh`,
`install/first-run-choices.sh`; commit range `1e7a9b2..bd6cc72`.
**Side effects:** adds third-party apt repositories, installs the Azure/AWS/GCP CLI
packages.

## Phase 14: ubuntu-24-04-and-editor-picker-fixes
**Teaches:** A batch of independent portability/correctness fixes surfaced by running
on a newer Ubuntu release and by real use of the editor picker: a PATH-timing false
negative in the opencode install guard, GitHub Copilot CLI's real binary name changing
out from under an idempotency check, swapping one AI CLI for another in the picker
(Gemini CLI to Antigravity CLI) as a product decision, and installing `gum` from its
own apt repo instead of assuming Ubuntu's universe repo carries it.
**Grounded in:** commit range `1f9b6d8..50bb054`.
**Side effects:** installs `gum` from a third-party apt repository (replacing the
Phase-1 approach); no other new external effects beyond existing installer paths.

## Phase 15: corp-safe-config-editing
**Teaches:** A policy change driven by a real risk (a corporate machine's `~/.bashrc`
may be centrally managed) — never overwrite a user's own dotfiles again; instead,
ensure exactly one `source`-line pointing at omawsl's own config lives in
`~/.bashrc`/`~/.inputrc`, and write a migration that moves *existing* installs onto
the new model without ever deleting the user's file. A concentrated lesson in
designing for "we might be wrong about what's safe to touch" instead of "we own this
file."
**Grounded in:**
`docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md`,
`docs/superpowers/plans/2026-07-28-corp-safe-config-editing.md`;
`install/lib.sh`'s `omawsl_ensure_bashrc_source_line`, `docs/config-safety.md`; commit
range `e36debe..3466a7e`.
**Side effects:** appends (never overwrites or deletes) one source-line to
`~/.bashrc`/`~/.inputrc` outside the project; migrates existing installs' dotfiles the
same way.

## Phase 16: upstream-install-hardening
**Teaches:** Preferring a tool's own upstream release/installer over an Ubuntu apt
package when apt's version is stale (fastfetch, lazygit, lazydocker), resolving a
Windows-side binary (`cmd.exe`) via a fixed path instead of assuming it's always on
PATH, and authenticating version-check network calls so they don't get silently
rate-limited.
**Grounded in:** commit range `489bd20..831a80a`.
**Side effects:** installs fastfetch/lazygit/lazydocker from their own GitHub releases
instead of apt; makes authenticated network calls to GitHub's API.

## Phase 17: docker-daemon-proxy-autoconfig
**Teaches:** Detecting a corporate HTTP(S) proxy from the environment and writing a
scoped, clearly-namespaced Docker daemon drop-in config for it — including the
narrower, harder problem of *not* clobbering a proxy config the user already set
themselves (conflict detection, back-off), reporting the pending state via `doctor`,
and cleanly removing only omawsl's own drop-in on uninstall.
**Grounded in:**
`docs/superpowers/specs/2026-07-29-docker-daemon-proxy-autoconfig-design.md`,
`docs/superpowers/plans/2026-07-29-docker-daemon-proxy-autoconfig.md`;
`omawsl_detect_proxy_env`, `omawsl_docker_proxy_conflict`,
`omawsl_configure_docker_proxy` in `install/lib.sh`; commit range `e3a5509..66fb897`.
**Side effects:** writes a Docker daemon proxy drop-in config file outside the project
directory (under Docker's system config path) and removes it on uninstall.

## Phase 18: copilot-autopilot-mode
**Teaches:** Adding an opt-in "autopilot" alias for a CLI tool (auto-approve all
actions) behind an explicit first-run prompt, wiring the same prompt into the
`install`-after-the-fact path too so it's not first-run-only, and persisting/clearing
that one boolean choice correctly through install and uninstall — plus a `doctor` fix
so it correctly reports tools that are installed but not (yet) selected.
**Grounded in:** `docs/superpowers/specs/2026-08-09-copilot-autopilot-mode-design.md`,
`docs/superpowers/plans/` implementation plan for issue #2; Copilot autopilot prompt
helper and alias code, `bin/omawsl-sub/doctor.sh` fixes; commit range
`a3ebc5c..658d8f9`.
**Side effects:** appends an alias definition to `~/.bashrc`, persists the autopilot
choice in the omawsl config directory under `$HOME`.

## Phase 19: starship-default-prompt
**Teaches:** Replacing a static `PS1` with `starship`, a real external prompt tool:
installing its binary, wiring it into `~/.bashrc` behind mise's own activation (order
matters again, as in Phase 3), recoloring its config to match each of the 10 ported
themes, adding it to the orphan-tools update registry and `doctor`, and migrating
existing installs onto it without breaking a themeless config.
**Grounded in:** `docs/superpowers/specs/2026-08-09-starship-default-prompt-design.md`,
`docs/superpowers/plans/2026-08-09-starship-default-prompt.md`; starship install/config
code, `configs/bashrc`, theme recoloring; commit range `a4ec9de..156c051`.
**Side effects:** installs the `starship` binary, writes its config into
`~/.config/starship.toml`, edits `~/.bashrc` to invoke it, migrates existing installs.

## Phase 20: test-suite-hardening
**Teaches:** Test flakiness and false positives as their own class of bug: a `doctor`
warning that only makes sense under the old prompt now false-triggering under
starship, a temp-directory leak in the stub-command test harness itself (across
hundreds of test files), and an end-to-end test whose scripted prompt answers drifted
out of sync with a real prompt added by Phase 18.
**Grounded in:** commit range `4eb9813..bcd8ef4`.
**Side effects:** none (test-only and doctor-reporting-only changes).

## Phase 21: neovim-treesitter-and-npm-warnings
**Teaches:** Two small, unrelated last-mile polish fixes: provisioning a real working
`tree-sitter-cli` so Neovim's treesitter plugin can build parsers on its `main`
branch, and precisely filtering (rather than blanket-suppressing) an `npm` advisory
warning for mise-managed CLI installs — a lesson in narrowing a fix to the exact
condition instead of silencing a whole class of output.
**Grounded in:** commit range `004ae3b..b2a604a`.
**Side effects:** installs `tree-sitter-cli` (via mise-managed npm) as part of the
Neovim setup path.
