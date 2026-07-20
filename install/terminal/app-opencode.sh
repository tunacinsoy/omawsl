#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_opencode_install_steps
# The actual install command, no guard - called both by
# omawsl_install_opencode below (guarded) and by bin/omawsl update's
# orphan-tool apply phase (guard bypassed).
omawsl_opencode_install_steps() {
  curl -fsSL https://opencode.ai/install | bash
}

# omawsl_install_opencode
# opencode.ai's terminal AI coding agent CLI - purely WSL-side, no
# Windows dependency (design spec §10). Installs via its official
# installer, which places the binary at $HOME/.opencode/bin/opencode
# (configs/bashrc adds that directory to PATH). Idempotent via a
# command -v guard, since the installer itself always re-downloads
# unconditionally.
# Also checks the known install path directly: unlike ~/.local/bin (already
# on PATH via Ubuntu's own default ~/.profile before omawsl's bashrc ever
# runs), ~/.opencode/bin is ONLY added to PATH by configs/bashrc, which only
# takes effect in a fresh shell. Re-running install in the same shell that
# just installed opencode (PATH not yet refreshed) made command -v alone
# report a false negative and re-trigger a real reinstall - confirmed as a
# real bug, not just a theoretical one.
omawsl_install_opencode() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "opencode"; then
    return 0
  fi

  if command -v opencode &>/dev/null || [[ -x "$HOME/.opencode/bin/opencode" ]]; then
    return 0
  fi

  omawsl_opencode_install_steps
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_opencode
fi
