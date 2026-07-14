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
- [ ] Deliberately leave one orphan tool (e.g. opencode) one version behind, so step 13 below
      has a real update to show instead of an "everything's current" no-op.

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

- [ ] **8. Install runs.**
      Say, while apt/mise run in the background, faster-paced than the corporate take: "Same
      terminal tooling under the hood as any omawsl install — zellij, btop, fastfetch,
      lazygit, lazydocker, gh."

- [ ] **9. Post-install tour: `bin/omawsl doctor`.**
      ```bash
      bin/omawsl doctor
      ```
      Say: "Every language, editor, and storage pick I just made, confirmed installed."

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
