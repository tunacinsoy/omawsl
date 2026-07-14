# omawsl Live-Demo Tasklists Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Write two self-contained, checkbox-driven live-demo scripts (`docs/demo-corporate.md`, `docs/demo-personal.md`) the user follows while presenting/recording omawsl, DHH-omakub-demo style.

**Architecture:** Two new markdown files, content-only, no code changes. Each follows the same 13-step arc from the design spec, with different picker choices/framing per file. No shared partial/include mechanism — each file is fully self-contained per the spec's explicit "no cross-referencing mid-demo" requirement.

**Tech Stack:** Markdown only.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-14-omawsl-demo-docs-design.md` — every command, slug, and theme name below is copied verbatim from it or verified directly against the real source in this repo (`bin/omawsl-sub/items.sh`, `bin/omawsl-sub/theme.sh`, `bin/omawsl` usage output) as of 2026-07-14. Do not invent slugs/commands not listed here.
- Audience: the user's own live-demo script — terse, ordered, "do this, say this, show this." Not general-audience documentation. Say: lines are short narration *cues*, not full scripts to read verbatim.
- Both files use `- [ ]` checkbox steps, a **Say:** line per step (where narration matters), and a **⭐ Why this matters:** callout on the 4 differentiator beats.
- Verified exact slugs (from `bin/omawsl-sub/items.sh`):
  - Languages: `ruby` (Ruby on Rails), `node` (Node.js), `go` (Go), `php` (PHP), `python` (Python), `elixir` (Elixir), `rust` (Rust), `java` (Java), `terraform` (Terraform), `azure` (Azure CLI)
  - Editors: `vscode` (VS Code), `neovim` (Neovim), `opencode` (opencode), `cursor` (Cursor), `claude` (Claude Code CLI), `codex` (Codex CLI), `gh-copilot` (GitHub Copilot CLI), `gemini` (Gemini CLI)
  - Storage: `mysql` (MySQL), `redis` (Redis), `postgresql` (PostgreSQL)
  - Command shape: `bin/omawsl install <category> <slug>` (e.g. `bin/omawsl install language go`), `bin/omawsl uninstall <slug>` (e.g. `bin/omawsl uninstall go`)
- Verified exact theme folder names (from `bin/omawsl-sub/theme.sh`, Omakub's own picker order): `catppuccin`, `everforest`, `gruvbox`, `kanagawa`, `matte-black`, `nord`, `osaka-jade`, `ristretto`, `rose-pine`, `tokyo-night`. Command: `bin/omawsl theme <name>`, or `bin/omawsl theme` with no argument for the interactive picker.
- The real one-liner (from `README.md`): `curl -fsSL https://raw.githubusercontent.com/tunacinsoy/omawsl/master/boot.sh | bash`

---

### Task 1: `docs/demo-corporate.md`

**Files:**
- Create: `docs/demo-corporate.md`

**Interfaces:**
- Consumes: nothing (standalone content file).
- Produces: nothing consumed by later tasks — Task 2 is an independent file with its own content, not built on this one.

- [ ] **Step 1: Write the Prep section**

At the top of the file, before the live script, write:

```markdown
# omawsl live demo — corporate PC

**Audience for this file:** you, mid-demo. Terse cues, not a script to read verbatim.

## Prep (before recording — not part of the timed demo)

- [ ] Reset the demo machine/WSL distro to a clean slate: either restore a fresh VM snapshot,
      or `wsl --unregister <distro-name>` on a scratch distro you don't otherwise use.
- [ ] Confirm the Windows-side WSL2 feature itself is already enabled, so `wsl --install`
      below doesn't hit a "restart required" prompt live on camera.
- [ ] **Make the repo public.** `boot.sh` does a plain unauthenticated `git clone` — on a
      genuinely fresh machine with no cached GitHub credentials, cloning a private repo fails.
      Ask Claude to run this when you're actually ready to record (repo-visibility changes need
      a separate explicit go-ahead each time, not decided in advance):
      `gh repo edit tunacinsoy/omawsl --visibility public`
```

- [ ] **Step 2: Write steps 1-3 of the live script (cold open through first-run picker)**

```markdown
## Live script

- [ ] **1. Cold open.**
      Say: "This is omawsl — Omakub's 'one script, done' experience, ported for WSL2 on
      Windows 11. Everything you're about to see runs from a completely fresh machine."

- [ ] **2. Install WSL2 + Ubuntu from literal zero.**
      In PowerShell, as Administrator:
      ```powershell
      wsl --install -d Ubuntu
      ```
      Say: "This is the only Windows-side command in the entire demo."

- [ ] **3. Open the fresh Ubuntu shell, run the one-liner.**
      ```bash
      curl -fsSL https://raw.githubusercontent.com/tunacinsoy/omawsl/master/boot.sh | bash
      ```
      Say, while the picker prompts appear one at a time: narrate each `gum` prompt as it
      shows up — don't pre-explain the whole picker up front, react to it live.
```

- [ ] **Step 3: Write steps 4-9 (picker choices: Docker, language, editor, storage, then the prereq checklist)**

```markdown
- [ ] **4. Docker pick: Docker Desktop for Windows.**
      At the Docker picker, choose "Docker Desktop for Windows," not the Engine default.
      Say: "On a corporate machine you often don't have root/admin to install Docker Engine
      natively inside WSL — Docker Desktop is the safer default here, and omawsl detects it's
      not installed yet and defers instead of failing."

- [ ] **5. Pick languages: Node.js only.**
      At the language picker, select just Node.js.
      Say: "Keeping this to one pick — Node's fast to install and it's the one most teams
      actually need day one."

- [ ] **6. Pick editors/AI tooling: VS Code + GitHub Copilot CLI.**
      Say: "VS Code because it's the editor most corporate teams already standardize on, and
      GitHub Copilot CLI to show the one AI-tool pick that has a real prerequisite."

- [ ] **7. Pick storage: PostgreSQL.**
      Say: "One storage engine, containerized automatically — no manual `docker run` needed
      once Docker Desktop is actually up."

- [ ] **8. `gh auth login` reminder lands (if not already run).**
      Say: "GitHub Copilot CLI needs an authenticated `gh` session before its own install step
      — a fresh machine doesn't have one yet. omawsl isolates that one failure instead of
      aborting the whole run if you forget to do this first."

- [ ] **9. windows-prereq-checklist appears.**
      Say: "This is the one moment omawsl asks you to step outside WSL. It only shows items
      relevant to what you actually picked — nothing generic." Point out the Docker Desktop
      item specifically. Choose to continue past it (Docker Desktop install itself is out of
      scope for this demo take).
```

- [ ] **Step 4: Write steps 10-12 (install runs, doctor, editor tour)**

```markdown
- [ ] **10. Install runs.**
      Say, while apt/mise run in the background: "This is installing the terminal tooling —
      zellij, btop, fastfetch, lazygit, lazydocker, gh — plus Node, VS Code, and Postgres.
      Nothing here needed admin rights beyond what WSL's own sudo already grants inside the
      distro."

- [ ] **11. Post-install tour: `bin/omawsl doctor`.**
      ```bash
      bin/omawsl doctor
      ```
      Say: "doctor reports exactly what's installed versus still pending — this becomes your
      source of truth any time later, not just at first install."

- [ ] **12. Editor tour: VS Code.**
      Open VS Code via `code .` from the WSL shell to show the Remote-WSL connection working.
      Say: "This connected automatically the first time `code` was reachable — no manual
      extension install needed on your end."
```

- [ ] **Step 5: Write steps 13-17 (differentiator beats + close)**

```markdown
- [ ] **13. ⭐ Theme cycling: `bin/omawsl theme`.**
      ```bash
      bin/omawsl theme catppuccin
      bin/omawsl theme nord
      bin/omawsl theme tokyo-night
      ```
      Say while each one lands: "Watch the Windows Terminal color scheme change too — that's
      not manual. This is the one deliberate exception to omawsl never touching Windows-side
      files automatically: it's a local JSON edit to an app you already have installed, backed
      up first, not a network install."
      ⭐ Why this matters: Windows Terminal theme auto-sync — a real, visible payoff with zero
      manual Windows-side steps.

- [ ] **14. ⭐ Granular install: `bin/omawsl install language terraform`.**
      ```bash
      bin/omawsl install language terraform
      ```
      Say: "Didn't pick Terraform during first-run — a lot of corporate teams add cloud
      tooling after the fact once they know what they need. This adds it with no replay of
      the whole picker."
      ⭐ Why this matters: granular install/uninstall — you're not locked into first-run choices.

- [ ] **15. ⭐ Granular uninstall: `bin/omawsl uninstall terraform` → `doctor` again.**
      ```bash
      bin/omawsl uninstall terraform
      bin/omawsl doctor
      ```
      Say: "And it comes back out just as cleanly — doctor confirms it's genuinely gone, not
      just unlisted."

- [ ] **16. ⭐ Update mechanism: `bin/omawsl update`.**
      ```bash
      bin/omawsl update
      ```
      Say: "This is safe to run any time after today — it pulls the latest omawsl itself,
      then separately tells you about the other three update paths: your mise-managed
      languages, apt packages, and the handful of tools like lazydocker and the AI CLIs that
      have no updater of their own. Nothing here needs an IT ticket."
      ⭐ Why this matters: omawsl is a full CLI you keep using, not a one-shot install script.

- [ ] **17. Close.**
      Say: "Four things to remember: it's a full CLI, not just an installer. It updates
      everything, including the tools nobody else has a good update story for. You can add or
      remove any single piece without redoing the whole setup. And the one time it touches
      Windows at all, it's a local file edit you can see and revert." Point back at the
      one-liner from step 3 as the takeaway.
```

- [ ] **Step 6: Read the finished file back and check it against the spec**

Open `docs/demo-corporate.md` and confirm against
`docs/superpowers/specs/2026-07-14-omawsl-demo-docs-design.md`:
- All 17 numbered live-script steps present, in order, covering the spec's 13-step arc (picker
  choices broken out into individual steps 4-9, matching how Task 2/`docs/demo-personal.md`
  also breaks out its own picker choices).
- All 4 differentiator beats have a ⭐ callout.
- Docker Desktop (not Engine) picked; `windows-prereq-checklist` beat present; one language
  (Node.js) picked during first-run, matching the spec's "one pick, fast" corporate guidance;
  VS Code + GitHub Copilot CLI as the editor pick; one storage engine (PostgreSQL).
- The granular install/uninstall beat (steps 14-15) uses `terraform` — a slug NOT already
  picked during first-run (step 5 only picked `node`) — so the demo is genuinely adding/
  removing something new, not re-installing what's already there.

- [ ] **Step 7: Commit**

```bash
git add docs/demo-corporate.md
git commit -m "docs: add corporate-PC live-demo script"
```

---

### Task 2: `docs/demo-personal.md`

**Files:**
- Create: `docs/demo-personal.md`

**Interfaces:**
- Consumes: nothing (standalone content file, independent of Task 1's output).
- Produces: nothing.

- [ ] **Step 1: Write the Prep section**

```markdown
# omawsl live demo — personal PC

**Audience for this file:** you, mid-demo. Terse cues, not a script to read verbatim.

## Prep (before recording — not part of the timed demo)

- [ ] Reset the demo machine/WSL distro to a clean slate: either restore a fresh VM snapshot,
      or `wsl --unregister <distro-name>` on a scratch distro you don't otherwise use.
- [ ] Confirm the Windows-side WSL2 feature itself is already enabled, so `wsl --install`
      below doesn't hit a "restart required" prompt live on camera.
- [ ] **Make the repo public**, if not already done for the corporate-PC take. Ask Claude to
      run this when you're actually ready to record (repo-visibility changes need a separate
      explicit go-ahead each time):
      `gh repo edit tunacinsoy/omawsl --visibility public`
```

- [ ] **Step 2: Write steps 1-3 of the live script (cold open through first-run picker)**

```markdown
## Live script

- [ ] **1. Cold open.**
      Say: "This is omawsl — Omakub's 'one script, done' experience, ported for WSL2 on
      Windows 11. This is my own daily-driver setup, full power-user tour."

- [ ] **2. Install WSL2 + Ubuntu from literal zero.**
      In PowerShell, as Administrator:
      ```powershell
      wsl --install -d Ubuntu
      ```

- [ ] **3. Open the fresh Ubuntu shell, run the one-liner.**
      ```bash
      curl -fsSL https://raw.githubusercontent.com/tunacinsoy/omawsl/master/boot.sh | bash
      ```
      Say, while the picker prompts appear one at a time: narrate each `gum` prompt live,
      move faster than the corporate take — this is the "everything on" tour.
```

- [ ] **Step 3: Write step 4 (Docker Engine pick, no prereq-checklist beat)**

```markdown
- [ ] **4. Docker pick: Engine (the default).**
      At the Docker picker, take the default Engine-only option.
      Say: "This is the default because it needs nothing extra on the Windows side — native
      `docker-ce` straight inside WSL2." (No `windows-prereq-checklist` beat here — Engine mode
      has nothing to flag.)

- [ ] **5. Pick languages: Ruby on Rails + Go.**
      At the language picker, select both.
      Say, once the install reaches Rails: "Watch this one — Rails installs `gem`s under a
      real compiled Ruby via mise, not a pre-built package. This is the slowest single step in
      the whole install, and it's the one place omawsl had to get PATH/toolchain ordering
      exactly right in development."

- [ ] **6. Pick editors/AI tooling: opencode + Claude Code CLI.**
      Say: "These two need nothing extra on the Windows side, unlike VS Code/Cursor — good
      pick for a pure-terminal power-user flow."

- [ ] **7. Pick storage: PostgreSQL + Redis.**
      Say: "Both come up as containers automatically — no manual `docker run` needed."
```

- [ ] **Step 4: Write steps 8-9 (install runs, doctor)**

```markdown
- [ ] **8. Install runs.**
      Say, while apt/mise run in the background, faster-paced than the corporate take: "Same
      terminal tooling under the hood as any omawsl install — zellij, btop, fastfetch,
      lazygit, lazydocker, gh."

- [ ] **9. Post-install tour: `bin/omawsl doctor`.**
      ```bash
      bin/omawsl doctor
      ```
      Say: "Every language, editor, and storage pick I just made, confirmed installed."
```

- [ ] **Step 5: Write steps 10-14 (differentiator beats + close, personal-flavored)**

```markdown
- [ ] **10. ⭐ Theme cycling: `bin/omawsl theme`.**
      ```bash
      bin/omawsl theme
      ```
      Use the interactive picker this time (not named args like the corporate take) — cycle
      through several: catppuccin, gruvbox, rose-pine, osaka-jade.
      Say: "Ten ported Omakub themes, applied consistently across zellij, btop, Neovim,
      opencode, and — watch the tab bar — Windows Terminal itself, live."
      ⭐ Why this matters: Windows Terminal theme auto-sync — the one deliberate exception to
      omawsl never touching Windows-side files automatically.

- [ ] **11. ⭐ Granular install: `bin/omawsl install language rust`.**
      ```bash
      bin/omawsl install language rust
      ```
      Say: "Didn't pick Rust up front — adding it now, no picker replay."
      ⭐ Why this matters: granular install/uninstall.

- [ ] **12. ⭐ Granular uninstall: `bin/omawsl uninstall rust` → `doctor` again.**
      ```bash
      bin/omawsl uninstall rust
      bin/omawsl doctor
      ```
      Say: "And back out cleanly — confirmed gone, not just hidden."

- [ ] **13. ⭐ Update mechanism: `bin/omawsl update`, with a real outdated tool.**
      Before recording, deliberately leave one orphan tool (e.g. opencode) one version behind
      so this step has something real to show, not just an "up to date" no-op.
      ```bash
      bin/omawsl update
      ```
      Say: "This checks its own git history, then separately flags mise-managed languages, apt
      packages, and the tools like opencode here with no native updater — real version checks
      against GitHub/npm, not guesses. Picker's pre-checked for anything actually outdated."
      ⭐ Why this matters: omawsl is a full CLI you keep using, and the update story covers
      tools nothing else updates for you.

- [ ] **14. Close.**
      Say: "Four things: full CLI, not a one-shot script. Real updates, including the tools
      nobody else covers. Add or remove any single piece without redoing setup. And the one
      Windows-side touch is a visible, reversible local file edit." Point back at the one-liner
      from step 3.
```

- [ ] **Step 6: Read the finished file back and check it against the spec**

Open `docs/demo-personal.md` and confirm against
`docs/superpowers/specs/2026-07-14-omawsl-demo-docs-design.md`:
- All 4 differentiator beats have a ⭐ callout.
- Docker Engine (default) picked; no `windows-prereq-checklist` beat; opencode + Claude Code
  CLI as the editor pick; two-three language picks including one (Rails) that shows mise
  compiling from source; two storage picks (PostgreSQL + Redis) — matches the spec's "full
  power-user tour" personal guidance.
- Confirm this file and `docs/demo-corporate.md` share the same underlying arc (cold open →
  WSL install → one-liner → Docker pick → [prereq checklist if applicable] → install runs →
  doctor → editors → theme → granular install → granular uninstall → update → close) even
  though the concrete picks differ.

- [ ] **Step 7: Commit**

```bash
git add docs/demo-personal.md
git commit -m "docs: add personal-PC live-demo script"
```
