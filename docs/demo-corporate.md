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
