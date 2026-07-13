#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_codex_cli_install_steps
# The actual install + wrapper-write commands, no guard - called both by
# omawsl_install_codex_cli below (guarded) and by bin/omawsl update's
# orphan-tool apply phase (guard bypassed). Re-running this always
# re-installs the npm package at whatever version @openai/codex currently
# resolves to and rewrites the wrapper unconditionally (cheap, and keeps
# it in sync if this file's own wrapper contents ever change).
omawsl_codex_cli_install_steps() {
  mise exec node@lts -- npm install -g @openai/codex

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/codex" <<'WRAPPER'
#!/usr/bin/env bash
exec mise exec node@lts -- codex "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/codex"
}

# omawsl_install_codex_cli
# OpenAI Codex CLI - purely WSL-side, no Windows dependency (design spec
# §10). Its only distribution channel is npm (@openai/codex), so this
# uses a private mise-managed Node runtime to install it (`mise exec
# node@lts`), rather than depending on whether the user separately picked
# Node.js in the language picker - that picker is about the user's own
# project runtime, not an implementation detail of an unrelated tool
# (design spec §10). Idempotent via a command -v guard.
omawsl_install_codex_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Codex CLI"; then
    return 0
  fi

  if command -v codex &>/dev/null; then
    return 0
  fi

  omawsl_codex_cli_install_steps
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_codex_cli
fi
