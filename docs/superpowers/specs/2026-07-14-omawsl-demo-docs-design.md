# omawsl live-demo tasklists — design

**Date:** 2026-07-14
**Status:** approved
**Scope:** item 4 of the post-launch roadmap, done ahead of item 3 (docs style pass) at the
user's explicit request — item 3 remains deferred pending real user feedback (see
`docs/superpowers/specs/2026-07-14-omawsl-aliases-parity-design.md`'s sibling memory note).

## Why

The user wants to give a live demo of omawsl, the way DHH demoed Omakub itself, and needs a
concrete tasklist to follow while presenting so they know exactly what to do, say, and show —
not a general-audience walkthrough doc, a personal script. Two variants are needed because the
picker choices and framing genuinely differ: a corporate-PC demo (locked-down machine, Docker
Desktop, IT-ticket-free framing) and a personal-PC demo (full power-user tour, faster pace).

## Audience & format

Both files are **the user's own live-demo script**, not public-facing documentation — terse,
ordered, "do this, say this, show this." They are not required to read well as standalone docs
for someone who wasn't in the room; the DHH-style demo itself is the artifact people actually
watch. (This deliberately does not need to follow whatever convention item 3, the deferred docs
style pass, eventually establishes — different genre of writing, different audience.)

Each file (`docs/demo-corporate.md`, `docs/demo-personal.md`) is self-contained — no
cross-referencing the other file mid-demo — and has two parts:

1. **Prep** (done before recording, not part of the timed live flow):
   - Reset the demo machine/WSL distro to a genuinely clean slate (either a fresh VM snapshot,
     or `wsl --unregister <distro>` + re-provision).
   - **Make the `tunacinsoy/omawsl` GitHub repo public.** This is a repo-visibility change and
     per the project's standing rule (see the `feedback_confirm_before_github_remote` memory)
     needs the user's separate, explicit go-ahead at the time it's actually done — this spec
     documents it as a required prep step, but does not authorize it. Necessary because
     `boot.sh` does a plain unauthenticated `git clone`, which fails against a private repo on
     a machine with no cached GitHub credentials (a real, previously-flagged gap — see
     `project_omawsl_overview.md`'s Phase 6 operational-lessons section).
   - Anything else that would be dead air on camera (e.g., confirming the WSL2 feature itself
     is enabled at the Windows level, so `wsl --install` doesn't hit a reboot-required Windows
     feature prompt mid-recording).
2. **Live script**: numbered `- [ ]` checkbox steps in actual performed order. Each step has:
   - The literal command, if any.
   - A **Say:** line — a short narration cue, not a full script (bullet-point prompts the user
     talks around, matching their own voice, not scripted sentences to read verbatim).
   - A **⭐ Why this matters:** callout on any step that lands one of the four differentiator
     beats (see below), so it's not forgotten in the moment.

## Differentiator beats (both files, same four)

Selected from the current real feature set (verified against `bin/omawsl`'s own usage output
and `README.md`'s "What you get" section as of 2026-07-14, not assumed):

1. **It's a full CLI, not just an installer** — `theme`/`update`/`migrate`/`install`/
   `uninstall`/`doctor`; you keep using it long after day one.
2. **Real update mechanism** — `omawsl update` handles omawsl's own `git pull` + migrations,
   and separately flags the other three update paths (mise-managed languages, apt packages, and
   the 7 "orphan" tools with real GitHub-Releases/npm-registry version checks and no native
   updater of their own).
3. **Granular install/uninstall** — add or remove one language/editor/storage item later without
   replaying the whole first-run picker; `doctor` shows exactly what's installed vs. pending.
4. **Windows Terminal theme auto-sync** — `bin/omawsl theme <name>` edits the real Windows
   Terminal `settings.json` directly, the one deliberate exception to "never touch Windows-side
   files automatically," backed up first, skips gracefully if `jq`/the file can't be found.

## Live script arc (shared skeleton, both files)

1. **Cold open.** One sentence: what omawsl is, why WSL2 needed its own Omakub port.
2. `wsl --install -d Ubuntu` from literal zero (Windows-side, PowerShell as Administrator).
3. Open the fresh Ubuntu shell, run the `boot.sh` one-liner from `README.md` → first-run
   picker, narrated live as each `gum` prompt appears.
4. Docker pick (corporate: Docker Desktop; personal: Engine, the default) — narrate why.
5. Corporate only: `windows-prereq-checklist` shows a real item for Docker Desktop — narrate
   the detect-and-defer behavior and that omawsl itself never auto-installs Windows software.
6. Install runs — narrate what's happening in the background (terminal tooling, mise, etc.) to
   fill dead air while apt/mise/etc. actually run.
7. Post-install tour: `bin/omawsl doctor` — show real installed state matching what was picked.
8. Editor/AI-tool tour (corporate: VS Code + GitHub Copilot CLI, narrating the `gh auth login`
   prerequisite as a corporate-reality beat per `docs/windows-setup.md`'s existing coverage;
   personal: opencode + Claude Code CLI).
9. ⭐ `bin/omawsl theme` — cycle several of the 10 ported themes live across zellij/btop/Neovim/
   the picked editor, landing on Windows Terminal's own color scheme visibly updating too.
10. ⭐ `bin/omawsl install language <x>` — add one more language after the first-run picker,
    no replay needed.
11. ⭐ `bin/omawsl uninstall <x>` → `doctor` again to confirm it's genuinely gone.
12. ⭐ `bin/omawsl update` — corporate frames it as "safe to run later, per-tool failure
    isolation, no IT drama"; personal can show a real orphan-tool update if something is
    deliberately left outdated going into the demo (mirrors how the update-mechanism feature's
    own real verification staged a genuine version gap — see `project_omawsl_overview.md`).
13. **Close.** Recap the four differentiator beats in one breath, point back at the one-liner
    as the call to action.

## What differs between the two files, concretely

| | Corporate | Personal |
|---|---|---|
| Docker | Desktop (detect-and-defer story) | Engine (default path) |
| Languages | One pick, fast (Node.js) | Two or three, incl. one that shows mise compiling from source (Ruby on Rails) |
| Editors/AI tooling | VS Code + GitHub Copilot CLI | opencode + Claude Code CLI |
| Storage | Skip, or one (PostgreSQL) | Two (PostgreSQL + Redis) |
| Framing | "Safe on a locked-down machine," IT-ticket-free, detect-and-defer | Full power-user tour, faster pace, more picks shown |
| `windows-prereq-checklist` beat | Shown (Docker Desktop item) | Skipped (Engine mode shows nothing) |

Both files still cover the same 13-step arc and all four differentiator beats — only the
picker choices, one or two narration angles, and whether the prereq-checklist beat appears
actually change.

## Non-scope

- Does not touch `README.md`, `docs/updating.md`, or `docs/windows-setup.md` — those are
  separate, already-shipped, general-audience docs; item 3 (deferred) is where their tone gets
  revisited, not this item.
- Does not include the actual repo-visibility change (making `tunacinsoy/omawsl` public) —
  documented as a required prep step, executed only with separate explicit authorization when
  the user is actually ready to record.
- Not written to double as public documentation — no attempt to make these two files readable
  in isolation by someone who wasn't watching the demo.

## Implementation approach

Two new files, `docs/demo-corporate.md` and `docs/demo-personal.md`, content-only (no code, no
tests) — direct writing on `master`, no worktree needed.

## Addendum (2026-07-14): Windows-side setup coverage

The first version of both files started the live script at `wsl --install`, on the assumption
that Windows itself (Windows Terminal, a Nerd Font, VS Code/Docker Desktop where relevant) was
already set up. The user flagged this as non-exhaustive — the goal is a genuinely fresh Windows
OS through to the full omawsl experience, matching `docs/windows-setup.md`'s existing coverage
(Windows Terminal, fonts, Docker Desktop, VS Code, Cursor, GitHub Copilot CLI, the Windows
Terminal theme sync) rather than skipping past it.

**Split decision:** boring/slow installs (Windows Terminal from the Store, downloading and
installing a font, installing VS Code/Docker Desktop) move into **Prep** (off-camera, checklist
only) rather than the timed live script — matching the existing Prep section's own nature
(clean-slate reset, repo-visibility). Fast/visual steps stay **live**: merging the Windows
Terminal JSON fragment (~30 seconds, fixes font *and* the zellij `Alt+arrow` keybinding
collision in one edit — real "show this" content), and everything already in the live script
from `wsl --install` onward is unchanged.

**This naturally makes Windows-side Prep asymmetric between the two files, reinforcing rather
than fighting the existing corporate/personal split:**
- **Personal:** editors (opencode + Claude Code CLI) and Docker mode (Engine) need nothing
  Windows-side. Prep only grows by Windows Terminal + a Nerd Font (enhanced — full icon-glyph
  rendering, matches the "full power-user tour" framing).
- **Corporate:** VS Code, Docker Desktop, and GitHub Copilot CLI's `gh auth login` prerequisite
  all have real Windows-side or pre-install requirements. Prep grows by Windows Terminal +
  Cascadia Mono (the zero-install fallback font, bundled with Windows Terminal already — fits
  "no IT ticket needed" better than requiring a separate font download/install on a possibly
  locked-down machine) + VS Code + Docker Desktop.

**New live step, both files, inserted right after the cold open and before `wsl --install`:**
merge `windows/windows-terminal.json` (personal, paired with the enhanced font) or
`windows/windows-terminal-fallback.json` (corporate, paired with Cascadia Mono) into Windows
Terminal's real `settings.json`, narrating that it's a local JSON edit fixing two things at
once (font family + the Alt-arrow collision with zellij), sourced from files already in the
repo, not invented for the demo.
