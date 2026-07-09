# Phase 5 (Theming) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port all 10 Omakub themes to `themes/<name>/`, ship `bin/omawsl theme <name>` (the first `bin/omawsl` subcommand — the rest arrive in Phase 7), and automatically sync the applied theme's colors into Windows Terminal's own `settings.json` via `jq`. Also close two real gaps this phase's own scope depends on: `configs/zellij.kdl` (Omakub's real keybindings) and a minimal `configs/btop.conf` were never actually ported in Phase 1 despite being listed as Phase-1 deliverables — without them, there is no base config for the theme step to sed-patch and nothing for the zellij keybinding-fidelity check to verify against.

**Architecture:** Mirrors Omakub's own `bin/omakub-sub/theme.sh` mechanism almost exactly (confirmed against the real upstream source, see Research below): copy each per-tool theme file into that tool's own config location, then `sed`-patch the *active* theme reference in the tool's main config. Two mechanisms are new, not present upstream: the Windows Terminal sync — Alacritty's `themes/<name>/alacritty.toml` is dropped (no Alacritty on Windows) and replaced by a hand-derived `themes/<name>/windows-terminal-scheme.json` (Windows Terminal's own native color-scheme JSON shape), merged into the real `settings.json` via `jq`, chosen over `sed` per the design spec's own explicit recommendation since `schemes` is a nested JSON array, not a single-line key — and opencode theming, which has no Omakub precedent at all but does have a real, current theme setting of its own (confirmed via research, not assumed), wired in for the 6 of 10 omawsl themes that match one of opencode's built-in presets. `bin/omawsl` is a new, minimal command dispatcher (`bin/omawsl <command> [args]`) with exactly one subcommand wired up this phase (`theme`); its shape (a thin dispatcher sourcing one `bin/omawsl-sub/<command>.sh` file per subcommand) is designed so Phase 7 can add `update`/`migrate`/`uninstall`/`install`/`doctor` without restructuring anything built here.

**Tech Stack:** Bash (`set -euo pipefail`), `jq` (new dependency — added to the always-on apt install list), `gum choose` (already installed, Phase 1), `sed` (only for single-line theme-reference patches, matching upstream), `cmd.exe`/`wslpath` (Win32 interop, for resolving the Windows user profile directory), bats-core (already vendored).

## Global Constraints

- Every script uses `set -euo pipefail` (project-wide convention, all phases).
- Never assume the Windows username matches `$USER` — resolve the Windows profile directory dynamically via `cmd.exe`, never by string-assembling a path (design spec §11).
- Prefer `jq` over `sed` for the Windows Terminal `settings.json` edit specifically, and always back up the file first (`settings.json.bak`) before writing (design spec §11) — a corrupted `settings.json` breaks the user's whole terminal, not just the theme.
- `bin/omawsl theme <name>` is the **one exception** to "omawsl never auto-edits Windows-side files" (design spec §2, §11): it's a local JSON edit to an already-installed app, no network call, no admin rights, and it must skip gracefully (never abort, never crash the rest of the command) if `jq` or Windows Terminal's `settings.json` can't be found.
- Nothing pre-selected/forced on: theme application only ever runs when the user explicitly runs `bin/omawsl theme`, never automatically during `install.sh`.
- Files newly deployed to `$HOME` that a user might hand-edit later (`~/.config/zellij/config.kdl`, `~/.config/btop/btop.conf`) must never be silently overwritten on a repeat `install.sh` run — same non-destructive guard already used for `~/.config/nvim` in Phase 4's `app-neovim.sh`.
- Repo-authored files checked out from this Windows-hosted git repo cannot be trusted to carry their executable bit (confirmed root cause of a real Phase-1-era bug in `boot.sh`, worked around there via `exec bash "$OMAWSL_HOME/install.sh"` instead of a bare `exec`) — any new file this plan makes directly user-invocable must use the same `bash <path>` wrapper pattern, not rely on `chmod +x` surviving a git checkout.

## Research (verified against real upstream source — see citations below)

All theme color data, keybindings, and mechanism code in this plan was fetched directly from `github.com/basecamp/omakub` (`master` branch) and `github.com/microsoft/terminal` (`main` branch, `src/cascadia/TerminalSettingsModel/defaults.json`) — nothing here is invented. Key findings that shape the tasks below:

1. **Omakub's real theme mechanism** (`bin/omakub-sub/theme.sh`): copies `themes/$THEME/zellij.kdl` to `~/.config/zellij/themes/$THEME.kdl`, then `sed -i 's/theme ".*"/theme "$THEME"/g' ~/.config/zellij/config.kdl` — this **requires** `~/.config/zellij/config.kdl` to already exist with a `theme "..."` line, which is exactly the gap Task 1 closes. Same shape for btop (`color_theme = "..."` in `~/.config/btop/btop.conf`). Neovim's `theme.lua` is only copied `if [ -d "$HOME/.config/nvim" ]`. VS Code's helper (`themes/set-vscode-theme.sh`) installs the extension and `sed`-patches `workbench.colorTheme`.
2. **Omakub's real `configs/zellij.kdl`** (fetched in full — see Task 1) runs zellij in `default_mode "locked"` with `clear-defaults=true`: almost nothing fires on a bare keypress except `Ctrl g` (unlock into `normal` mode) and a set of `Alt+...` bindings shared between `normal` and `locked`. This "locked by default" model is the main thing that needs reconciling against Windows Terminal's own default keybindings (Task 8).
3. **All 10 theme folders** (`catppuccin`, `everforest`, `gruvbox`, `kanagawa`, `matte-black`, `nord`, `osaka-jade`, `ristretto`, `rose-pine`, `tokyo-night`) were fetched in full — every one has all 5 needed files, none missing. Exact hex values are reproduced verbatim in Tasks 3–5.
4. **Windows Terminal's real default keybindings** (`microsoft/terminal` `main` branch `defaults.json`, cross-checked against the docs page, which is confirmed slightly stale in places) identify exactly one direct, real collision with Omakub's zellij keybindings: `Alt+Left/Down/Up/Right` is bound by both Windows Terminal (`Terminal.MoveFocus*`) and zellij (`shared_among "normal" "locked"` → `MoveFocusOrTab`/`MoveFocus`) — see Task 8 for the full analysis and the fix.
5. **opencode does have a real, current theme setting** (design spec §11 marks this "best-effort... if not, skipped" — checked, and the answer is yes): `~/.config/opencode/tui.json`, a `"theme"` key, documented at `opencode.ai/docs/themes/`. It ships built-in named presets, six of which are direct 1:1 matches for omawsl's own theme names (`tokyonight`, `everforest`, `catppuccin`, `gruvbox`, `kanagawa`, `nord`); the other four omawsl themes (`matte-black`, `osaka-jade`, `ristretto`, `rose-pine`) have no built-in opencode preset. opencode also supports fully custom theme JSON files for arbitrary color sets, but that's a separate, unverified schema — building it for these 4 remaining themes is out of scope here (Task 7 wires in the 6 direct matches only and no-ops for the rest, matching the spec's own "skipped rather than forcing a workaround" guidance).

---

### Task 1: Port `configs/zellij.kdl` and `configs/btop.conf`, deploy both, add `jq`

**Files:**
- Create: `configs/zellij.kdl`
- Create: `configs/btop.conf`
- Modify: `install/terminal/apps-terminal.sh`
- Test: `tests/apps_terminal_test.bats`

**Interfaces:**
- Produces: `omawsl_install_zellij_config` (no args), `omawsl_install_btop_config` (no args) — both called unconditionally from `omawsl_install_terminal_apps`, after their respective tool installs.
- Consumes: nothing new.

- [ ] **Step 1: Write `configs/zellij.kdl`** — ported verbatim from `github.com/basecamp/omakub/blob/master/configs/zellij.kdl`. This is the base config `bin/omawsl theme` (Task 7) will `sed`-patch the `theme "..."` line of, and what Task 9's human verification exercises every binding of.

```kdl
theme "tokyo-night"
default_layout "compact"
on_force_close "quit"

default_mode "locked"
keybinds clear-defaults=true {
    locked {
        bind "Ctrl g" { SwitchToMode "normal"; }
    }
    pane {
        bind "Left" { MoveFocus "left"; }
        bind "Down" { MoveFocus "down"; }
        bind "Up" { MoveFocus "up"; }
        bind "Right" { MoveFocus "right"; }
        bind "c" { SwitchToMode "renamepane"; PaneNameInput 0; }
        bind "d" { NewPane "down"; SwitchToMode "locked"; }
        bind "e" { TogglePaneEmbedOrFloating; SwitchToMode "locked"; }
        bind "f" { ToggleFocusFullscreen; SwitchToMode "locked"; }
        bind "h" { MoveFocus "left"; }
        bind "j" { MoveFocus "down"; }
        bind "k" { MoveFocus "up"; }
        bind "l" { MoveFocus "right"; }
        bind "n" { NewPane; SwitchToMode "locked"; }
        bind "p" { SwitchToMode "normal"; }
        bind "r" { NewPane "right"; SwitchToMode "locked"; }
        bind "w" { ToggleFloatingPanes; SwitchToMode "locked"; }
        bind "x" { CloseFocus; SwitchToMode "locked"; }
        bind "z" { TogglePaneFrames; SwitchToMode "locked"; }
        bind "Tab" { SwitchFocus; }
    }
    tab {
        bind "Left" { GoToPreviousTab; }
        bind "Down" { GoToNextTab; }
        bind "Up" { GoToPreviousTab; }
        bind "Right" { GoToNextTab; }
        bind "1" { GoToTab 1; SwitchToMode "locked"; }
        bind "2" { GoToTab 2; SwitchToMode "locked"; }
        bind "3" { GoToTab 3; SwitchToMode "locked"; }
        bind "4" { GoToTab 4; SwitchToMode "locked"; }
        bind "5" { GoToTab 5; SwitchToMode "locked"; }
        bind "6" { GoToTab 6; SwitchToMode "locked"; }
        bind "7" { GoToTab 7; SwitchToMode "locked"; }
        bind "8" { GoToTab 8; SwitchToMode "locked"; }
        bind "9" { GoToTab 9; SwitchToMode "locked"; }
        bind "[" { BreakPaneLeft; SwitchToMode "locked"; }
        bind "]" { BreakPaneRight; SwitchToMode "locked"; }
        bind "b" { BreakPane; SwitchToMode "locked"; }
        bind "h" { GoToPreviousTab; }
        bind "j" { GoToNextTab; }
        bind "k" { GoToPreviousTab; }
        bind "l" { GoToNextTab; }
        bind "n" { NewTab; SwitchToMode "locked"; }
        bind "r" { SwitchToMode "renametab"; TabNameInput 0; }
        bind "s" { ToggleActiveSyncTab; SwitchToMode "locked"; }
        bind "t" { SwitchToMode "normal"; }
        bind "x" { CloseTab; SwitchToMode "locked"; }
        bind "Tab" { ToggleTab; }
    }
    resize {
        bind "Left" { Resize "Increase left"; }
        bind "Down" { Resize "Increase down"; }
        bind "Up" { Resize "Increase up"; }
        bind "Right" { Resize "Increase right"; }
        bind "+" { Resize "Increase"; }
        bind "-" { Resize "Decrease"; }
        bind "=" { Resize "Increase"; }
        bind "H" { Resize "Decrease left"; }
        bind "J" { Resize "Decrease down"; }
        bind "K" { Resize "Decrease up"; }
        bind "L" { Resize "Decrease right"; }
        bind "h" { Resize "Increase left"; }
        bind "j" { Resize "Increase down"; }
        bind "k" { Resize "Increase up"; }
        bind "l" { Resize "Increase right"; }
        bind "r" { SwitchToMode "normal"; }
    }
    move {
        bind "Left" { MovePane "left"; }
        bind "Down" { MovePane "down"; }
        bind "Up" { MovePane "up"; }
        bind "Right" { MovePane "right"; }
        bind "h" { MovePane "left"; }
        bind "j" { MovePane "down"; }
        bind "k" { MovePane "up"; }
        bind "l" { MovePane "right"; }
        bind "m" { SwitchToMode "normal"; }
        bind "n" { MovePane; }
        bind "p" { MovePaneBackwards; }
        bind "Tab" { MovePane; }
    }
    scroll {
        bind "Alt Left" { MoveFocusOrTab "left"; SwitchToMode "locked"; }
        bind "Alt Down" { MoveFocus "down"; SwitchToMode "locked"; }
        bind "Alt Up" { MoveFocus "up"; SwitchToMode "locked"; }
        bind "Alt Right" { MoveFocusOrTab "right"; SwitchToMode "locked"; }
        bind "e" { EditScrollback; SwitchToMode "locked"; }
        bind "f" { SwitchToMode "entersearch"; SearchInput 0; }
        bind "Alt h" { MoveFocusOrTab "left"; SwitchToMode "locked"; }
        bind "Alt j" { MoveFocus "down"; SwitchToMode "locked"; }
        bind "Alt k" { MoveFocus "up"; SwitchToMode "locked"; }
        bind "Alt l" { MoveFocusOrTab "right"; SwitchToMode "locked"; }
        bind "s" { SwitchToMode "normal"; }
    }
    search {
        bind "c" { SearchToggleOption "CaseSensitivity"; }
        bind "n" { Search "down"; }
        bind "o" { SearchToggleOption "WholeWord"; }
        bind "p" { Search "up"; }
        bind "w" { SearchToggleOption "Wrap"; }
    }
    session {
        bind "c" {
            LaunchOrFocusPlugin "configuration" {
                floating true
                move_to_focused_tab true
            }
            SwitchToMode "locked"
        }
        bind "d" { Detach; }
        bind "o" { SwitchToMode "normal"; }
        bind "p" {
            LaunchOrFocusPlugin "plugin-manager" {
                floating true
                move_to_focused_tab true
            }
            SwitchToMode "locked"
        }
        bind "w" {
            LaunchOrFocusPlugin "session-manager" {
                floating true
                move_to_focused_tab true
            }
            SwitchToMode "locked"
        }
    }
    shared_among "normal" "locked" {
        bind "Alt Left" { MoveFocusOrTab "left"; }
        bind "Alt Down" { MoveFocus "down"; }
        bind "Alt Up" { MoveFocus "up"; }
        bind "Alt Right" { MoveFocusOrTab "right"; }
        bind "Alt +" { Resize "Increase"; }
        bind "Alt -" { Resize "Decrease"; }
        bind "Alt =" { Resize "Increase"; }
        bind "Alt [" { PreviousSwapLayout; }
        bind "Alt ]" { NextSwapLayout; }
        bind "Alt f" { ToggleFloatingPanes; }
        bind "Alt h" { MoveFocusOrTab "left"; }
        bind "Alt i" { MoveTab "left"; }
        bind "Alt j" { MoveFocus "down"; }
        bind "Alt k" { MoveFocus "up"; }
        bind "Alt l" { MoveFocusOrTab "right"; }
        bind "Alt n" { NewPane; }
        bind "Alt o" { MoveTab "right"; }
    }
    shared_except "locked" "renametab" "renamepane" {
        bind "Ctrl g" { SwitchToMode "locked"; }
        bind "Ctrl q" { Quit; }
    }
    shared_except "locked" "entersearch" {
        bind "Enter" { SwitchToMode "locked"; }
    }
    shared_except "locked" "entersearch" "renametab" "renamepane" {
        bind "Esc" { SwitchToMode "locked"; }
    }
    shared_except "locked" "entersearch" "renametab" "renamepane" "move" {
        bind "m" { SwitchToMode "move"; }
    }
    shared_except "locked" "entersearch" "search" "renametab" "renamepane" "session" {
        bind "o" { SwitchToMode "session"; }
    }
    shared_except "locked" "tab" "entersearch" "renametab" "renamepane" {
        bind "t" { SwitchToMode "tab"; }
    }
    shared_except "locked" "tab" "scroll" "entersearch" "renametab" "renamepane" {
        bind "s" { SwitchToMode "scroll"; }
    }
    shared_among "normal" "resize" "tab" "scroll" "prompt" "tmux" {
        bind "p" { SwitchToMode "pane"; }
    }
    shared_except "locked" "resize" "pane" "tab" "entersearch" "renametab" "renamepane" {
        bind "r" { SwitchToMode "resize"; }
    }
    shared_among "scroll" "search" {
        bind "PageDown" { PageScrollDown; }
        bind "PageUp" { PageScrollUp; }
        bind "Left" { PageScrollUp; }
        bind "Down" { ScrollDown; }
        bind "Up" { ScrollUp; }
        bind "Right" { PageScrollDown; }
        bind "Ctrl b" { PageScrollUp; }
        bind "Ctrl c" { ScrollToBottom; SwitchToMode "locked"; }
        bind "d" { HalfPageScrollDown; }
        bind "Ctrl f" { PageScrollDown; }
        bind "h" { PageScrollUp; }
        bind "j" { ScrollDown; }
        bind "k" { ScrollUp; }
        bind "l" { PageScrollDown; }
        bind "u" { HalfPageScrollUp; }
    }
    entersearch {
        bind "Ctrl c" { SwitchToMode "scroll"; }
        bind "Esc" { SwitchToMode "scroll"; }
        bind "Enter" { SwitchToMode "search"; }
    }
    renametab {
        bind "Esc" { UndoRenameTab; SwitchToMode "tab"; }
    }
    shared_among "renametab" "renamepane" {
        bind "Ctrl c" { SwitchToMode "locked"; }
    }
    renamepane {
        bind "Esc" { UndoRenamePane; SwitchToMode "pane"; }
    }
}
```

- [ ] **Step 2: Write `configs/btop.conf`**

btop auto-generates and fills in the rest of its own config on first real launch — this ships only the one line `bin/omawsl theme` (Task 7) needs to `sed`-patch, so the patch has something to target even before btop has ever been run once.

```
# omawsl: minimal seed config. btop fills in the rest of its own
# defaults (and any keys it doesn't recognize here) the first time it
# actually runs. This file exists purely so `bin/omawsl theme` always
# has a `color_theme = "..."` line to sed-patch, even before btop has
# ever been launched once.
color_theme = "Default"
```

- [ ] **Step 3: Write the failing tests**

Add to `tests/apps_terminal_test.bats` (after the existing zellij tests):

```bash
@test "deploys configs/zellij.kdl to ~/.config/zellij/config.kdl" {
  run omawsl_install_zellij_config
  [ "$status" -eq 0 ]
  diff "$HOME/.config/zellij/config.kdl" "$REPO_ROOT/configs/zellij.kdl"
}

@test "does not overwrite an existing zellij config.kdl" {
  mkdir -p "$HOME/.config/zellij"
  echo "theme \"my-custom-theme\"" > "$HOME/.config/zellij/config.kdl"
  run omawsl_install_zellij_config
  [ "$status" -eq 0 ]
  [[ "$(cat "$HOME/.config/zellij/config.kdl")" == 'theme "my-custom-theme"' ]]
}

@test "deploys configs/btop.conf to ~/.config/btop/btop.conf" {
  run omawsl_install_btop_config
  [ "$status" -eq 0 ]
  diff "$HOME/.config/btop/btop.conf" "$REPO_ROOT/configs/btop.conf"
}

@test "does not overwrite an existing btop.conf" {
  mkdir -p "$HOME/.config/btop"
  echo 'color_theme = "my-custom-theme"' > "$HOME/.config/btop/btop.conf"
  run omawsl_install_btop_config
  [ "$status" -eq 0 ]
  [[ "$(cat "$HOME/.config/btop/btop.conf")" == 'color_theme = "my-custom-theme"' ]]
}

@test "installs jq alongside the rest of the always-on apt tool set" {
  run omawsl_install_terminal_apps
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop fastfetch lazygit jq"* ]]
}
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/apps_terminal_test.bats"`
Expected: FAIL — `omawsl_install_zellij_config: command not found`, `omawsl_install_btop_config: command not found`, and the apt-list test fails because `jq` isn't in the install command yet.

- [ ] **Step 5: Modify `install/terminal/apps-terminal.sh`**

Add a `SCRIPT_DIR` line (needed to locate `configs/` — this file didn't need it before), add `jq` to the apt list, and add the two new deploy functions, called unconditionally from `omawsl_install_terminal_apps` right after their tool's own install call:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# omawsl_install_terminal_apps
# Always-on terminal tooling, no picker gate. Installs via apt where a
# stable Ubuntu package exists (verified against Ubuntu 26.04's own
# universe repo: fzf, ripgrep, bat, eza, zoxide, plocate, apache2-utils,
# fd-find, gh, btop, fastfetch, lazygit, jq all have candidates there),
# plus two tools with no Ubuntu package at all (lazydocker, zellij),
# each installed via its own official method below. `jq` is new in
# Phase 5 - `bin/omawsl theme` (design spec §11) needs it for the
# Windows Terminal settings.json edit.
omawsl_install_terminal_apps() {
  sudo apt-get update -qq
  sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop fastfetch lazygit jq

  omawsl_install_lazydocker
  omawsl_install_zellij
  omawsl_install_zellij_config
  omawsl_install_btop_config
}

# omawsl_install_lazydocker
# No Ubuntu package exists for lazydocker - installs via its official
# script (jesseduffield/lazydocker), which installs to $HOME/.local/bin
# by default (already on PATH via configs/bashrc). The script itself
# always re-downloads/reinstalls unconditionally - this command -v guard
# is what actually makes this idempotent.
omawsl_install_lazydocker() {
  if command -v lazydocker &>/dev/null; then
    return 0
  fi
  curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
}

# omawsl_install_zellij
# No Ubuntu package exists for zellij either. Installs the official
# prebuilt musl binary release directly from GitHub rather than the
# project's own `bash <(curl .../launch)` one-liner, so the exact steps
# stay auditable here instead of delegating to an unseen remote script.
# `/releases/latest/download/<asset>` always resolves to the current
# release, so no separate version-lookup step is needed.
omawsl_install_zellij() {
  if command -v zellij &>/dev/null; then
    return 0
  fi
  local arch
  arch="$(uname -m)"
  curl -fsSL "https://github.com/zellij-org/zellij/releases/latest/download/zellij-${arch}-unknown-linux-musl.tar.gz" | tar -xz -C /tmp
  sudo install -m 0755 /tmp/zellij /usr/local/bin/zellij
  rm -f /tmp/zellij
}

# omawsl_install_zellij_config
# Deploys omawsl's own configs/zellij.kdl (Omakub's ported keybindings,
# plus an initial "theme" reference bin/omawsl theme later rewrites -
# Phase 5 Task 7) to zellij's real config location. Guarded like
# app-neovim.sh's LazyVim clone (Phase 4) - never overwrites a config
# the user may have since hand-edited.
omawsl_install_zellij_config() {
  local config_file="$HOME/.config/zellij/config.kdl"
  if [[ -f "$config_file" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$config_file")"
  cp "$SCRIPT_DIR/../../configs/zellij.kdl" "$config_file"
}

# omawsl_install_btop_config
# Deploys omawsl's own minimal configs/btop.conf, for the same reason
# and with the same non-destructive guard as omawsl_install_zellij_config
# above.
omawsl_install_btop_config() {
  local config_file="$HOME/.config/btop/btop.conf"
  if [[ -f "$config_file" ]]; then
    return 0
  fi
  mkdir -p "$(dirname "$config_file")"
  cp "$SCRIPT_DIR/../../configs/btop.conf" "$config_file"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_terminal_apps
fi
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/apps_terminal_test.bats"`
Expected: PASS, all tests including the pre-existing ones.

- [ ] **Step 7: Commit**

```bash
git add configs/zellij.kdl configs/btop.conf install/terminal/apps-terminal.sh tests/apps_terminal_test.bats
git commit -m "feat: port configs/zellij.kdl and configs/btop.conf, add jq"
```

---

### Task 2: Shared VS Code/Cursor theme helper (`themes/set-vscode-theme.sh`)

**Files:**
- Create: `themes/set-vscode-theme.sh`
- Test: `tests/theme_vscode_test.bats`

**Interfaces:**
- Consumes: `omawsl_code_reachable` (from `install/lib.sh`, existing).
- Produces: `omawsl_theme_set_vscode_settings <settings_file> <color_theme>`, `omawsl_theme_apply_vscode <color_theme> <extension_id>` — both consumed by every per-theme `vscode.sh` file (Tasks 3–5) and transitively by `bin/omawsl-sub/theme.sh` (Task 7).

Upstream's `vscode.sh` uses two bash *global variables* (`VSC_THEME`, `VSC_EXTENSION`) set by the caller before `source`-ing the helper. This plan uses explicit function arguments instead — Phase 1's own retrospective (`docs/superpowers/plans/2026-07-06-omawsl-phase1-core-skeleton.md`) flagged a real `SCRIPT_DIR` global-variable collision bug across sourced scripts as a lesson to avoid repeating; passing values as arguments sidesteps that whole class of bug.

Upstream also hardcodes `~/.config/Code/User/settings.json` (a native-Linux desktop path). On WSL2 with VS Code's Remote-WSL extension, the real file omawsl already manages is `$HOME/.vscode-server/data/Machine/settings.json` (deployed by Phase 4's `app-vscode.sh`) and, for Cursor, `$HOME/.cursor-server/data/Machine/settings.json` (Phase 4's `app-cursor.sh`) — design spec §11 explicitly calls for the theme step to cover both from one shared helper.

- [ ] **Step 1: Write the failing tests**

Create `tests/theme_vscode_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/themes/set-vscode-theme.sh"
  command -v jq &>/dev/null || skip "jq not installed on this test host"
}

@test "omawsl_theme_set_vscode_settings merges workbench.colorTheme without touching other keys" {
  mkdir -p "$HOME/.vscode-server/data/Machine"
  local settings="$HOME/.vscode-server/data/Machine/settings.json"
  cp "$REPO_ROOT/configs/vscode.json" "$settings"
  run omawsl_theme_set_vscode_settings "$settings" "Tokyo Night"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$settings")" == "Tokyo Night" ]]
  [[ "$(jq -r '.["editor.formatOnSave"]' "$settings")" == "true" ]]
}

@test "omawsl_theme_set_vscode_settings no-ops when the settings file doesn't exist" {
  run omawsl_theme_set_vscode_settings "$HOME/.vscode-server/data/Machine/settings.json" "Tokyo Night"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.vscode-server/data/Machine/settings.json" ]
}

@test "omawsl_theme_apply_vscode patches both VS Code and Cursor settings, installs only the VS Code extension" {
  mkdir -p "$HOME/.vscode-server/data/Machine" "$HOME/.cursor-server/data/Machine"
  cp "$REPO_ROOT/configs/vscode.json" "$HOME/.vscode-server/data/Machine/settings.json"
  cp "$REPO_ROOT/configs/vscode.json" "$HOME/.cursor-server/data/Machine/settings.json"
  stub_command code
  run omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$HOME/.vscode-server/data/Machine/settings.json")" == "Tokyo Night" ]]
  [[ "$(jq -r '.["workbench.colorTheme"]' "$HOME/.cursor-server/data/Machine/settings.json")" == "Tokyo Night" ]]
  [[ "$(stub_calls)" == *"code --install-extension enkia.tokyo-night"* ]]
}

@test "omawsl_theme_apply_vscode skips the extension install when code isn't reachable" {
  stub_hide_command code
  run omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"code --install-extension"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/theme_vscode_test.bats"`
Expected: FAIL — `themes/set-vscode-theme.sh: No such file or directory`.

- [ ] **Step 3: Write `themes/set-vscode-theme.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../install/lib.sh
source "$SCRIPT_DIR/../install/lib.sh"

# omawsl_theme_set_vscode_settings <settings_file> <color_theme>
# Merges "workbench.colorTheme" into an existing VS Code/Cursor-shaped
# settings.json via jq, never a blind sed (design spec §11 - jq is the
# safer choice, though the real risk there is the Windows Terminal
# edit's nested schemes array; kept consistent here too). No-ops if the
# settings file doesn't exist yet (VS Code/Cursor not selected in
# Phase 4's picker, so app-vscode.sh/app-cursor.sh never deployed it) or
# if jq itself isn't reachable.
omawsl_theme_set_vscode_settings() {
  local settings_file="$1" color_theme="$2"
  [[ -f "$settings_file" ]] || return 0
  command -v jq &>/dev/null || return 0
  local tmp
  tmp="$(mktemp)"
  jq --arg theme "$color_theme" '.["workbench.colorTheme"] = $theme' "$settings_file" > "$tmp"
  mv "$tmp" "$settings_file"
}

# omawsl_theme_apply_vscode <color_theme> <extension_id>
# Applies the theme to both VS Code's and Cursor's Remote settings.json,
# whichever exist (design spec §11: "VS Code theme step also covers
# Cursor", since Cursor reads the same settings.json keys). Installs the
# VS Code extension via `code --install-extension` only when `code` is
# reachable - matches app-vscode.sh's own detect-and-defer shape
# (Phase 4). Deliberately does NOT attempt `cursor --install-extension`,
# same reasoning as app-cursor.sh (Phase 4): Cursor has its own
# extension distribution and commonly blocks Microsoft-published
# extensions from its marketplace, so this only touches what's clearly
# specified (shared settings keys).
omawsl_theme_apply_vscode() {
  local color_theme="$1" extension_id="$2"

  omawsl_theme_set_vscode_settings "$HOME/.vscode-server/data/Machine/settings.json" "$color_theme"
  omawsl_theme_set_vscode_settings "$HOME/.cursor-server/data/Machine/settings.json" "$color_theme"

  if omawsl_code_reachable; then
    code --install-extension "$extension_id" >/dev/null
  fi
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/theme_vscode_test.bats"`
Expected: PASS (or SKIP for both if the test host genuinely has no `jq` — acceptable only for this local dev loop; Task 1 guarantees `jq` on any real WSL2 install).

- [ ] **Step 5: Commit**

```bash
git add themes/set-vscode-theme.sh tests/theme_vscode_test.bats
git commit -m "feat: add shared VS Code/Cursor theme-apply helper"
```

---

### Task 3: Port themes batch 1 — catppuccin, everforest, gruvbox, kanagawa

**Files:**
- Create: `themes/catppuccin/{neovim.lua,zellij.kdl,btop.theme,vscode.sh,windows-terminal-scheme.json}`
- Create: `themes/everforest/{neovim.lua,zellij.kdl,btop.theme,vscode.sh,windows-terminal-scheme.json}`
- Create: `themes/gruvbox/{neovim.lua,zellij.kdl,btop.theme,vscode.sh,windows-terminal-scheme.json}`
- Create: `themes/kanagawa/{neovim.lua,zellij.kdl,btop.theme,vscode.sh,windows-terminal-scheme.json}`
- Test: `tests/theme_files_test.bats`

**Interfaces:**
- Consumes: `themes/set-vscode-theme.sh`'s `omawsl_theme_apply_vscode` (Task 2).
- Produces: nothing new — these are pure data files consumed by `bin/omawsl-sub/theme.sh` (Task 7).

`neovim.lua`, `zellij.kdl`, and `btop.theme` are ported **verbatim** from the real upstream files (design spec §11: "ported as-is (or lightly adapted)"). `vscode.sh` is adapted to call the new shared helper directly (Task 2) instead of upstream's global-variable pattern. `windows-terminal-scheme.json` is new — hand-derived from each theme's real upstream `alacritty.toml` hex values (fetched during Phase 5 research, not invented), following one fixed, documented mapping:

- `background`/`foreground` ← alacritty's `[colors.primary]` `background`/`foreground`.
- `black`/`red`/`green`/`yellow`/`blue`/`purple`/`cyan`/`white` ← alacritty's `[colors.normal]` (alacritty/ANSI calls it `magenta`; Windows Terminal's own schema calls the same slot `purple`).
- `brightBlack`.../`brightWhite` ← alacritty's `[colors.bright]`, same slot mapping.
- `cursorColor` ← alacritty's `[colors.cursor].cursor` if present, else falls back to `foreground`.
- `selectionBackground` ← alacritty's `[colors.selection].background` if present, else falls back to `[colors.bright].black` (a lighter tint of the background, a reasonable subtle-highlight default — never the same color as `foreground`, which would make selected text unreadable).
- `name` ← the Title Case display name (Omakub's own `gum choose` label, e.g. `"Tokyo Night"`), not the folder name.

One format quirk found during research and handled per-theme as noted: gruvbox's upstream `alacritty.toml` uses `0xRRGGBB` instead of `#RRGGBB` (values converted to `#` form below, same colors). tokyo-night's upstream `zellij.kdl` fragment uses space-separated RGB decimal instead of `"#hex"` strings (kept as-is — both are valid zellij KDL syntax, ported verbatim in Task 5).

- [ ] **Step 1: Write the failing test**

Create `tests/theme_files_test.bats`:

```bash
#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

@test "every ported theme has all 5 required files" {
  for name in catppuccin everforest gruvbox kanagawa matte-black nord osaka-jade ristretto rose-pine tokyo-night; do
    for f in neovim.lua zellij.kdl btop.theme vscode.sh windows-terminal-scheme.json; do
      [ -f "$REPO_ROOT/themes/$name/$f" ] || { echo "missing themes/$name/$f"; return 1; }
    done
  done
}

@test "every windows-terminal-scheme.json is valid JSON with all required keys" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  for name in catppuccin everforest gruvbox kanagawa matte-black nord osaka-jade ristretto rose-pine tokyo-night; do
    local f="$REPO_ROOT/themes/$name/windows-terminal-scheme.json"
    run jq -e '.name and .background and .foreground and .cursorColor and .selectionBackground and .black and .red and .green and .yellow and .blue and .purple and .cyan and .white and .brightBlack and .brightRed and .brightGreen and .brightYellow and .brightBlue and .brightPurple and .brightCyan and .brightWhite' "$f"
    [ "$status" -eq 0 ]
  done
}

@test "catppuccin windows-terminal-scheme.json matches the researched alacritty hex values" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  local f="$REPO_ROOT/themes/catppuccin/windows-terminal-scheme.json"
  [[ "$(jq -r .background "$f")" == "#24273a" ]]
  [[ "$(jq -r .foreground "$f")" == "#cad3f5" ]]
  [[ "$(jq -r .purple "$f")" == "#f5bde6" ]]
}

@test "gruvbox windows-terminal-scheme.json converts 0x-prefixed hex to #-prefixed" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  local f="$REPO_ROOT/themes/gruvbox/windows-terminal-scheme.json"
  [[ "$(jq -r .background "$f")" == "#282828" ]]
  [[ "$(jq -r .red "$f")" == "#ea6962" ]]
}

@test "catppuccin vscode.sh calls the shared helper with the right theme and extension" {
  grep -q 'omawsl_theme_apply_vscode "Catppuccin Macchiato" "Catppuccin.catppuccin-vsc"' "$REPO_ROOT/themes/catppuccin/vscode.sh"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/theme_files_test.bats"`
Expected: FAIL — missing files.

- [ ] **Step 3: Write `themes/catppuccin/neovim.lua`**

```lua
return {
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "catppuccin",
		},
	},
}
```

- [ ] **Step 4: Write `themes/catppuccin/zellij.kdl`**

```kdl
themes {
  catppuccin {
    bg "#626880" // Surface2
    fg "#c6d0f5"
    red "#e78284"
    green "#a6d189"
    blue "#8caaee"
    yellow "#e5c890"
    magenta "#f4b8e4" // Pink
    orange "#ef9f76" // Peach
    cyan "#99d1db" // Sky
    black "#292c3c" // Mantle
    white "#c6d0f5"
  }

  catppuccin-latte {
    bg "#acb0be" // Surface2
    fg "#acb0be" // Surface2
    red "#d20f39"
    green "#40a02b"
    blue "#1e66f5"
    yellow "#df8e1d"
    magenta "#ea76cb" // Pink
    orange "#fe640b" // Peach
    cyan "#04a5e5" // Sky
    black "#dce0e8" // Crust
    white "#4c4f69" // Text
  }

  catppuccin-macchiato {
    bg "#5b6078" // Surface2
    fg "#cad3f5"
    red "#ed8796"
    green "#a6da95"
    blue "#8aadf4"
    yellow "#eed49f"
    magenta "#f5bde6" // Pink
    orange "#f5a97f" // Peach
    cyan "#91d7e3" // Sky
    black "#1e2030" // Mantle
    white "#cad3f5"
  }

  catppuccin-mocha {
    bg "#585b70" // Surface2
    fg "#cdd6f4"
    red "#f38ba8"
    green "#a6e3a1"
    blue "#89b4fa"
    yellow "#f9e2af"
    magenta "#f5c2e7" // Pink
    orange "#fab387" // Peach
    cyan "#89dceb" // Sky
    black "#181825" // Mantle
    white "#cdd6f4"
  }
}
```

- [ ] **Step 5: Write `themes/catppuccin/btop.theme`**

```
# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]="#24273a"

# Main text color
theme[main_fg]="#c6d0f5"

# Title color for boxes
theme[title]="#c6d0f5"

# Highlight color for keyboard shortcuts
theme[hi_fg]="#8caaee"

# Background color of selected item in processes box
theme[selected_bg]="#51576d"

# Foreground color of selected item in processes box
theme[selected_fg]="#8caaee"

# Color of inactive/disabled text
theme[inactive_fg]="#838ba7"

# Color of text appearing on top of graphs, i.e uptime and current network graph scaling
theme[graph_text]="#f2d5cf"

# Background color of the percentage meters
theme[meter_bg]="#51576d"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="#f2d5cf"

# CPU, Memory, Network, Proc box outline colors
theme[cpu_box]="#ca9ee6" #Mauve
theme[mem_box]="#a6d189" #Green
theme[net_box]="#ea999c" #Maroon
theme[proc_box]="#8caaee" #Blue

# Box divider line and small boxes line color
theme[div_line]="#737994"

# Temperature graph color (Green -> Yellow -> Red)
theme[temp_start]="#a6d189"
theme[temp_mid]="#e5c890"
theme[temp_end]="#e78284"

# CPU graph colors (Teal -> Lavender)
theme[cpu_start]="#81c8be"
theme[cpu_mid]="#85c1dc"
theme[cpu_end]="#babbf1"

# Mem/Disk free meter (Mauve -> Lavender -> Blue)
theme[free_start]="#ca9ee6"
theme[free_mid]="#babbf1"
theme[free_end]="#8caaee"

# Mem/Disk cached meter (Sapphire -> Lavender)
theme[cached_start]="#85c1dc"
theme[cached_mid]="#8caaee"
theme[cached_end]="#babbf1"

# Mem/Disk available meter (Peach -> Red)
theme[available_start]="#ef9f76"
theme[available_mid]="#ea999c"
theme[available_end]="#e78284"

# Mem/Disk used meter (Green -> Sky)
theme[used_start]="#a6d189"
theme[used_mid]="#81c8be"
theme[used_end]="#99d1db"

# Download graph colors (Peach -> Red)
theme[download_start]="#ef9f76"
theme[download_mid]="#ea999c"
theme[download_end]="#e78284"

# Upload graph colors (Green -> Sky)
theme[upload_start]="#a6d189"
theme[upload_mid]="#81c8be"
theme[upload_end]="#99d1db"

# Process box color gradient for threads, mem and cpu usage (Sapphire -> Mauve)
theme[process_start]="#85c1dc"
theme[process_mid]="#babbf1"
theme[process_end]="#ca9ee6"
```

- [ ] **Step 6: Write `themes/catppuccin/vscode.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$SCRIPT_DIR/../set-vscode-theme.sh"

omawsl_theme_apply_vscode "Catppuccin Macchiato" "Catppuccin.catppuccin-vsc"
```

- [ ] **Step 7: Write `themes/catppuccin/windows-terminal-scheme.json`**

```json
{
    "name": "Catppuccin",
    "background": "#24273a",
    "foreground": "#cad3f5",
    "cursorColor": "#f4dbd6",
    "selectionBackground": "#f4dbd6",
    "black": "#494d64",
    "red": "#ed8796",
    "green": "#a6da95",
    "yellow": "#eed49f",
    "blue": "#8aadf4",
    "purple": "#f5bde6",
    "cyan": "#8bd5ca",
    "white": "#b8c0e0",
    "brightBlack": "#5b6078",
    "brightRed": "#ed8796",
    "brightGreen": "#a6da95",
    "brightYellow": "#eed49f",
    "brightBlue": "#8aadf4",
    "brightPurple": "#f5bde6",
    "brightCyan": "#8bd5ca",
    "brightWhite": "#a5adcb"
}
```

- [ ] **Step 8: Write `themes/everforest/neovim.lua`**

```lua
return {
	{ "neanias/everforest-nvim" },
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "everforest",
			background = "soft",
		},
	},
}
```

- [ ] **Step 9: Write `themes/everforest/zellij.kdl`**

```kdl
themes {
    everforest {
        bg "#2b3339"
        fg "#d3c6aa"
        black "#4b565c"
        red "#e67e80"
        green "#a7c080"
        yellow "#dbbc7f"
        blue "#7fbbb3"
        magenta "#d699b6"
        cyan "#83c092"
        white "#d3c6aa"
        orange "#FF9E64"
    }
}
```

- [ ] **Step 10: Write `themes/everforest/btop.theme`**

```
# All graphs and meters can be gradients
# For single color graphs leave "mid" and "end" variable empty.
# Use "start" and "end" variables for two color gradient
# Use "start", "mid" and "end" for three color gradient

# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]="#2d353b"

# Main text color
theme[main_fg]="#d3c6aa"

# Title color for boxes
theme[title]="#d3c6aa"

# Highlight color for keyboard shortcuts
theme[hi_fg]="#e67e80"

# Background color of selected items
theme[selected_bg]="#3d484d"

# Foreground color of selected items
theme[selected_fg]="#dbbc7f"

# Color of inactive/disabled text
theme[inactive_fg]="#2d353b"  

# Color of text appearing on top of graphs, i.e uptime and current network graph scaling
theme[graph_text]="#d3c6aa"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="#a7c080"

# Cpu box outline color
theme[cpu_box]="#3d484d"

# Memory/disks box outline color
theme[mem_box]="#3d484d"

# Net up/down box outline color
theme[net_box]="#3d484d"

# Processes box outline color
theme[proc_box]="#3d484d"

# Box divider line and small boxes line color
theme[div_line]="#3d484d"

# Temperature graph colors
theme[temp_start]="#a7c080"
theme[temp_mid]="#dbbc7f"
theme[temp_end]="#f85552"

# CPU graph colors
theme[cpu_start]="#a7c080"
theme[cpu_mid]="#dbbc7f"
theme[cpu_end]="#f85552"

# Mem/Disk free meter
theme[free_start]="#f85552"
theme[free_mid]="#dbbc7f"
theme[free_end]="#a7c080"

# Mem/Disk cached meter
theme[cached_start]="#7fbbb3"
theme[cached_mid]="#83c092"
theme[cached_end]="#a7c080"

# Mem/Disk available meter
theme[available_start]="#f85552"
theme[available_mid]="#dbbc7f"
theme[available_end]="#a7c080"

# Mem/Disk used meter
theme[used_start]="#a7c080"
theme[used_mid]="#dbbc7f"
theme[used_end]="#f85552"

# Download graph colors
theme[download_start]="#a7c080"
theme[download_mid]="#83c092"
theme[download_end]="#7fbbb3"

# Upload graph colors
theme[upload_start]="#dbbc7f"
theme[upload_mid]="#e69875"
theme[upload_end]="#e67e80"

# Process box color gradient for threads, mem and cpu usage
theme[process_start]="#a7c080"
theme[process_mid]="#e67e80"
theme[process_end]="#f85552"
```

- [ ] **Step 11: Write `themes/everforest/vscode.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$SCRIPT_DIR/../set-vscode-theme.sh"

omawsl_theme_apply_vscode "Everforest Dark" "sainnhe.everforest"
```

- [ ] **Step 12: Write `themes/everforest/windows-terminal-scheme.json`**

No `[colors.cursor]`/`[colors.selection]` block upstream — `cursorColor` falls back to `foreground`, `selectionBackground` falls back to `black` (normal and bright are identical for this theme).

```json
{
    "name": "Everforest",
    "background": "#2d353b",
    "foreground": "#d3c6aa",
    "cursorColor": "#d3c6aa",
    "selectionBackground": "#475258",
    "black": "#475258",
    "red": "#e67e80",
    "green": "#a7c080",
    "yellow": "#dbbc7f",
    "blue": "#7fbbb3",
    "purple": "#d699b6",
    "cyan": "#83c092",
    "white": "#d3c6aa",
    "brightBlack": "#475258",
    "brightRed": "#e67e80",
    "brightGreen": "#a7c080",
    "brightYellow": "#dbbc7f",
    "brightBlue": "#7fbbb3",
    "brightPurple": "#d699b6",
    "brightCyan": "#83c092",
    "brightWhite": "#d3c6aa"
}
```

- [ ] **Step 13: Write `themes/gruvbox/neovim.lua`**

```lua
return {
	{ "ellisonleao/gruvbox.nvim" },
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "gruvbox",
		},
	},
}
```

- [ ] **Step 14: Write `themes/gruvbox/zellij.kdl`**

```kdl
themes {
    gruvbox {
        fg "#d5c4a1"
        bg "#282828"
        black "#3c3836"
        red "#cc241d"
        green "#98971a"
        yellow "#d79921"
        blue "#3c8588"
        magenta "#b16286"
        cyan "#689d6a"
        white "#fbf1c7"
        orange "#d65d0e"
    }
}
```

- [ ] **Step 15: Write `themes/gruvbox/btop.theme`**

```
#Bashtop gruvbox (https://github.com/morhetz/gruvbox) theme
#by BachoSeven

# Colors should be in 6 or 2 character hexadecimal or single spaced rgb decimal: "#RRGGBB", "#BW" or "0-255 0-255 0-255"
# example for white: "#FFFFFF", "#ff" or "255 255 255".

# All graphs and meters can be gradients
# For single color graphs leave "mid" and "end" variable empty.
# Use "start" and "end" variables for two color gradient
# Use "start", "mid" and "end" for three color gradient

# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]="#282828"

# Main text color
theme[main_fg]="#a89984"

# Title color for boxes
theme[title]="#ebdbb2"

# Highlight color for keyboard shortcuts
theme[hi_fg]="#d79921"

# Background color of selected items
theme[selected_bg]="#282828"

# Foreground color of selected items
theme[selected_fg]="#fabd2f"

# Color of inactive/disabled text
theme[inactive_fg]="#282828"

# Color of text appearing on top of graphs, i.e uptime and current network graph scaling
theme[graph_text]="#585858"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="#98971a"

# Cpu box outline color
theme[cpu_box]="#a89984"

# Memory/disks box outline color
theme[mem_box]="#a89984"

# Net up/down box outline color
theme[net_box]="#a89984"

# Processes box outline color
theme[proc_box]="#a89984"

# Box divider line and small boxes line color
theme[div_line]="#a89984"

# Temperature graph colors
theme[temp_start]="#458588"
theme[temp_mid]="#d3869b"
theme[temp_end]="#fb4394"

# CPU graph colors
theme[cpu_start]="#b8bb26"
theme[cpu_mid]="#d79921"
theme[cpu_end]="#fb4934"

# Mem/Disk free meter
theme[free_start]="#4e5900"
theme[free_mid]=""
theme[free_end]="#98971a"

# Mem/Disk cached meter
theme[cached_start]="#458588"
theme[cached_mid]=""
theme[cached_end]="#83a598"

# Mem/Disk available meter
theme[available_start]="#d79921"
theme[available_mid]=""
theme[available_end]="#fabd2f"

# Mem/Disk used meter
theme[used_start]="#cc241d"
theme[used_mid]=""
theme[used_end]="#fb4934"

# Download graph colors
theme[download_start]="#3d4070"
theme[download_mid]="#6c71c4"
theme[download_end]="#a3a8f7"

# Upload graph colors
theme[upload_start]="#701c45"
theme[upload_mid]="#b16286"
theme[upload_end]="#d3869b"
```

- [ ] **Step 16: Write `themes/gruvbox/vscode.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$SCRIPT_DIR/../set-vscode-theme.sh"

omawsl_theme_apply_vscode "Gruvbox Dark Medium" "jdinhlife.gruvbox"
```

- [ ] **Step 17: Write `themes/gruvbox/windows-terminal-scheme.json`**

Upstream `alacritty.toml` uses `0xRRGGBB` — converted to `#RRGGBB` below (same colors, confirmed during research). No `[colors.cursor]`/`[colors.selection]` block — same fallback rule as everforest.

```json
{
    "name": "Gruvbox",
    "background": "#282828",
    "foreground": "#d4be98",
    "cursorColor": "#d4be98",
    "selectionBackground": "#3c3836",
    "black": "#3c3836",
    "red": "#ea6962",
    "green": "#a9b665",
    "yellow": "#d8a657",
    "blue": "#7daea3",
    "purple": "#d3869b",
    "cyan": "#89b482",
    "white": "#d4be98",
    "brightBlack": "#3c3836",
    "brightRed": "#ea6962",
    "brightGreen": "#a9b665",
    "brightYellow": "#d8a657",
    "brightBlue": "#7daea3",
    "brightPurple": "#d3869b",
    "brightCyan": "#89b482",
    "brightWhite": "#d4be98"
}
```

- [ ] **Step 18: Write `themes/kanagawa/neovim.lua`**

```lua
return {
	{ "rebelot/kanagawa.nvim" },
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "kanagawa",
		},
	},
}
```

- [ ] **Step 19: Write `themes/kanagawa/zellij.kdl`**

```kdl
themes {
    kanagawa {
        fg "#DCD7BA"
        bg "#1F1F28"
        red "#C34043"
        green "#76946A"
        yellow "#FF9E3B"
        blue "#7E9CD8"
        magenta "#957FB8"
        orange "#FFA066"
        cyan "#7FB4CA"
        black "#16161D"
        white "#DCD7BA"
    }
}
```

- [ ] **Step 20: Write `themes/kanagawa/btop.theme`**

```
# Bashtop Kanagawa-wave (https://github.com/rebelot/kanagawa.nvim) theme
# By: philikarus

# Main bg
theme[main_bg]="#1f1f28"

# Main text color
theme[main_fg]="#dcd7ba"

# Title color for boxes
theme[title]="#dcd7ba"

# Highlight color for keyboard shortcuts
theme[hi_fg]="#C34043"

# Background color of selected item in processes box
theme[selected_bg]="#223249"

# Foreground color of selected item in processes box
theme[selected_fg]="#dca561"

# Color of inactive/disabled text
theme[inactive_fg]="#727169"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="#7aa89f"

# Cpu box outline color
theme[cpu_box]="#727169"

# Memory/disks box outline color
theme[mem_box]="#727169"

# Net up/down box outline color
theme[net_box]="#727169"

# Processes box outline color
theme[proc_box]="#727169"

# Box divider line and small boxes line color
theme[div_line]="#727169"

# Temperature graph colors
theme[temp_start]="#98BB6C"
theme[temp_mid]="#DCA561"
theme[temp_end]="#E82424"

# CPU graph colors
theme[cpu_start]="#98BB6C"
theme[cpu_mid]="#DCA561"
theme[cpu_end]="#E82424"

# Mem/Disk free meter
theme[free_start]="#E82424"
theme[free_mid]="#C34043"
theme[free_end]="#FF5D62"

# Mem/Disk cached meter
theme[cached_start]="#C0A36E"
theme[cached_mid]="#DCA561"
theme[cached_end]="#FF9E3B"

# Mem/Disk available meter
theme[available_start]="#938AA9"
theme[available_mid]="#957FBB"
theme[available_end]="#9CABCA"

# Mem/Disk used meter
theme[used_start]="#658594"
theme[used_mid]="#7E9CDB"
theme[used_end]="#7FB4CA"

# Download graph colors
theme[download_start]="#7E9CDB"
theme[download_mid]="#938AA9"
theme[download_end]="#957FBB"

# Upload graph colors
theme[upload_start]="#DCA561"
theme[upload_mid]="#E6C384"
theme[upload_end]="#E82424"

# Process box color gradient for threads, mem and cpu usage
theme[process_start]="#98BB6C"
theme[process_mid]="#DCA561"
theme[process_end]="#C34043"
```

- [ ] **Step 21: Write `themes/kanagawa/vscode.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$SCRIPT_DIR/../set-vscode-theme.sh"

omawsl_theme_apply_vscode "Kanagawa" "qufiwefefwoyn.kanagawa"
```

- [ ] **Step 22: Write `themes/kanagawa/windows-terminal-scheme.json`**

Upstream `alacritty.toml` has a `[colors.selection]` block but no `[colors.cursor]` block — `cursorColor` falls back to `foreground`.

```json
{
    "name": "Kanagawa",
    "background": "#1f1f28",
    "foreground": "#dcd7ba",
    "cursorColor": "#dcd7ba",
    "selectionBackground": "#2d4f67",
    "black": "#090618",
    "red": "#c34043",
    "green": "#76946a",
    "yellow": "#c0a36e",
    "blue": "#7e9cd8",
    "purple": "#957fb8",
    "cyan": "#6a9589",
    "white": "#c8c093",
    "brightBlack": "#727169",
    "brightRed": "#e82424",
    "brightGreen": "#98bb6c",
    "brightYellow": "#e6c384",
    "brightBlue": "#7fb4ca",
    "brightPurple": "#938aa9",
    "brightCyan": "#7aa89f",
    "brightWhite": "#dcd7ba"
}
```

- [ ] **Step 23: Run test to verify it passes for this batch**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/theme_files_test.bats"`
Expected: still FAIL on the "every ported theme has all 5 required files" test (batches 2 and 3 don't exist yet) — but the catppuccin- and gruvbox-specific assertions now PASS. This is expected until Task 5 completes; re-run the full suite there.

- [ ] **Step 24: Commit**

```bash
git add themes/catppuccin themes/everforest themes/gruvbox themes/kanagawa tests/theme_files_test.bats
git commit -m "feat: port catppuccin, everforest, gruvbox, kanagawa themes"
```

---

### Task 4: Port themes batch 2 — matte-black, nord, osaka-jade, ristretto

**Files:**
- Create: `themes/matte-black/{neovim.lua,zellij.kdl,btop.theme,vscode.sh,windows-terminal-scheme.json}`
- Create: `themes/nord/{neovim.lua,zellij.kdl,btop.theme,vscode.sh,windows-terminal-scheme.json}`
- Create: `themes/osaka-jade/{neovim.lua,zellij.kdl,btop.theme,vscode.sh,windows-terminal-scheme.json}`
- Create: `themes/ristretto/{neovim.lua,zellij.kdl,btop.theme,vscode.sh,windows-terminal-scheme.json}`

Same shape as Task 3 — no new interfaces, no new test file (this batch is covered by the shared `tests/theme_files_test.bats` from Task 3).

- [ ] **Step 1: Write `themes/matte-black/neovim.lua`**

```lua
return {
  { "tahayvr/matteblack.nvim", lazy = false, priority = 1000 },
  {
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "matteblack",
		},
	},
}
```

- [ ] **Step 2: Write `themes/matte-black/zellij.kdl`**

```kdl
themes {
    matte-black {
        fg "#bebebe"
        bg "#121212"
        red "#D35F5F"
        green "#FFC107"
        yellow "#b91c1c"
        blue "#e68e0d"
        orange "#FFA066"
        magenta "#D35F5F"
        cyan "#bebebe"
        black "#333333"
        white "#bebebe"
    }
}
```

- [ ] **Step 3: Write `themes/matte-black/btop.theme`**

```
# ────────────────────────────────────────────────────────────
# Bashtop theme - Omarchy Matte Black
# by tahayvr
# https://github.com/tahayvr
# ────────────────────────────────────────────────────────────

# Colors should be in 6 or 2 character hexadecimal or single spaced rgb decimal: "#RRGGBB", "#BW" or "0-255 0-255 0-255"
# example for white: "#ffffff", "#ff" or "255 255 255".

# All graphs and meters can be gradients
# For single color graphs leave "mid" and "end" variable empty.
# Use "start" and "end" variables for two color gradient
# Use "start", "mid" and "end" for three color gradient

# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]=""

# Main text color
theme[main_fg]="#EAEAEA"

# Title color for boxes
theme[title]="#8a8a8d"

# Highlight color for keyboard shortcuts
theme[hi_fg]="#f59e0b"

# Background color of selected item in processes box
theme[selected_bg]="#f59e0b"

# Foreground color of selected item in processes box
theme[selected_fg]="#EAEAEA"

# Color of inactive/disabled text
theme[inactive_fg]="#333333"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="#8a8a8d"

# Cpu box outline color
theme[cpu_box]="#8a8a8d"

# Memory/disks box outline color
theme[mem_box]="#8a8a8d"

# Net up/down box outline color
theme[net_box]="#8a8a8d"

# Processes box outline color
theme[proc_box]="#8a8a8d"

# Box divider line and small boxes line color
theme[div_line]="#8a8a8d"

# Temperature graph colors
theme[temp_start]="#8a8a8d"
theme[temp_mid]="#f59e0b"
theme[temp_end]="#b91c1c"

# CPU graph colors
theme[cpu_start]="#8a8a8d"
theme[cpu_mid]="#f59e0b"
theme[cpu_end]="#b91c1c"

# Mem/Disk free meter
theme[free_start]="#8a8a8d"
theme[free_mid]="#f59e0b"
theme[free_end]="#b91c1c"

# Mem/Disk cached meter
theme[cached_start]="#8a8a8d"
theme[cached_mid]="#f59e0b"
theme[cached_end]="#b91c1c"

# Mem/Disk available meter
theme[available_start]="#8a8a8d"
theme[available_mid]="#f59e0b"
theme[available_end]="#b91c1c"

# Mem/Disk used meter
theme[used_start]="#8a8a8d"
theme[used_mid]="#f59e0b"
theme[used_end]="#b91c1c"

# Download graph colors
theme[download_start]="#8a8a8d"
theme[download_mid]="#f59e0b"
theme[download_end]="#b91c1c"

# Upload graph colors
theme[upload_start]="#8a8a8d"
theme[upload_mid]="#f59e0b"
theme[upload_end]="#b91c1c"
```

- [ ] **Step 4: Write `themes/matte-black/vscode.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$SCRIPT_DIR/../set-vscode-theme.sh"

omawsl_theme_apply_vscode "Matte Black Theme" "CleanThemes.matte-black-theme"
```

- [ ] **Step 5: Write `themes/matte-black/windows-terminal-scheme.json`**

Upstream has both `[colors.cursor]` and `[colors.selection]` blocks.

```json
{
    "name": "Matte Black",
    "background": "#121212",
    "foreground": "#bebebe",
    "cursorColor": "#eaeaea",
    "selectionBackground": "#333333",
    "black": "#333333",
    "red": "#d35f5f",
    "green": "#ffc107",
    "yellow": "#b91c1c",
    "blue": "#e68e0d",
    "purple": "#d35f5f",
    "cyan": "#bebebe",
    "white": "#bebebe",
    "brightBlack": "#8a8a8d",
    "brightRed": "#b91c1c",
    "brightGreen": "#ffc107",
    "brightYellow": "#b90a0a",
    "brightBlue": "#f59e0b",
    "brightPurple": "#b91c1c",
    "brightCyan": "#eaeaea",
    "brightWhite": "#ffffff"
}
```

- [ ] **Step 6: Write `themes/nord/neovim.lua`**

```lua
return {
	{ "EdenEast/nightfox.nvim" },
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "nordfox",
		},
	},
}
```

- [ ] **Step 7: Write `themes/nord/zellij.kdl`**

```kdl
themes {
    nord {
        fg "#D8DEE9"
        bg "#2E3440"
        black "#3B4252"
        red "#BF616A"
        green "#A3BE8C"
        yellow "#EBCB8B"
        blue "#81A1C1"
        magenta "#B48EAD"
        cyan "#88C0D0"
        white "#E5E9F0"
        orange "#D08770"
    }
}
```

- [ ] **Step 8: Write `themes/nord/btop.theme`**

```
#Bashtop theme with nord palette (https://www.nordtheme.com)
#by Justin Zobel <justin.zobel@gmail.com>

# Colors should be in 6 or 2 character hexadecimal or single spaced rgb decimal: "#RRGGBB", "#BW" or "0-255 0-255 0-255"
# example for white: "#ffffff", "#ff" or "255 255 255".

# All graphs and meters can be gradients
# For single color graphs leave "mid" and "end" variable empty.
# Use "start" and "end" variables for two color gradient
# Use "start", "mid" and "end" for three color gradient

# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]="#2E3440"

# Main text color
theme[main_fg]="#D8DEE9"

# Title color for boxes
theme[title]="#8FBCBB"

# Highlight color for keyboard shortcuts
theme[hi_fg]="#5E81AC"

# Background color of selected item in processes box
theme[selected_bg]="#4C566A"

# Foreground color of selected item in processes box
theme[selected_fg]="#ECEFF4"

# Color of inactive/disabled text
theme[inactive_fg]="#4C566A"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="#5E81AC"

# Cpu box outline color
theme[cpu_box]="#4C566A"

# Memory/disks box outline color
theme[mem_box]="#4C566A"

# Net up/down box outline color
theme[net_box]="#4C566A"

# Processes box outline color
theme[proc_box]="#4C566A"

# Box divider line and small boxes line color
theme[div_line]="#4C566A"

# Temperature graph colors
theme[temp_start]="#81A1C1"
theme[temp_mid]="#88C0D0"
theme[temp_end]="#ECEFF4"

# CPU graph colors
theme[cpu_start]="#81A1C1"
theme[cpu_mid]="#88C0D0"
theme[cpu_end]="#ECEFF4"

# Mem/Disk free meter
theme[free_start]="#81A1C1"
theme[free_mid]="#88C0D0"
theme[free_end]="#ECEFF4"

# Mem/Disk cached meter
theme[cached_start]="#81A1C1"
theme[cached_mid]="#88C0D0"
theme[cached_end]="#ECEFF4"

# Mem/Disk available meter
theme[available_start]="#81A1C1"
theme[available_mid]="#88C0D0"
theme[available_end]="#ECEFF4"

# Mem/Disk used meter
theme[used_start]="#81A1C1"
theme[used_mid]="#88C0D0"
theme[used_end]="#ECEFF4"

# Download graph colors
theme[download_start]="#81A1C1"
theme[download_mid]="#88C0D0"
theme[download_end]="#ECEFF4"

# Upload graph colors
theme[upload_start]="#81A1C1"
theme[upload_mid]="#88C0D0"
theme[upload_end]="#ECEFF4"
```

- [ ] **Step 9: Write `themes/nord/vscode.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$SCRIPT_DIR/../set-vscode-theme.sh"

omawsl_theme_apply_vscode "Nord" "arcticicestudio.nord-visual-studio-code"
```

- [ ] **Step 10: Write `themes/nord/windows-terminal-scheme.json`**

```json
{
    "name": "Nord",
    "background": "#2e3440",
    "foreground": "#d8dee9",
    "cursorColor": "#d8dee9",
    "selectionBackground": "#4c566a",
    "black": "#3b4252",
    "red": "#bf616a",
    "green": "#a3be8c",
    "yellow": "#ebcb8b",
    "blue": "#81a1c1",
    "purple": "#b48ead",
    "cyan": "#88c0d0",
    "white": "#e5e9f0",
    "brightBlack": "#4c566a",
    "brightRed": "#bf616a",
    "brightGreen": "#a3be8c",
    "brightYellow": "#ebcb8b",
    "brightBlue": "#81a1c1",
    "brightPurple": "#b48ead",
    "brightCyan": "#8fbcbb",
    "brightWhite": "#eceff4"
}
```

- [ ] **Step 11: Write `themes/osaka-jade/neovim.lua`**

```lua
return {
  {
    "ribru17/bamboo.nvim",
    lazy = false,
    priority = 1000,
    config = function()
      require("bamboo").setup({})
      require("bamboo").load()
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "bamboo",
    },
  },
}
```

- [ ] **Step 12: Write `themes/osaka-jade/zellij.kdl`**

```kdl
themes {
    osaka-jade {
        fg "#C1C497"
        bg "#111c18"
        red "#FF5345"
        green "#549e6a"
        yellow "#459451"
        blue "#509475"
        magenta "#D2689C"
        cyan "#2DD5B7"
        black "#23372B"
        orange "#E5C736"
        white "#F6F5DD"
    }
}
```

- [ ] **Step 13: Write `themes/osaka-jade/btop.theme`**

```
# Main background
theme[main_bg]="#111c18"

# Main text color
theme[main_fg]="#F7E8B2"

# Title color for boxes
theme[title]="#D6D5BC"

# Highlight color for keyboard shortcuts
theme[hi_fg]="#E67D64"

# Background color of selected items
theme[selected_bg]="#364538"

# Foreground color of selected items
theme[selected_fg]="#DEB266"

# Color of inactive/disabled text
theme[inactive_fg]="#32473B"  

# Color of text appearing on top of graphs
theme[graph_text]="#E6D8BA"

# Misc colors for processes box
theme[proc_misc]="#E6D8BA"

# Cpu box outline color
theme[cpu_box]="#81B8A8"

# Memory/disks box outline color
theme[mem_box]="#81B8A8"

# Net up/down box outline color
theme[net_box]="#81B8A8"

# Processes box outline color
theme[proc_box]="#81B8A8"

# Box divider line and small boxes line color
theme[div_line]="#81B8A8"

# Temperature graph colors
theme[temp_start]="#BFD99A"
theme[temp_mid]="#E1B55E"
theme[temp_end]="#DBB05C"

# CPU graph colors
theme[cpu_start]="#5F8C86"
theme[cpu_mid]="#629C89"
theme[cpu_end]="#76AD98"

# Mem/Disk free meter
theme[free_start]="#5F8C86"
theme[free_mid]="#629C89"
theme[free_end]="#76AD98"

# Mem/Disk cached meter
theme[cached_start]="#5F8C86"
theme[cached_mid]="#629C89"
theme[cached_end]="#76AD98"

# Mem/Disk available meter
theme[available_start]="#5F8C86"
theme[available_mid]="#629C89"
theme[available_end]="#76AD98"

# Mem/Disk used meter
theme[used_start]="#5F8C86"
theme[used_mid]="#629C89"
theme[used_end]="#76AD98"

# Download graph colors
theme[download_start]="#75BBB3"
theme[download_mid]="#61949A"
theme[download_end]="#215866"

# Upload graph colors
theme[upload_start]="#215866"
theme[upload_mid]="#91C080"
theme[upload_end]="#549E6A"

# Process box color gradient for threads, mem and cpu usage
theme[process_start]="#72CFA3"
theme[process_mid]="#D0D494"
theme[process_end]="#DB9F9C"
```

- [ ] **Step 14: Write `themes/osaka-jade/vscode.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$SCRIPT_DIR/../set-vscode-theme.sh"

omawsl_theme_apply_vscode "Ocean Green: Dark" "jovejonovski.ocean-green"
```

- [ ] **Step 15: Write `themes/osaka-jade/windows-terminal-scheme.json`**

```json
{
    "name": "Osaka Jade",
    "background": "#111c18",
    "foreground": "#c1c497",
    "cursorColor": "#d7c995",
    "selectionBackground": "#23372b",
    "black": "#23372b",
    "red": "#ff5345",
    "green": "#549e6a",
    "yellow": "#459451",
    "blue": "#509475",
    "purple": "#d2689c",
    "cyan": "#2dd5b7",
    "white": "#f6f5dd",
    "brightBlack": "#53685b",
    "brightRed": "#db9f9c",
    "brightGreen": "#63b07a",
    "brightYellow": "#e5c736",
    "brightBlue": "#acd4cf",
    "brightPurple": "#75bbb3",
    "brightCyan": "#8cd3cb",
    "brightWhite": "#9eebb3"
}
```

- [ ] **Step 16: Write `themes/ristretto/neovim.lua`**

```lua
return {
	{
		"gthelding/monokai-pro.nvim",
		config = function()
			require("monokai-pro").setup({
				filter = "ristretto",
				override = function()
					return {
						NonText = { fg = "#948a8b" },
					}
				end,
			})
			vim.cmd([[colorscheme monokai-pro]])
		end,
	},
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "monokai-pro",
		},
	},
}
```

- [ ] **Step 17: Write `themes/ristretto/zellij.kdl`**

```kdl
themes {
    ristretto {
        fg "#e6d9db"
        bg "#2c2525"
        red "#fd6883"
        green "#adda78"
        yellow "#f9cc6c"
        blue "#f38d70"
        orange "#FFA066"
        magenta "#a8a9eb"
        cyan "#85dacc"
        black "#2c2525"
        white "#e6d9db"
    }
}
```

- [ ] **Step 18: Write `themes/ristretto/btop.theme`**

```
#Btop monokai pro ristretto theme
#Reconfigured from monokai theme

# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]="#2c2421"

# Main text color
theme[main_fg]="#e6d9db"

# Title color for boxes
theme[title]="#e6d9db"

# Higlight color for keyboard shortcuts
theme[hi_fg]="#fd6883"

# Background color of selected item in processes box
theme[selected_bg]="#3d2f2a"

# Foreground color of selected item in processes box
theme[selected_fg]="#e6d9db"

# Color of inactive/disabled text
theme[inactive_fg]="#72696a"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="#adda78"

# Cpu box outline color
theme[cpu_box]="#5b4a45"

# Memory/disks box outline color
theme[mem_box]="#5b4a45"

# Net up/down box outline color
theme[net_box]="#5b4a45"

# Processes box outline color
theme[proc_box]="#5b4a45"

# Box divider line and small boxes line color
theme[div_line]="#72696a"

# Temperature graph colors
theme[temp_start]="#a8a9eb"
theme[temp_mid]="#f38d70"
theme[temp_end]="#fd6a85"

# CPU graph colors
theme[cpu_start]="#adda78"
theme[cpu_mid]="#f9cc6c"
theme[cpu_end]="#fd6883"

# Mem/Disk free meter
theme[free_start]="#5b4a45"
theme[free_mid]="#adda78"
theme[free_end]="#c5e2a3"

# Mem/Disk cached meter
theme[cached_start]="#5b4a45"
theme[cached_mid]="#85dacc"
theme[cached_end]="#b3e8dd"

# Mem/Disk available meter
theme[available_start]="#5b4a45"
theme[available_mid]="#f9cc6c"
theme[available_end]="#fce2a3"

# Mem/Disk used meter
theme[used_start]="#5b4a45"
theme[used_mid]="#fd6a85"
theme[used_end]="#feb5c7"

# Download graph colors
theme[download_start]="#3d2f2a"
theme[download_mid]="#a8a9eb"
theme[download_end]="#c5c6f0"

# Upload graph colors
theme[upload_start]="#3d2f2a"
theme[upload_mid]="#fd6a85"
theme[upload_end]="#feb5c7"
```

- [ ] **Step 19: Write `themes/ristretto/vscode.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$SCRIPT_DIR/../set-vscode-theme.sh"

omawsl_theme_apply_vscode "Monokai Pro (Filter Ristretto)" "monokai.theme-monokai-pro-vscode"
```

- [ ] **Step 20: Write `themes/ristretto/windows-terminal-scheme.json`**

```json
{
    "name": "Ristretto",
    "background": "#2c2525",
    "foreground": "#e6d9db",
    "cursorColor": "#c3b7b8",
    "selectionBackground": "#403e41",
    "black": "#2c2525",
    "red": "#fd6883",
    "green": "#adda78",
    "yellow": "#f9cc6c",
    "blue": "#f38d70",
    "purple": "#a8a9eb",
    "cyan": "#85dacc",
    "white": "#e6d9db",
    "brightBlack": "#463a3a",
    "brightRed": "#ff8297",
    "brightGreen": "#c8e292",
    "brightYellow": "#fcd675",
    "brightBlue": "#f8a788",
    "brightPurple": "#bebffd",
    "brightCyan": "#9bf1e1",
    "brightWhite": "#f1e5e7"
}
```

- [ ] **Step 21: Commit**

```bash
git add themes/matte-black themes/nord themes/osaka-jade themes/ristretto
git commit -m "feat: port matte-black, nord, osaka-jade, ristretto themes"
```

---

### Task 5: Port themes batch 3 — rose-pine, tokyo-night

**Files:**
- Create: `themes/rose-pine/{neovim.lua,zellij.kdl,btop.theme,vscode.sh,windows-terminal-scheme.json}`
- Create: `themes/tokyo-night/{neovim.lua,zellij.kdl,btop.theme,vscode.sh,windows-terminal-scheme.json}`
- Test: `tests/theme_files_test.bats` (extend)

rose-pine is upstream's only **light** theme (background `#faf4ed`) — ported as-is, no special-casing needed since every theme file (zellij, btop, VS Code, Windows Terminal) just carries whatever colors it carries. tokyo-night's upstream `zellij.kdl` fragment is the only one of the 10 using space-separated RGB decimal instead of `"#hex"` strings — kept exactly as upstream wrote it (both are valid zellij KDL syntax).

- [ ] **Step 1: Write `themes/rose-pine/neovim.lua`**

```lua
return {
	{ "rose-pine/neovim", name = "rose-pine" },
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "rose-pine-dawn",
		},
	},
}
```

- [ ] **Step 2: Write `themes/rose-pine/zellij.kdl`**

```kdl
themes {
	rose-pine {
		bg "#faf4ed"
		fg "#575279"
		red "#b4637a"
		green "#286983"
		blue "#56949f"
		yellow "#ea9d34"
		magenta "#907aa9"
		orange "#fe640b"
		cyan "#d7827e"
		black "#f2e9e1"
		white "#575279"
	}
}
```

- [ ] **Step 3: Write `themes/rose-pine/btop.theme`**

```
# Main background, empty for terminal default, need to be empty if you want transparent background
theme[main_bg]="#faf4ed"
# Base

# Main text color
theme[main_fg]="#575279"
# Text

# Title color for boxes
theme[title]="#908caa"
# Subtle

# Highlight color for keyboard shortcuts
theme[hi_fg]="#e0def4"
# Text

# Background color of selected item in processes box
theme[selected_bg]="#524f67"
# HL High

# Foreground color of selected item in processes box
theme[selected_fg]="#f6c177"
# Gold

# Color of inactive/disabled text
theme[inactive_fg]="#403d52"
# HL Med

# Color of text appearing on top of graphs, i.e uptime and current network graph scaling
theme[graph_text]="#9ccfd8"
# Foam

# Background color of the percentage meters
theme[meter_bg]="#9ccfd8"
# Foam

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="#c4a7e7"
# Iris

# Cpu box outline color
theme[cpu_box]="#ebbcba"
# Rose

# Memory/disks box outline color
theme[mem_box]="#31748f"
# Pine

# Net up/down box outline color
theme[net_box]="#c4a7e7"
# Iris

# Processes box outline color
theme[proc_box]="#eb6f92"
# Love

# Box divider line and small boxes line color
theme[div_line]="#6e6a86"
# Muted

# Temperature graph colors
theme[temp_start]="#ebbcba"
# Rose
theme[temp_mid]="#f6c177"
# Gold
theme[temp_end]="#eb6f92"
# Love

# CPU graph colors
theme[cpu_start]="#f6c177"
# Gold
theme[cpu_mid]="#ebbcba"
# Rose
theme[cpu_end]="#eb6f92"
# Love

# Mem/Disk free meter
# all love
theme[free_start]="#eb6f92"
theme[free_mid]="#eb6f92"
theme[free_end]="#eb6f92"

# Mem/Disk cached meter
# all iris
theme[cached_start]="#c4a7e7"
theme[cached_mid]="#c4a7e7"
theme[cached_end]="#c4a7e7"

# Mem/Disk available meter
# all pine
theme[available_start]="#31748f"
theme[available_mid]="#31748f"
theme[available_end]="#31748f"

# Mem/Disk used meter
# all rose
theme[used_start]="#ebbcba"
theme[used_mid]="#ebbcba"
theme[used_end]="#ebbcba"

# Download graph colors
# Pine for start, foam for the rest
theme[download_start]="#31748f"
theme[download_mid]="#9ccfd8"
theme[download_end]="#9ccfd8"

# Upload graph colors
theme[upload_start]="#ebbcba"
# Rose for start
theme[upload_mid]="#eb6f92"
# Love for mid and end
theme[upload_end]="#eb6f92"

# Process box color gradient for threads, mem and cpu usage
theme[process_start]="#31748f"
# Pine
theme[process_mid]="#9ccfd8"
# Foam for mid and end
theme[process_end]="#9ccfd8"
```

- [ ] **Step 4: Write `themes/rose-pine/vscode.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$SCRIPT_DIR/../set-vscode-theme.sh"

omawsl_theme_apply_vscode "Rosé Pine Dawn" "mvllow.rose-pine"
```

- [ ] **Step 5: Write `themes/rose-pine/windows-terminal-scheme.json`**

```json
{
    "name": "Rose Pine",
    "background": "#faf4ed",
    "foreground": "#575279",
    "cursorColor": "#cecacd",
    "selectionBackground": "#dfdad9",
    "black": "#f2e9e1",
    "red": "#b4637a",
    "green": "#286983",
    "yellow": "#ea9d34",
    "blue": "#56949f",
    "purple": "#907aa9",
    "cyan": "#d7827e",
    "white": "#575279",
    "brightBlack": "#9893a5",
    "brightRed": "#b4637a",
    "brightGreen": "#286983",
    "brightYellow": "#ea9d34",
    "brightBlue": "#56949f",
    "brightPurple": "#907aa9",
    "brightCyan": "#d7827e",
    "brightWhite": "#575279"
}
```

- [ ] **Step 6: Write `themes/tokyo-night/neovim.lua`**

```lua
return {
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "tokyonight",
		},
	},
}
```

- [ ] **Step 7: Write `themes/tokyo-night/zellij.kdl`**

```kdl
themes {
    tokyo-night {
        fg 169 177 214
        bg 26 27 38
        black 56 62 90
        red 249 51 87
        green 158 206 106
        yellow 224 175 104
        blue 122 162 247
        magenta 187 154 247
        cyan 42 195 222
        white 192 202 245
        orange 255 158 100
    }
}
```

- [ ] **Step 8: Write `themes/tokyo-night/btop.theme`**

```
# Theme: tokyo-night
# By: Pascal Jaeger

# Main bg
theme[main_bg]="#1a1b26"

# Main text color
theme[main_fg]="#cfc9c2"

# Title color for boxes
theme[title]="#cfc9c2"

# Highlight color for keyboard shortcuts
theme[hi_fg]="#7dcfff"

# Background color of selected item in processes box
theme[selected_bg]="#414868"

# Foreground color of selected item in processes box
theme[selected_fg]="#cfc9c2"

# Color of inactive/disabled text
theme[inactive_fg]="#565f89"

# Misc colors for processes box including mini cpu graphs, details memory graph and details status text
theme[proc_misc]="#7dcfff"

# Cpu box outline color
theme[cpu_box]="#565f89"

# Memory/disks box outline color
theme[mem_box]="#565f89"

# Net up/down box outline color
theme[net_box]="#565f89"

# Processes box outline color
theme[proc_box]="#565f89"

# Box divider line and small boxes line color
theme[div_line]="#565f89"

# Temperature graph colors
theme[temp_start]="#9ece6a"
theme[temp_mid]="#e0af68"
theme[temp_end]="#f7768e"

# CPU graph colors
theme[cpu_start]="#9ece6a"
theme[cpu_mid]="#e0af68"
theme[cpu_end]="#f7768e"

# Mem/Disk free meter
theme[free_start]="#9ece6a"
theme[free_mid]="#e0af68"
theme[free_end]="#f7768e"

# Mem/Disk cached meter
theme[cached_start]="#9ece6a"
theme[cached_mid]="#e0af68"
theme[cached_end]="#f7768e"

# Mem/Disk available meter
theme[available_start]="#9ece6a"
theme[available_mid]="#e0af68"
theme[available_end]="#f7768e"

# Mem/Disk used meter
theme[used_start]="#9ece6a"
theme[used_mid]="#e0af68"
theme[used_end]="#f7768e"

# Download graph colors
theme[download_start]="#9ece6a"
theme[download_mid]="#e0af68"
theme[download_end]="#f7768e"

# Upload graph colors
theme[upload_start]="#9ece6a"
theme[upload_mid]="#e0af68"
theme[upload_end]="#f7768e"
```

- [ ] **Step 9: Write `themes/tokyo-night/vscode.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$SCRIPT_DIR/../set-vscode-theme.sh"

omawsl_theme_apply_vscode "Tokyo Night" "enkia.tokyo-night"
```

- [ ] **Step 10: Write `themes/tokyo-night/windows-terminal-scheme.json`**

Upstream `alacritty.toml` has a `[colors.selection]` block with only `background` (no `text` key) and no `[colors.cursor]` block — `cursorColor` falls back to `foreground`, `selectionBackground` uses the explicit `background` value.

```json
{
    "name": "Tokyo Night",
    "background": "#1a1b26",
    "foreground": "#a9b1d6",
    "cursorColor": "#a9b1d6",
    "selectionBackground": "#7aa2f7",
    "black": "#32344a",
    "red": "#f7768e",
    "green": "#9ece6a",
    "yellow": "#e0af68",
    "blue": "#7aa2f7",
    "purple": "#ad8ee6",
    "cyan": "#449dab",
    "white": "#787c99",
    "brightBlack": "#444b6a",
    "brightRed": "#ff7a93",
    "brightGreen": "#b9f27c",
    "brightYellow": "#ff9e64",
    "brightBlue": "#7da6ff",
    "brightPurple": "#bb9af7",
    "brightCyan": "#0db9d7",
    "brightWhite": "#acb0d0"
}
```

- [ ] **Step 11: Run the full theme-files test suite**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/theme_files_test.bats"`
Expected: PASS — all 10 themes now present with all 5 files each, all `windows-terminal-scheme.json` files valid.

- [ ] **Step 12: Commit**

```bash
git add themes/rose-pine themes/tokyo-night
git commit -m "feat: port rose-pine and tokyo-night themes"
```

---

### Task 6: Windows Terminal `settings.json` sync

**Files:**
- Modify: `install/lib.sh`
- Create: `bin/omawsl-sub/windows-terminal.sh`
- Test: `tests/windows_terminal_test.bats`

**Interfaces:**
- Produces: `omawsl_windows_userprofile` (in `install/lib.sh`, no args, prints a WSL path or returns 1), `omawsl_windows_terminal_settings_path` (no args, prints a path or returns 1), `omawsl_theme_apply_windows_terminal <scheme_file>` — consumed by `bin/omawsl-sub/theme.sh` (Task 7).

- [ ] **Step 1: Write the failing tests**

Create `tests/windows_terminal_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  WINHOME="$BATS_TEST_TMPDIR/winhome"
  mkdir -p "$WINHOME"

  cmd.exe() {
    if [[ "$*" == *USERPROFILE* ]]; then
      printf 'C:\\Users\\testuser\r\n'
    fi
  }
  export -f cmd.exe

  wslpath() {
    echo "$WINHOME"
  }
  export -f wslpath

  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/windows-terminal.sh"
  command -v jq &>/dev/null || skip "jq not installed on this test host"
}

@test "omawsl_windows_userprofile resolves via cmd.exe and wslpath" {
  run omawsl_windows_userprofile
  [ "$status" -eq 0 ]
  [ "$output" = "$WINHOME" ]
}

@test "omawsl_windows_userprofile fails cleanly when cmd.exe isn't reachable" {
  unset -f cmd.exe
  run omawsl_windows_userprofile
  [ "$status" -ne 0 ]
}

@test "omawsl_windows_terminal_settings_path finds the Store-package path first" {
  local store_dir="$WINHOME/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
  mkdir -p "$store_dir"
  echo '{"schemes":[],"profiles":{"defaults":{}}}' > "$store_dir/settings.json"
  run omawsl_windows_terminal_settings_path
  [ "$status" -eq 0 ]
  [ "$output" = "$store_dir/settings.json" ]
}

@test "omawsl_windows_terminal_settings_path falls back to the unpackaged path" {
  local unpackaged_dir="$WINHOME/AppData/Local/Microsoft/Windows Terminal"
  mkdir -p "$unpackaged_dir"
  echo '{"schemes":[],"profiles":{"defaults":{}}}' > "$unpackaged_dir/settings.json"
  run omawsl_windows_terminal_settings_path
  [ "$status" -eq 0 ]
  [ "$output" = "$unpackaged_dir/settings.json" ]
}

@test "omawsl_windows_terminal_settings_path fails when neither path exists" {
  run omawsl_windows_terminal_settings_path
  [ "$status" -ne 0 ]
}

@test "omawsl_theme_apply_windows_terminal merges the scheme, backs up first, and sets the default colorScheme" {
  local store_dir="$WINHOME/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
  mkdir -p "$store_dir"
  echo '{"schemes":[{"name":"Other Scheme","background":"#000000"}],"profiles":{"defaults":{"colorScheme":"Other Scheme"}}}' > "$store_dir/settings.json"

  run omawsl_theme_apply_windows_terminal "$REPO_ROOT/themes/tokyo-night/windows-terminal-scheme.json"
  [ "$status" -eq 0 ]

  [ -f "$store_dir/settings.json.bak" ]
  [[ "$(jq -r '.profiles.defaults.colorScheme' "$store_dir/settings.json")" == "Tokyo Night" ]]
  [[ "$(jq -r '.schemes | map(.name) | sort | join(",")' "$store_dir/settings.json")" == "Other Scheme,Tokyo Night" ]]
  [[ "$(jq -r '.schemes[] | select(.name == "Tokyo Night") | .background' "$store_dir/settings.json")" == "#1a1b26" ]]
}

@test "omawsl_theme_apply_windows_terminal replaces a same-named scheme instead of duplicating it" {
  local store_dir="$WINHOME/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState"
  mkdir -p "$store_dir"
  echo '{"schemes":[{"name":"Tokyo Night","background":"#000000"}],"profiles":{"defaults":{}}}' > "$store_dir/settings.json"

  run omawsl_theme_apply_windows_terminal "$REPO_ROOT/themes/tokyo-night/windows-terminal-scheme.json"
  [ "$status" -eq 0 ]
  [[ "$(jq -r '.schemes | length' "$store_dir/settings.json")" == "1" ]]
  [[ "$(jq -r '.schemes[0].background' "$store_dir/settings.json")" == "#1a1b26" ]]
}

@test "omawsl_theme_apply_windows_terminal skips gracefully when settings.json can't be found" {
  run omawsl_theme_apply_windows_terminal "$REPO_ROOT/themes/tokyo-night/windows-terminal-scheme.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"docs/windows-setup.md"* ]]
}

@test "omawsl_theme_apply_windows_terminal skips gracefully when jq isn't reachable" {
  stub_hide_command jq wslpath
  wslpath() { echo "$WINHOME"; }
  export -f wslpath
  run omawsl_theme_apply_windows_terminal "$REPO_ROOT/themes/tokyo-night/windows-terminal-scheme.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"jq"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/windows_terminal_test.bats"`
Expected: FAIL — `omawsl_windows_userprofile: command not found`, and `bin/omawsl-sub/windows-terminal.sh: No such file or directory`.

- [ ] **Step 3: Add `omawsl_windows_userprofile` to `install/lib.sh`**

Append to the end of `install/lib.sh` (after `omawsl_cursor_reachable`):

```bash

# omawsl_windows_userprofile
# Resolves the Windows user's profile directory as a WSL path
# (e.g. /mnt/c/Users/<name>) via cmd.exe + wslpath, rather than
# assuming the Windows username matches $USER - design spec §11 flags
# this as a real, common mismatch. Prints nothing and returns 1 if
# cmd.exe/wslpath aren't reachable (e.g. outside real WSL2, as in the
# bats suite unless stubbed) or the lookup comes back empty.
omawsl_windows_userprofile() {
  command -v cmd.exe &>/dev/null || return 1
  command -v wslpath &>/dev/null || return 1
  local win_path
  win_path="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r\n')"
  [[ -n "$win_path" ]] || return 1
  wslpath -u "$win_path"
}
```

- [ ] **Step 4: Write `bin/omawsl-sub/windows-terminal.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"

# omawsl_windows_terminal_settings_path
# Locates Windows Terminal's real settings.json under the resolved
# Windows user profile. Checks the Microsoft Store package path first
# (the install method docs/windows-setup.md recommends, design spec
# §13), then the unpackaged/portable install path. Prints nothing and
# returns 1 if neither exists yet, or if the profile itself can't be
# resolved.
omawsl_windows_terminal_settings_path() {
  local profile
  profile="$(omawsl_windows_userprofile)" || return 1

  local store_path="$profile/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
  local unpackaged_path="$profile/AppData/Local/Microsoft/Windows Terminal/settings.json"

  if [[ -f "$store_path" ]]; then
    echo "$store_path"
  elif [[ -f "$unpackaged_path" ]]; then
    echo "$unpackaged_path"
  else
    return 1
  fi
}

# omawsl_theme_apply_windows_terminal <scheme_file>
# Merges one windows-terminal-scheme.json fragment into Windows
# Terminal's settings.json `schemes` array (replacing any prior entry
# of the same name) and sets it as the default profile's colorScheme -
# design spec §11's one exception to "no automatic Windows-side edits"
# (§2): a local JSON edit to an already-installed app, no network call,
# no admin rights. Always backs up first (settings.json.bak) since a
# corrupted settings.json breaks the user's whole terminal, not just
# the theme. Prefers jq over sed because `schemes` is a nested array,
# not a single-line key. Skips gracefully (prints a
# docs/windows-setup.md pointer, returns 0) if jq or Windows Terminal's
# settings.json can't be found - never fails the rest of
# `bin/omawsl theme`. Targets `profiles.defaults.colorScheme` (applies
# to every profile unless a specific one overrides it) rather than
# hunting for "the" WSL profile object by name/source/GUID, which is
# more fragile across install configurations.
omawsl_theme_apply_windows_terminal() {
  local scheme_file="$1"

  if ! command -v jq &>/dev/null; then
    echo "omawsl: 'jq' isn't available - skipping the Windows Terminal color sync."
    echo "See docs/windows-setup.md#windows-terminal-theme for the manual steps."
    return 0
  fi

  local settings_file
  if ! settings_file="$(omawsl_windows_terminal_settings_path)"; then
    echo "omawsl: couldn't find Windows Terminal's settings.json - skipping the Windows Terminal color sync."
    echo "See docs/windows-setup.md#windows-terminal-theme for the manual steps."
    return 0
  fi

  cp "$settings_file" "$settings_file.bak"

  local tmp
  tmp="$(mktemp)"
  jq --argjson scheme "$(cat "$scheme_file")" \
    '.schemes = ((.schemes // []) | map(select(.name != $scheme.name))) + [$scheme]
     | .profiles.defaults.colorScheme = $scheme.name' \
    "$settings_file" > "$tmp"

  if ! jq empty "$tmp" 2>/dev/null; then
    echo "omawsl: the Windows Terminal settings edit produced invalid JSON - leaving settings.json untouched (backup at $settings_file.bak)." >&2
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$settings_file"
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/windows_terminal_test.bats"`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add install/lib.sh bin/omawsl-sub/windows-terminal.sh tests/windows_terminal_test.bats
git commit -m "feat: sync applied theme colors into Windows Terminal's settings.json"
```

---

### Task 7: `bin/omawsl` dispatcher + `bin/omawsl theme` subcommand + PATH symlink

**Files:**
- Create: `bin/omawsl`
- Create: `bin/omawsl-sub/theme.sh`
- Modify: `install/terminal/apps-terminal.sh`
- Test: `tests/omawsl_cli_test.bats`
- Test: `tests/apps_terminal_test.bats` (extend)

**Interfaces:**
- Consumes: `omawsl_theme_apply_windows_terminal` (Task 6), `omawsl_theme_apply_vscode` (Task 2, via each theme's `vscode.sh`).
- Produces: `omawsl_theme_names`, `omawsl_theme_is_valid <name>`, `omawsl_theme_display_name <name>`, `omawsl_theme_folder_name <display_name>`, `omawsl_theme_opencode_preset <name>`, `omawsl_theme_apply_opencode <name>`, `omawsl_theme_apply <name>`, `omawsl_theme_command [name]` (all in `bin/omawsl-sub/theme.sh`) — `omawsl_theme_command` is what `bin/omawsl theme` dispatches to, and is the extension point Phase 7 will add four siblings next to (`omawsl_update_command`, etc.), each in its own `bin/omawsl-sub/<name>.sh`.

- [ ] **Step 1: Write the failing tests**

Create `tests/omawsl_cli_test.bats`:

```bash
#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/bin/omawsl-sub/theme.sh"
}

@test "omawsl_theme_names lists all 10 themes" {
  [[ "$(omawsl_theme_names | wc -l)" -eq 10 ]]
  [[ "$(omawsl_theme_names)" == *"tokyo-night"* ]]
  [[ "$(omawsl_theme_names)" == *"rose-pine"* ]]
}

@test "omawsl_theme_is_valid accepts real theme names and rejects unknown ones" {
  omawsl_theme_is_valid "tokyo-night"
  omawsl_theme_is_valid "rose-pine"
  ! omawsl_theme_is_valid "not-a-real-theme"
}

@test "omawsl_theme_display_name title-cases hyphenated folder names" {
  [[ "$(omawsl_theme_display_name "rose-pine")" == "Rose Pine" ]]
  [[ "$(omawsl_theme_display_name "tokyo-night")" == "Tokyo Night" ]]
  [[ "$(omawsl_theme_display_name "osaka-jade")" == "Osaka Jade" ]]
  [[ "$(omawsl_theme_display_name "catppuccin")" == "Catppuccin" ]]
}

@test "omawsl_theme_folder_name reverses omawsl_theme_display_name and is idempotent on folder form" {
  [[ "$(omawsl_theme_folder_name "Rose Pine")" == "rose-pine" ]]
  [[ "$(omawsl_theme_folder_name "rose-pine")" == "rose-pine" ]]
}

@test "omawsl_theme_apply rejects an unknown theme name without touching anything" {
  run omawsl_theme_apply "not-a-real-theme"
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown theme"* ]]
  [ ! -d "$HOME/.config/zellij" ]
}

@test "omawsl_theme_apply copies the zellij/btop theme files and patches the active references" {
  mkdir -p "$HOME/.config/zellij" "$HOME/.config/btop"
  cp "$REPO_ROOT/configs/zellij.kdl" "$HOME/.config/zellij/config.kdl"
  cp "$REPO_ROOT/configs/btop.conf" "$HOME/.config/btop/btop.conf"

  run omawsl_theme_apply "tokyo-night"
  [ "$status" -eq 0 ]

  diff "$HOME/.config/zellij/themes/tokyo-night.kdl" "$REPO_ROOT/themes/tokyo-night/zellij.kdl"
  grep -q 'theme "tokyo-night"' "$HOME/.config/zellij/config.kdl"

  diff "$HOME/.config/btop/themes/tokyo-night.theme" "$REPO_ROOT/themes/tokyo-night/btop.theme"
  grep -q 'color_theme = "tokyo-night"' "$HOME/.config/btop/btop.conf"
}

@test "omawsl_theme_apply only touches neovim's theme.lua when ~/.config/nvim exists" {
  run omawsl_theme_apply "tokyo-night"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/nvim/lua/plugins/theme.lua" ]

  mkdir -p "$HOME/.config/nvim"
  run omawsl_theme_apply "tokyo-night"
  [ "$status" -eq 0 ]
  diff "$HOME/.config/nvim/lua/plugins/theme.lua" "$REPO_ROOT/themes/tokyo-night/neovim.lua"
}

@test "omawsl_theme_apply syncs the Windows Terminal scheme via omawsl_theme_apply_windows_terminal" {
  omawsl_theme_apply_windows_terminal() { echo "windows-terminal-sync-called $1" >> "$STUB_LOG"; }
  export -f omawsl_theme_apply_windows_terminal
  run omawsl_theme_apply "tokyo-night"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"windows-terminal-sync-called $REPO_ROOT/themes/tokyo-night/windows-terminal-scheme.json"* ]]
}

@test "omawsl_theme_opencode_preset maps the 6 themes with a real opencode built-in preset" {
  [[ "$(omawsl_theme_opencode_preset "tokyo-night")" == "tokyonight" ]]
  [[ "$(omawsl_theme_opencode_preset "everforest")" == "everforest" ]]
  [[ "$(omawsl_theme_opencode_preset "catppuccin")" == "catppuccin" ]]
  [[ "$(omawsl_theme_opencode_preset "gruvbox")" == "gruvbox" ]]
  [[ "$(omawsl_theme_opencode_preset "kanagawa")" == "kanagawa" ]]
  [[ "$(omawsl_theme_opencode_preset "nord")" == "nord" ]]
}

@test "omawsl_theme_opencode_preset fails for the 4 themes with no built-in opencode preset" {
  ! omawsl_theme_opencode_preset "matte-black"
  ! omawsl_theme_opencode_preset "osaka-jade"
  ! omawsl_theme_opencode_preset "ristretto"
  ! omawsl_theme_opencode_preset "rose-pine"
}

@test "omawsl_theme_apply_opencode sets the theme key when opencode is reachable and a preset exists" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  stub_command opencode
  run omawsl_theme_apply_opencode "tokyo-night"
  [ "$status" -eq 0 ]
  [[ "$(jq -r .theme "$HOME/.config/opencode/tui.json")" == "tokyonight" ]]
}

@test "omawsl_theme_apply_opencode no-ops when opencode isn't reachable" {
  stub_hide_command opencode
  run omawsl_theme_apply_opencode "tokyo-night"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/opencode/tui.json" ]
}

@test "omawsl_theme_apply_opencode no-ops for a theme with no built-in opencode preset" {
  stub_command opencode
  run omawsl_theme_apply_opencode "rose-pine"
  [ "$status" -eq 0 ]
  [ ! -f "$HOME/.config/opencode/tui.json" ]
}

@test "omawsl_theme_command applies the exact theme name given on the command line" {
  omawsl_theme_apply() { echo "apply-called $1" >> "$STUB_LOG"; }
  export -f omawsl_theme_apply
  run omawsl_theme_command "rose-pine"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"apply-called rose-pine"* ]]
}

@test "omawsl_theme_command accepts the Title Case display form too" {
  omawsl_theme_apply() { echo "apply-called $1" >> "$STUB_LOG"; }
  export -f omawsl_theme_apply
  run omawsl_theme_command "Rose Pine"
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"apply-called rose-pine"* ]]
}

@test "omawsl_theme_command with no args prompts via gum and applies the chosen theme" {
  omawsl_theme_apply() { echo "apply-called $1" >> "$STUB_LOG"; }
  export -f omawsl_theme_apply
  gum_stub_init
  gum_stub_respond "Tokyo Night"
  run omawsl_theme_command
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" == *"apply-called tokyo-night"* ]]
}
```

Create/extend `tests/apps_terminal_test.bats` with:

```bash
@test "installs a bin/omawsl wrapper into ~/.local/bin that execs the real script" {
  run omawsl_install_cli
  [ "$status" -eq 0 ]
  [ -x "$HOME/.local/bin/omawsl" ]
  [[ "$(cat "$HOME/.local/bin/omawsl")" == *"exec bash \"$REPO_ROOT/bin/omawsl\""* ]]
}
```

Create `bin/omawsl` dispatcher test coverage directly (not through bats, since it's a thin dispatcher) as part of `tests/omawsl_cli_test.bats`:

```bash
@test "bin/omawsl theme with a valid name applies it end to end (real jq, real files)" {
  command -v jq &>/dev/null || skip "jq not installed on this test host"
  mkdir -p "$HOME/.config/zellij" "$HOME/.config/btop"
  cp "$REPO_ROOT/configs/zellij.kdl" "$HOME/.config/zellij/config.kdl"
  cp "$REPO_ROOT/configs/btop.conf" "$HOME/.config/btop/btop.conf"
  run bash "$REPO_ROOT/bin/omawsl" theme tokyo-night
  [ "$status" -eq 0 ]
  [ -f "$HOME/.config/zellij/themes/tokyo-night.kdl" ]
}

@test "bin/omawsl with an unknown command prints usage and exits non-zero" {
  run bash "$REPO_ROOT/bin/omawsl" not-a-real-command
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
  [[ "$output" == *"Usage: omawsl"* ]]
}

@test "bin/omawsl with no args prints usage and exits zero" {
  run bash "$REPO_ROOT/bin/omawsl"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: omawsl"* ]]
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/omawsl_cli_test.bats tests/apps_terminal_test.bats"`
Expected: FAIL — `bin/omawsl-sub/theme.sh: No such file or directory`, `bin/omawsl: No such file or directory`, `omawsl_install_cli: command not found`.

- [ ] **Step 3: Write `bin/omawsl-sub/theme.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=windows-terminal.sh
source "$SCRIPT_DIR/windows-terminal.sh"

# omawsl_theme_names
# The 10 ported theme folder names, in Omakub's own picker order
# (design spec §11).
omawsl_theme_names() {
  cat <<'EOF'
catppuccin
everforest
gruvbox
kanagawa
matte-black
nord
osaka-jade
ristretto
rose-pine
tokyo-night
EOF
}

# omawsl_theme_is_valid <folder_name>
omawsl_theme_is_valid() {
  omawsl_theme_names | grep -qx "$1"
}

# omawsl_theme_display_name <folder_name>
# Title-cases a folder name back to Omakub's own gum choose label (e.g.
# "rose-pine" -> "Rose Pine").
omawsl_theme_display_name() {
  echo "$1" | sed -E 's/(^|-)([a-z])/\1\U\2/g; s/-/ /g'
}

# omawsl_theme_folder_name <name>
# Reverses omawsl_theme_display_name - lower-cases and hyphenates,
# exactly what Omakub's own theme.sh does to its gum choose result.
# Idempotent on input that's already in folder form.
omawsl_theme_folder_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}

# omawsl_theme_opencode_preset <folder_name>
# Maps omawsl's theme folder names to opencode's own built-in preset
# names (opencode.ai/docs/themes/, ~/.config/opencode/tui.json's
# "theme" key) where a direct match exists. Fails (empty stdout,
# nonzero exit) for the 4 themes with no built-in opencode preset
# (matte-black, osaka-jade, ristretto, rose-pine) - design spec §11
# marks opencode theming "best-effort... skipped rather than forcing a
# workaround" for exactly this kind of gap; opencode's separate
# custom-theme JSON format for arbitrary colors is a different,
# unverified schema and out of scope here.
omawsl_theme_opencode_preset() {
  case "$1" in
    tokyo-night) echo "tokyonight" ;;
    everforest) echo "everforest" ;;
    catppuccin) echo "catppuccin" ;;
    gruvbox) echo "gruvbox" ;;
    kanagawa) echo "kanagawa" ;;
    nord) echo "nord" ;;
    *) return 1 ;;
  esac
}

# omawsl_theme_apply_opencode <folder_name>
# Sets opencode's own "theme" key when opencode is reachable and this
# theme has a built-in opencode preset (see
# omawsl_theme_opencode_preset above) - no-ops otherwise, same
# detect-and-defer shape as every other optional component this
# function touches.
omawsl_theme_apply_opencode() {
  local name="$1"
  command -v opencode &>/dev/null || return 0
  command -v jq &>/dev/null || return 0

  local preset
  preset="$(omawsl_theme_opencode_preset "$name")" || return 0

  local config_file="$HOME/.config/opencode/tui.json"
  mkdir -p "$(dirname "$config_file")"
  if [[ ! -f "$config_file" ]]; then
    echo '{"$schema": "https://opencode.ai/tui.json"}' > "$config_file"
  fi

  local tmp
  tmp="$(mktemp)"
  jq --arg theme "$preset" '.theme = $theme' "$config_file" > "$tmp"
  mv "$tmp" "$config_file"
}

# omawsl_theme_apply <folder_name>
# Applies one theme across every installed component, matching Omakub's
# own bin/omakub-sub/theme.sh (design spec §11): zellij (per-theme file
# + sed-patch the active reference), btop (same shape), Neovim (only if
# ~/.config/nvim exists - Phase 4's app-neovim.sh only creates it when
# Neovim was selected), VS Code/Cursor (via each theme's own vscode.sh,
# which sources themes/set-vscode-theme.sh - Task 2), opencode (only
# for the 6 themes with a built-in preset - see
# omawsl_theme_apply_opencode above), and Windows Terminal (Task 6).
omawsl_theme_apply() {
  local name="$1"
  local theme_dir="$OMAWSL_ROOT_DIR/themes/$name"

  if ! omawsl_theme_is_valid "$name"; then
    echo "omawsl: unknown theme '$name'" >&2
    echo "Valid themes: $(omawsl_theme_names | tr '\n' ' ')" >&2
    return 1
  fi

  mkdir -p "$HOME/.config/zellij/themes"
  cp "$theme_dir/zellij.kdl" "$HOME/.config/zellij/themes/$name.kdl"
  if [[ -f "$HOME/.config/zellij/config.kdl" ]]; then
    sed -i "s/theme \".*\"/theme \"$name\"/g" "$HOME/.config/zellij/config.kdl"
  fi

  if [[ -f "$HOME/.config/btop/btop.conf" ]]; then
    mkdir -p "$HOME/.config/btop/themes"
    cp "$theme_dir/btop.theme" "$HOME/.config/btop/themes/$name.theme"
    sed -i "s/color_theme = \".*\"/color_theme = \"$name\"/g" "$HOME/.config/btop/btop.conf"
  fi

  if [[ -d "$HOME/.config/nvim" ]]; then
    mkdir -p "$HOME/.config/nvim/lua/plugins"
    cp "$theme_dir/neovim.lua" "$HOME/.config/nvim/lua/plugins/theme.lua"
  fi

  # shellcheck source=/dev/null
  source "$theme_dir/vscode.sh"

  omawsl_theme_apply_opencode "$name"

  omawsl_theme_apply_windows_terminal "$theme_dir/windows-terminal-scheme.json"
}

# omawsl_theme_command [name]
# Entry point for `bin/omawsl theme [name]`. With no name, prompts via
# gum choose using Omakub's own Title Case labels (design spec §11);
# with a name, accepts either form ("rose-pine" or "Rose Pine") for
# convenience on the command line.
omawsl_theme_command() {
  local input="${1:-}"
  local name

  if [[ -z "$input" ]]; then
    local choice
    choice="$(omawsl_theme_names | while read -r n; do omawsl_theme_display_name "$n"; done | gum choose --header "Choose your theme")"
    [[ -n "$choice" ]] || return 0
    name="$(omawsl_theme_folder_name "$choice")"
  else
    name="$(omawsl_theme_folder_name "$input")"
  fi

  omawsl_theme_apply "$name"
}
```

- [ ] **Step 4: Write `bin/omawsl`**

```bash
#!/usr/bin/env bash
set -euo pipefail

OMAWSL_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=omawsl-sub/theme.sh
source "$OMAWSL_ROOT_DIR/bin/omawsl-sub/theme.sh"

# omawsl_usage
# Only "theme" is wired up this phase - Phase 7 adds update/migrate/
# uninstall/install/doctor here, each backed by its own
# bin/omawsl-sub/<command>.sh, same shape as theme.sh.
omawsl_usage() {
  cat <<'EOF'
Usage: omawsl <command> [args]

Commands:
  theme [name]   Apply one of the ported themes. With no name, choose
                 interactively.
EOF
}

omawsl_main() {
  local cmd="${1:-}"
  case "$cmd" in
    theme)
      shift
      omawsl_theme_command "$@"
      ;;
    ""|-h|--help)
      omawsl_usage
      ;;
    *)
      echo "omawsl: unknown command '$cmd'" >&2
      omawsl_usage >&2
      exit 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_main "$@"
fi
```

- [ ] **Step 5: Add `omawsl_install_cli` to `install/terminal/apps-terminal.sh`**

Modify `omawsl_install_terminal_apps` to also call the new function, and add the function itself:

```bash
omawsl_install_terminal_apps() {
  sudo apt-get update -qq
  sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop fastfetch lazygit jq

  omawsl_install_lazydocker
  omawsl_install_zellij
  omawsl_install_zellij_config
  omawsl_install_btop_config
  omawsl_install_cli
}
```

Add after `omawsl_install_btop_config`:

```bash
# omawsl_install_cli
# Installs a thin $HOME/.local/bin/omawsl wrapper (already on PATH via
# configs/bashrc) that execs bin/omawsl via `bash` explicitly, not a
# bare symlink - this repo is authored on Windows, where git does not
# reliably track the executable bit on checkout into WSL2's ext4
# (same root cause boot.sh's own top-level comment documents for
# install.sh). The wrapper file itself is freshly created directly on
# WSL's own ext4 filesystem, so its own +x bit (set below) is not
# subject to that problem. Always re-written (not guarded by an
# existence check) since it's just a thin pointer, not user-owned
# state - safe to keep in sync with OMAWSL_ROOT_DIR on every run.
omawsl_install_cli() {
  local root_dir
  root_dir="$(cd "$SCRIPT_DIR/../.." && pwd)"
  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/omawsl" <<EOF
#!/usr/bin/env bash
exec bash "$root_dir/bin/omawsl" "\$@"
EOF
  chmod +x "$HOME/.local/bin/omawsl"
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/omawsl_cli_test.bats tests/apps_terminal_test.bats"`
Expected: PASS.

- [ ] **Step 7: Run the full test suite**

Run: `wsl.exe -d Ubuntu -- bash -c "cd /mnt/c/Users/tcins/vscode-workspace/omawsl && tests/.bats-core/bin/bats tests/*.bats"`
Expected: PASS, all files (existing 147+ tests plus everything added in this plan).

- [ ] **Step 8: Commit**

```bash
git add bin/omawsl bin/omawsl-sub/theme.sh install/terminal/apps-terminal.sh tests/omawsl_cli_test.bats tests/apps_terminal_test.bats
git commit -m "feat: add bin/omawsl dispatcher with the theme subcommand"
```

---

### Task 8: Zellij/Windows Terminal keybinding collision fix (documented, interim)

**Files:**
- Create: `docs/zellij-keybinding-fixes.md`
- Modify: `docs/superpowers/plans/roadmap.md`

**Interfaces:** none — this is a documentation-only task. No code enforces the fix automatically; Task 9's human verification applies and confirms it for real, and Phase 6 folds the finding into `windows/windows-terminal.json`/`windows-terminal-fallback.json` (design spec §13) once those files exist.

This mirrors the `docs/prerequisites.md` pattern already established in Phase 4 (an interim, tracked stopgap outside the spec's documented doc structure, explicitly flagged for a later phase to fold in and delete) — recorded in project memory as a pattern that worked well.

- [ ] **Step 1: Write `docs/zellij-keybinding-fixes.md`**

```markdown
# Zellij / Windows Terminal keybinding fixes (interim)

> **Status: interim stopgap, added during Phase 5 (Theming).** This is **not**
> part of the design spec's documented doc structure (§13, §16) — it exists so
> the real, sourced finding below isn't lost before Phase 6 builds
> `docs/windows-setup.md` and `windows/windows-terminal.json` /
> `windows-terminal-fallback.json` (design spec §13). **Phase 6 must fold this
> finding into both of those `windows/*.json` files (both need the identical
> fix — it's independent of which font variant the user merged in) and delete
> this file.** Do not leave `windows-terminal.json` shipping without this fix
> just because this doc exists — the fix isn't real until it's in the JSON a
> user actually merges into their `settings.json`.

## The collision

Cross-referencing Omakub's real zellij keybindings (`configs/zellij.kdl`,
ported verbatim in Phase 5 Task 1) against Windows Terminal's real default
keybindings (`microsoft/terminal` `main` branch,
`src/cascadia/TerminalSettingsModel/defaults.json`) turns up exactly one
direct, real collision:

**`Alt+Left` / `Alt+Down` / `Alt+Up` / `Alt+Right`** is bound by both layers:

- Windows Terminal (default): `Terminal.MoveFocusLeft` / `Down` / `Up` / `Right`
  — moves focus between **Windows Terminal's own** split panes.
- zellij (`configs/zellij.kdl`, `shared_among "normal" "locked"`): the same
  four chords fire `MoveFocusOrTab`/`MoveFocus` between **zellij's own** panes
  — and critically, this is one of the few bindings zellij fires even in its
  default `locked` mode, without needing `Ctrl g` to unlock first.

Since Windows Terminal owns the keypress at the terminal-app layer, it
intercepts `Alt+Left/Down/Up/Right` before zellij (running inside it) ever
sees the keystroke — even when Windows Terminal itself has no other pane to
move focus to (the common case, since zellij is the pane multiplexer here,
not Windows Terminal). Net effect: these four zellij bindings are dead by
default under Windows Terminal.

Every other zellij binding was checked against the full Windows Terminal
default keybinding list and found *not* to collide — Omakub's zellij runs in
`default_mode "locked"` with `clear-defaults=true`, so almost nothing else
fires without first unlocking (`Ctrl g`) into a leader-key mode
(`p`=pane, `t`=tab, `r`=resize, `s`=scroll, `o`=session, `m`=move), and none
of those leader chords or their follow-up keys match a Windows Terminal
default.

## The fix

Unbind Windows Terminal's default `Alt+Left/Down/Up/Right` pane-focus
bindings so the keystroke passes through to zellij. Windows Terminal's
documented mechanism for clearing a default keybinding is to redeclare the
same `keys` with `"command": "unbound"` in the user's own `actions`/
`keybindings` array:

```json
{ "command": "unbound", "keys": "alt+left" },
{ "command": "unbound", "keys": "alt+down" },
{ "command": "unbound", "keys": "alt+up" },
{ "command": "unbound", "keys": "alt+right" }
```

**This exact JSON snippet is not yet verified against a real, current
Windows Terminal settings.json** — Windows Terminal's schema has evolved
(older `keybindings`/`command` vs. newer `actions`/`id`), and both are
believed still supported for backward compatibility, but this needs
confirming for real, not assumed. **Task 9 (manual verification) must apply
this snippet to the real test machine's actual Windows Terminal
`settings.json`, confirm `Alt+Left/Down/Up/Right` reaches zellij afterward,
and update this file with whatever the real, working form turns out to be**
before Phase 6 copies it into `windows/windows-terminal.json` /
`windows-terminal-fallback.json`.

## Everything else: confirmed non-issue, not a UX gap worth changing

- `Ctrl+Shift+T` (WT: new tab), `Ctrl+Shift+W` (WT: close pane) — no chord
  collision (zellij's own tab-new/pane-close are multi-key sequences behind
  `Ctrl g`), so no fix needed, even though WT "owns" these chords first.
- `Ctrl+Tab` / `Ctrl+Shift+Tab` (WT: next/prev tab) — no zellij binding on
  these chords at all.
- `Ctrl+,` (WT: settings), `Ctrl+Shift+F` (WT: find) — no zellij collision.
```

- [ ] **Step 2: Modify `docs/superpowers/plans/roadmap.md`'s Phase 6 entry**

Add a sentence to Phase 6's bullet (right after the existing `docs/prerequisites.md` breadcrumb), so this finding isn't lost:

```markdown
6. **Windows-side deliverables + README — not yet planned.**
   `docs/windows-setup.md`, `windows/` assets (both the Nerd Font and zero-install Cascadia
   Mono profile variants), and `README.md`'s required sections (exclusions list, "Before you
   begin"). **Must fold in and then delete `docs/prerequisites.md`** (an interim stopgap added
   during Phase 4's Task 13, outside the spec's documented doc structure): its GitHub Copilot
   CLI (`gh auth login`) and VS Code/Cursor (install on Windows first) content belongs in the
   one canonical quick-reference table `docs/windows-setup.md` §13 specifies, reused as-is by
   README's "Before you begin" §16. **Once that table exists and this file is deleted, update
   `install/terminal/app-gh-copilot.sh`'s failure message** (currently points at
   `docs/prerequisites.md#github-copilot-cli`) to point at the new location - don't leave a
   dangling reference to a deleted file. **Must also fold in and then delete
   `docs/zellij-keybinding-fixes.md`** (an interim stopgap added during Phase 5's own Task 8,
   same pattern as `docs/prerequisites.md`): its `Alt+Left/Down/Up/Right` unbind fix, confirmed
   for real against a live Windows Terminal `settings.json` during Phase 5's Task 9, must be
   baked into both `windows/windows-terminal.json` and `windows-terminal-fallback.json` (design
   spec §13 already requires both to resolve zellij keybinding collisions) before this file is
   deleted.
```

- [ ] **Step 3: Commit**

```bash
git add docs/zellij-keybinding-fixes.md docs/superpowers/plans/roadmap.md
git commit -m "docs: record the zellij/Windows Terminal Alt+arrow keybinding collision and fix"
```

---

### Task 9: Manual end-to-end verification (human-only — do not execute this task yourself)

**This task is not run by whoever is executing this plan.** Per this project's own established process (every prior phase's plan has ended with a human-only verification task; skipping straight to "roadmap: DONE" without it is a documented past mistake for this project — see the assistant's own persistent memory on this repo, "Don't skip the human verification task"), present these exact steps to the user and wait for them to actually run it and report back. Do not mark Phase 5 "DONE" in `docs/superpowers/plans/roadmap.md` until they do.

**Steps to hand to the user:**

1. Run `bash install.sh` (or a fresh `boot.sh` one-liner) against the real WSL2 Ubuntu instance to pick up this phase's changes (`configs/zellij.kdl`, `configs/btop.conf`, `jq`, `bin/omawsl`).
2. Confirm `omawsl theme` (no args) shows a `gum choose` picker listing all 10 themes by their Title Case names, and that choosing one (e.g. "Tokyo Night") exits cleanly.
3. Confirm the applied theme actually took effect:
   - `cat ~/.config/zellij/config.kdl` shows `theme "tokyo-night"`.
   - `cat ~/.config/btop/btop.conf` shows `color_theme = "tokyo-night"`; launch `btop` and confirm it visually matches the theme.
   - If Neovim was installed: open `nvim`, confirm the colorscheme matches.
   - If VS Code and/or Cursor were installed and connected at least once: confirm `workbench.colorTheme` in the Remote settings.json matches, and (VS Code only) that the extension got installed.
   - If opencode was installed and the applied theme is one of the 6 with a built-in opencode preset (tokyo-night, everforest, catppuccin, gruvbox, kanagawa, nord): confirm `~/.config/opencode/tui.json`'s `"theme"` key matches, and that `opencode` itself visually reflects it. For the other 4 themes (matte-black, osaka-jade, ristretto, rose-pine), confirm opencode is left on whatever theme it had before (no-op, by design).
4. Open a **real Windows Terminal window** and confirm its color scheme changed to match (background/foreground/ANSI colors) — this is the one automatic Windows-side edit this phase makes (design spec §11).
5. Run `bin/omawsl theme <name>` a second time with a *different* theme name, and confirm Windows Terminal's `schemes` array doesn't accumulate duplicate entries (should stay at exactly the themes applied, no dupes of the same name) — check via `Ctrl+,` → Settings UI → Color schemes, or by inspecting `settings.json` directly.
6. **Zellij keybinding-fidelity check (design spec §15 — every binding must be pressed for real, not assumed from a copied config):** inside a real zellij session running in the real Windows Terminal, exercise at minimum: `Ctrl g` (unlock), then each leader (`p`, `t`, `r`, `s`, `o`, `m`) and at least one action key in each mode (e.g. `p`→`n` new pane, `t`→`n` new tab, `r`→ resize, `s`→ scroll + `q` back out). Confirm each one reaches zellij as expected.
7. Specifically test `Alt+Left`, `Alt+Down`, `Alt+Up`, `Alt+Right` **before** applying Task 8's documented fix — confirm they do *not* reach zellij (Windows Terminal intercepts them), matching the collision `docs/zellij-keybinding-fixes.md` documents. Then apply the JSON snippet from that doc to the real Windows Terminal `settings.json`, restart Windows Terminal, and re-test the same four chords — confirm they now *do* reach zellij. If the documented `"command": "unbound"` snippet needs adjusting to actually work on the real, current Windows Terminal version, update `docs/zellij-keybinding-fixes.md` with the working form.
8. Confirm `bin/omawsl theme not-a-real-name` prints a clear "unknown theme" error listing the valid names, and exits non-zero.
9. Report back what happened — including anything that didn't match this plan's assumptions (in the pattern of every prior phase's Task N: real runs have found real bugs stubbed tests couldn't catch in every phase so far). Once confirmed clean, update `docs/superpowers/plans/roadmap.md`'s Phase 5 entry to "DONE, merged to `master`" yourself (or ask the assistant to, once you've confirmed) — not before.
