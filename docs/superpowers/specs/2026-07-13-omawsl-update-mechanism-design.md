# omawsl Update Mechanism — Design Spec

Date: 2026-07-13
Status: Draft — pending user review of this file

## 1. Purpose

Today, `bin/omawsl update` only does a `git pull` on the omawsl checkout itself plus pending
migrations (`bin/omawsl-sub/update.sh`). It never touches any tool omawsl installed. A user who
wants to know "how do I update Go" or "how do I update Codex CLI" has no single answer — and in
practice there are three different mechanisms in play depending on what the tool actually is,
with no documentation tying them together:

1. Go directly to the upstream tool's own install/update instructions.
2. Re-run `bin/omawsl install language go`, which happens to re-pin to `@latest` via mise.
3. Use `mise` directly (`mise upgrade`, `mise use --global go@latest`).

This spec does **not** try to collapse these into one universal mechanism — mise and apt are
already good at updating the tools they own, and wrapping them would mean maintaining a
duplicate, driftable copy of logic those tools already do correctly. Instead it targets the one
real gap: a set of tools omawsl installs that have **no native update command at all**, and
documents the three-way split clearly so a user always knows which tool to reach for.

## 2. Scope

**In scope:**
- Extending `bin/omawsl update` to, after its existing self-update + migrate step, offer to
  update the "orphan" tools (§3) that have no native updater.
- A version-check adapter per orphan tool (installed version vs. latest available).
- A two-phase, `gum`-driven picker UX (§6).
- A new canonical doc (`docs/updating.md`) explaining the three-way split, linked from README
  and printed as a pointer at the end of every `omawsl update` run.

**Out of scope:**
- Wrapping `mise upgrade` / `apt upgrade` themselves. `omawsl update` prints a pointer to them
  (§8) but never calls them on the user's behalf.
- Updating containerized storage (MySQL/Redis/PostgreSQL) — image/version management for
  running containers with real data is a separate concern (volumes, downtime) that doesn't fit
  this feature's "just bring the binary current" shape.
- Docker Engine / Docker Desktop itself — apt/Desktop's own updater already owns this.

## 3. Tool inventory — the "orphan" list

Every tool omawsl installs that has **no native update command** — the actual criterion,
verified against every `install/terminal/app-*.sh` and `apps-terminal.sh`:

| Slug (new) | Label | Always-on or picker-gated | Current install method | Existing guard |
|---|---|---|---|---|
| `zellij` | Zellij | Always-on (`apps-terminal.sh`) | GitHub release binary download | `command -v zellij` |
| `lazydocker` | LazyDocker | Always-on (`apps-terminal.sh`) | Official curl install script | `command -v lazydocker` |
| `opencode` | opencode | Picker (`OMAWSL_EDITORS`) | Official curl install script | `command -v opencode` |
| `claude` | Claude Code CLI | Picker (`OMAWSL_EDITORS`) | Official curl install script | `command -v claude` |
| `codex` | Codex CLI | Picker (`OMAWSL_EDITORS`) | `mise exec node@lts -- npm install -g @openai/codex` | `command -v codex` |
| `gemini` | Gemini CLI | Picker (`OMAWSL_EDITORS`) | `mise exec node@lts -- npm install -g @google/gemini-cli` | `command -v gemini` |
| `gh-copilot` | GitHub Copilot CLI | Picker (`OMAWSL_EDITORS`) | `gh extension install github/gh-copilot` | `gh extension list` match |

Explicitly **not** in this list, and why:
- **VS Code, Cursor** — Windows-side GUI apps that self-update on their own.
- **Neovim** — apt-installed; `sudo apt upgrade` covers the binary (LazyVim's own plugins update
  via `:Lazy sync` inside Neovim, out of scope here).
- **LazyGit** — apt-installed on Ubuntu 26.04 (unlike upstream Omakub, which had to hand-install
  it); already covered by `sudo apt upgrade`. This is a deliberate divergence from Omakub's own
  update menu, which does include LazyGit.
- **Language runtimes & cloud tools (Ruby, Node, Go, PHP, Python, Elixir, Rust, Java, Terraform,
  Azure CLI)** — mise-managed or apt-repo-managed; covered by §8's documentation, not wrapped.

`zellij` and `lazydocker` aren't part of the existing `bin/omawsl-sub/items.sh` slug registry
(they're always-on, not install/uninstall picker targets) — this feature introduces its own
small, separate static list of the 7 slugs above rather than overloading `items.sh`, which
exists specifically for install/uninstall/doctor's picker-driven categories.

## 4. Command flow

```
bin/omawsl update
  1. (existing, unchanged) git pull inside $OMAWSL_HOME; refuse on a dirty tree.
  2. (existing, unchanged) run pending migrations.
  3. (new) Determine which of the 7 orphan tools are actually installed right now.
     - None installed → print "omawsl: no orphan tools installed — nothing to check." and exit.
  4. (new) Phase 1: print a status line per installed orphan tool, each starting as
     "<label>   checking...". Kick off all version-check lookups as parallel background jobs
     (§5). As each resolves, redraw the block in place with its real
     "current: X   latest: Y   (update available | up to date | unknown)".
  5. (new) If every resolved tool is confirmed already up to date (no "update available" and no
     "unknown" results) → print "omawsl: everything is already up to date." and skip the picker
     entirely. If at least one tool is "unknown" (even with none confirmed outdated), still show
     the picker — an unresolved lookup isn't the same as a confirmed no-op, and the user should
     get the chance to force-check it themselves.
  6. (new) Phase 2: `gum choose --no-limit`, one line per tool using its final resolved label,
     pre-selected (`--selected`) for exactly the tools with an update available.
  7. (new) For each tool the user leaves checked, re-run that tool's install steps with its
     `command -v` guard bypassed (§7).
  8. (new) Print a closing pointer to docs/updating.md (§8) for the tools this command doesn't
     own (mise-managed languages, apt-managed packages).
```

## 5. Version-check adapter

Each orphan tool gets a small pair of shell functions: `omawsl_<slug>_version_installed` and
`omawsl_<slug>_version_latest`. Source per tool:

- **zellij, lazydocker, opencode, Claude Code CLI** — GitHub Releases API
  (`api.github.com/repos/<owner>/<repo>/releases/latest`, `.tag_name`). Exact repo/tag format for
  opencode and Claude Code CLI needs a short confirmation pass before implementation (both are
  curl-script installs; the underlying release source isn't yet verified the way zellij/lazydocker's
  is) — flagged as an implementation-plan research task, not a design blocker.
- **Codex CLI, Gemini CLI** — `npm view @openai/codex version` / `npm view @google/gemini-cli
  version` (no auth needed, same npm registry the install step itself already uses).
- **GitHub Copilot CLI** — `gh`'s own extension metadata (`gh extension list` / `gh api
  repos/github/gh-copilot/releases/latest`), reusing the authenticated `gh` session that's a
  documented prerequisite already (`docs/prerequisites.md`'s successor content in README).

All lookups run as background jobs, in parallel, each with a short timeout (a few seconds). A
lookup that fails or times out resolves to `latest: unknown` — never blocks the other six, never
hangs the command. A tool resolved as `unknown` is left **unchecked** by default in the picker
(no basis to claim an update is available), but the user can still select it manually to force a
reinstall attempt.

## 6. Picker UX

Two phases, because `gum choose` renders a fixed set of options once and can't live-update rows
while it's already showing an interactive prompt:

- **Phase 1 (non-interactive status list)** — plain terminal output, redrawn in place as each
  background lookup resolves. Purely informational; no input accepted yet.
- **Phase 2 (interactive picker)** — `gum choose --no-limit`, launched only once every row has
  settled, using the final labels. Example:

  ```
  [x] Codex CLI          current: 0.38.1   latest: 0.41.0   (update available)
  [ ] Gemini CLI         current: 2.1.0    latest: 2.1.0    (up to date)
  [ ] Zellij             current: 0.41.2   latest: 0.41.2   (up to date)
  ```

  Skipped entirely (§4 step 5) if every tool is confirmed already up to date.

## 7. Update application

Every orphan tool's existing install function (e.g. `omawsl_install_codex_cli` in
`install/terminal/app-codex-cli.sh`) currently starts with a `command -v <bin> &>/dev/null &&
return 0` guard, which is exactly what makes a plain re-run of `install`/`install.sh` a no-op for
these tools today. To let `update` force a fresh install without touching the normal
install/uninstall behavior, each of the 7 scripts is split into:

- `omawsl_<slug>_ensure_installed` — the existing guarded entry point (unchanged behavior, still
  what `install.sh`/`bin/omawsl install` call).
- `omawsl_<slug>_install_steps` — just the actual curl/npm/binary-install commands, no guard.
  Called by `omawsl_<slug>_ensure_installed` after its guard check, and called directly
  (bypassing the guard) by the new update path.

This touches all 7 app-*.sh/`apps-terminal.sh` functions listed in §3 — a real, visible refactor,
not hidden inside the new update code.

## 8. Documentation deliverable

A new `docs/updating.md`, linked from README's "What you get" section, laying out the three-way
split plainly:

- **Language runtimes & cloud tools** (Ruby, Node, Go, PHP, Python, Elixir, Rust, Java, Terraform,
  Azure CLI) → `mise upgrade`, or re-run `omawsl install language <x>` (re-pins to latest).
- **System packages** (fzf, eza, bat, zoxide, Docker Engine, VS Code, Cursor, Neovim, LazyGit,
  ...) → `sudo apt upgrade`, or the app's own Windows-side updater for GUI apps.
- **Everything else** (the 7 tools in §3, which have no native update command of their own) →
  `omawsl update`.

`bin/omawsl update` prints a one-line pointer to this doc at the end of every run (§4 step 8), so
the explanation is discoverable from the tool itself, not just from reading README cold.

## 9. Error handling

- Dirty `$OMAWSL_HOME` tree → unchanged existing behavior (refuse self-update, exit early, orphan
  tool update never runs).
- A version-check lookup failing → resolves to `unknown`, never blocks the others (§5).
- An orphan tool's install step failing during application (§7) → isolated per tool, matching
  this project's established failure-isolation pattern (`cloud-tools.sh`'s Terraform/Azure CLI
  handling): one tool's failure is reported but doesn't abort the rest of the selected updates or
  the overall `omawsl update` run.

## 10. Testing

Follows this repo's existing bats conventions (`tests/omawsl_update_test.bats`,
`tests/helpers/stubs.bash`): stub `curl`, `npm`, `gh`, and each tool's own `--version` output to
exercise the version-check adapters and the guard-bypass install-steps split without real network
calls or real installs. Existing self-update/migrate tests are unaffected.

## 11. Open questions for the implementation plan

- Confirm the exact "latest version" source for opencode and Claude Code CLI (§5) — both need a
  quick real-world check before their adapters can be written; not a design blocker, just not yet
  verified the way the other five are.
