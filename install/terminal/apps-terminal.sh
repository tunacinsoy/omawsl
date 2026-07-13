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
  omawsl_install_cli
}

# omawsl_lazydocker_install_steps
# The actual install command, no guard - called both by
# omawsl_install_lazydocker below (guarded, unchanged behavior) and by
# bin/omawsl update's orphan-tool apply phase (guard bypassed, so an
# already-installed lazydocker gets a genuine fresh install rather than
# a no-op).
omawsl_lazydocker_install_steps() {
  curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
}

# omawsl_install_lazydocker
# No Ubuntu package exists for lazydocker - installs via its official
# script (jesseduffield/lazydocker), which installs to $HOME/.local/bin
# by default (already on PATH via configs/bashrc). The script itself
# always re-downloads/reinstalls unconditionally - this command -v guard
# is what actually makes THIS entry point idempotent.
omawsl_install_lazydocker() {
  if command -v lazydocker &>/dev/null; then
    return 0
  fi
  omawsl_lazydocker_install_steps
}

# omawsl_zellij_install_steps
# The actual install command, no guard - same split rationale as
# omawsl_lazydocker_install_steps above.
omawsl_zellij_install_steps() {
  local arch
  arch="$(uname -m)"
  curl -fsSL "https://github.com/zellij-org/zellij/releases/latest/download/zellij-${arch}-unknown-linux-musl.tar.gz" | tar -xz -C /tmp
  sudo install -m 0755 /tmp/zellij /usr/local/bin/zellij
  rm -f /tmp/zellij
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
  omawsl_zellij_install_steps
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_terminal_apps
fi
