# omawsl — Curriculum Index

This is a 21-lesson curriculum for rebuilding omawsl from scratch, phase by phase, in
the order it was actually built. See `OUTLINE.md` for how these phases were derived
from the project's own commit history and plan documents.

## How each lesson works

1. **Open-book lesson.** Read the lesson file. It shows the real original code for
   that phase and explains it — the syntax, the design decision at each step, and why
   it was made that way instead of some plausible alternative.
2. **Closed-book exercise.** Close the lesson and rebuild that phase's exercise from
   scratch, blind, in the matching `practice/NN-<phase-slug>/` directory. No peeking
   at the original source while you write.
3. **Behavioral check.** Run that phase's `check.sh`. It never compares your code
   character-for-character against the original — it runs your implementation and
   asserts on what it actually does. A passing check means your solution is
   behaviorally correct, even if it doesn't look anything like the original.
4. **Diff, as a study aid only.** Once your check passes, you can diff your solution
   against the original code (shown in the lesson's Walkthrough) purely to compare
   style and approach. It is never the grade — only the check is.

Baseline level for this curriculum: **true beginner**. Lessons build up general
programming and Linux/bash concepts as they come up, not just this project's specifics.

## Lessons

**Core build (Phases 1-7)** — the largest, most foundational phases; do these first.

1. [Core skeleton](01-core-skeleton.md) — orchestration, `boot.sh`/`install.sh`, shared
   helpers, stubbed bats testing.
2. [Docker & storage](02-docker-and-storage.md) — detect-and-defer, idempotent
   containers, real-machine bugs tests can't catch.
3. [Languages & cloud tools](03-languages-and-cloud-tools.md) — `mise`, third-party
   apt repos, failure isolation, PATH-ordering bugs.
4. [Editors & AI tooling](04-editors-and-ai-tooling.md) — fan-out install scripts,
   shared config, isolating failures under `set -e`.
5. [Theming](05-theming.md) — porting themes across five config formats, the one
   sanctioned Windows-file edit.
6. [Windows docs & README](06-windows-docs-and-readme.md) — documenting the boundary
   the installer can't cross.
7. [CLI completion](07-cli-completion.md) — a shared registry, `update`/`migrate`,
   `doctor`, `uninstall` as install-in-reverse.

**Post-v1 features & hardening (Phases 8-21)** — smaller, more independent additions.

8. [Self-update mechanism](08-self-update-mechanism.md) — orphan-tools registry,
   bounded-wait parallel version checks.
9. [Aliases & demo docs](09-aliases-and-demo-docs.md) — upstream alias parity,
   documentation as a tested artifact.
10. [Real-world hardening, round 1](10-real-world-hardening-round-1.md) — bugs only a
    real `curl | bash` run exposes.
11. [Native VS Code/Cursor theme sync](11-native-vscode-cursor-theme-sync.md) —
    JSONC-safe merging, backups, isolated extension installs.
12. [Language toolchain hardening](12-language-toolchain-hardening.md) — compiled
    extensions needing `-dev` packages, install ordering.
13. [Cloud CLIs menu](13-cloud-clis-menu.md) — splitting a picker option, keeping a
    registry consistent across a refactor.
14. [Ubuntu 24.04 & editor-picker fixes](14-ubuntu-24-04-and-editor-picker-fixes.md) —
    stale idempotency guards, portability fixes.
15. [Corp-safe config editing](15-corp-safe-config-editing.md) — never overwrite the
    user's own dotfiles again.
16. [Upstream install hardening](16-upstream-install-hardening.md) — installing from a
    tool's own GitHub releases instead of stale apt packages.
17. [Docker daemon proxy autoconfig](17-docker-daemon-proxy-autoconfig.md) — detecting
    a corporate proxy, not clobbering the user's own config.
18. [Copilot CLI autopilot mode](18-copilot-autopilot-mode.md) — an opt-in alias,
    persisted correctly through install and uninstall.
19. [Starship as default prompt](19-starship-default-prompt.md) — replacing `PS1`,
    ordering against `mise`, recoloring for 10 themes.
20. [Test-suite hardening](20-test-suite-hardening.md) — false positives, temp-dir
    leaks, and test drift as their own bug class.
21. [Neovim treesitter & npm warnings](21-neovim-treesitter-and-npm-warnings.md) —
    precise fixes over blanket suppression.
