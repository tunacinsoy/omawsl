#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# omawsl_install_terminal_apps
# Always-on terminal tooling, no picker gate. Installs via apt where a
# stable Ubuntu package exists across the whole supported floor (Ubuntu
# 24.04+, no ceiling - install/check-version.sh): fzf, ripgrep, bat, eza,
# zoxide, plocate, apache2-utils, fd-find, gh, btop, jq, bash-completion.
# `jq` is new in Phase 5 - `bin/omawsl theme` (design spec §11) needs it
# for the Windows Terminal settings.json edit. `bash-completion` is
# explicit rather than relying on it arriving as a transitive dependency
# of something else (confirmed present-but-unsourced on a real WSL2
# instance before this was added) - configs/bashrc sources it.
#
# fastfetch and lazygit used to be in this same apt list, "verified"
# against a real instance - but that instance was running Ubuntu 26.04
# (a dev/interim release used for testing), not the 24.04 floor this repo
# actually promises. Checked against Launchpad's published-sources
# history: fastfetch's Ubuntu universe package doesn't exist before 25.04,
# lazygit's doesn't exist before 25.10. On any floor-supported release
# older than that (24.04 LTS included - almost certainly the most common
# real one), `apt-get install` doesn't fail on just those two names: apt
# resolves the whole install line atomically, so an unresolvable package
# anywhere in the list aborts the entire command and silently takes fzf,
# ripgrep, bat, eza, zoxide, plocate, apache2-utils, fd-find, gh, btop,
# jq, and bash-completion down with it too. Both now install the same way
# as lazydocker/zellij below: straight from the upstream project's own
# GitHub release, independent of which Ubuntu release is running.
omawsl_install_terminal_apps() {
  sudo apt-get update -qq
  sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop jq bash-completion

  omawsl_install_lazydocker
  omawsl_install_zellij
  omawsl_install_lazygit
  omawsl_install_fastfetch
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

# omawsl_lazygit_arch
# Maps dpkg's architecture name to the naming lazygit's own release assets
# use - same idea as cloud-clis.sh's omawsl_aws_cli_arch.
omawsl_lazygit_arch() {
  case "$(dpkg --print-architecture)" in
    arm64) echo "arm64" ;;
    *) echo "x86_64" ;;
  esac
}

# omawsl_lazygit_install_steps
# lazygit's release asset filenames embed the version number (e.g.
# lazygit_0.63.1_linux_x86_64.tar.gz), unlike zellij's, so there's no
# fixed /releases/latest/download/<name> URL to hit directly - the
# version has to be resolved first, exactly like the two-step curl calls
# in lazygit's own README install instructions. No guard - same split
# rationale as omawsl_zellij_install_steps above.
omawsl_lazygit_install_steps() {
  local version
  version="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -Po '"tag_name": "v\K[^"]+')"
  local arch
  arch="$(omawsl_lazygit_arch)"
  curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_linux_${arch}.tar.gz" | tar -xz -C /tmp lazygit
  sudo install -m 0755 /tmp/lazygit /usr/local/bin/lazygit
  rm -f /tmp/lazygit
}

# omawsl_install_lazygit
# lazygit has no Ubuntu package on the 24.04-25.04 floor range (see the
# comment on omawsl_install_terminal_apps above) - installs the official
# prebuilt Linux binary release directly from GitHub instead, guarded the
# same way as omawsl_install_lazydocker/omawsl_install_zellij above.
omawsl_install_lazygit() {
  if command -v lazygit &>/dev/null; then
    return 0
  fi
  omawsl_lazygit_install_steps
}

# omawsl_fastfetch_arch
# Maps dpkg's architecture name to the naming fastfetch's own release
# assets use - same idea as omawsl_lazygit_arch above.
omawsl_fastfetch_arch() {
  case "$(dpkg --print-architecture)" in
    arm64) echo "aarch64" ;;
    *) echo "amd64" ;;
  esac
}

# omawsl_fastfetch_install_steps
# Unlike lazygit, fastfetch's own release asset filenames don't embed a
# version (fastfetch-linux-amd64.deb), so the fixed
# /releases/latest/download/<name> URL works directly, same as zellij's.
# Installed via the project's own .deb rather than a bare tar.gz binary:
# fastfetch links against system libraries (Wayland/X11/dbus/etc.) that a
# raw binary copy wouldn't pull in, whereas `apt install ./*.deb` resolves
# those Depends: from the regular Ubuntu archive same as any other
# package - preserving the dependency handling the old (broken) plain
# `apt-get install fastfetch` line relied on. No guard - same split
# rationale as omawsl_zellij_install_steps above.
omawsl_fastfetch_install_steps() {
  local arch
  arch="$(omawsl_fastfetch_arch)"
  local tmp_deb
  tmp_deb="$(mktemp --suffix=.deb)"
  curl -fsSL -o "$tmp_deb" "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${arch}.deb"
  sudo apt-get install -y "$tmp_deb"
  rm -f "$tmp_deb"
}

# omawsl_install_fastfetch
# fastfetch has no Ubuntu package on the 24.04-24.10 floor range (see the
# comment on omawsl_install_terminal_apps above) - installs the official
# .deb release directly from GitHub instead, guarded the same way as
# omawsl_install_lazydocker/omawsl_install_zellij above.
omawsl_install_fastfetch() {
  if command -v fastfetch &>/dev/null; then
    return 0
  fi
  omawsl_fastfetch_install_steps
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
