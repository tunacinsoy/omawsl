#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_gemini_cli
# Same shape as app-codex-cli.sh: Gemini CLI's only distribution channel
# is npm (@google/gemini-cli), so this uses a private mise-managed Node
# runtime plus an explicit $HOME/.local/bin/gemini wrapper (see
# app-codex-cli.sh's comment for why the wrapper, not a bare mise shim).
omawsl_install_gemini_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Gemini CLI"; then
    return 0
  fi

  if command -v gemini &>/dev/null; then
    return 0
  fi

  mise exec node@lts -- npm install -g @google/gemini-cli

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/gemini" <<'WRAPPER'
#!/usr/bin/env bash
exec mise exec node@lts -- gemini "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/gemini"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_gemini_cli
fi
