#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../lib.sh
source "$SCRIPT_DIR/../lib.sh"

# omawsl_install_codex_cli
# OpenAI Codex CLI - purely WSL-side, no Windows dependency (design spec
# §10). Its only distribution channel is npm (@openai/codex), so this
# uses a private mise-managed Node runtime to install it (`mise exec
# node@lts`), rather than depending on whether the user separately picked
# Node.js in the language picker - that picker is about the user's own
# project runtime, not an implementation detail of an unrelated tool
# (design spec §10). A thin wrapper at $HOME/.local/bin/codex (already on
# PATH) re-resolves through `mise exec` on every invocation, rather than
# relying on mise's shim mechanism to expose a binary from an ad-hoc
# `mise exec`-driven npm global install - deliberately explicit rather
# than assumed, after Phase 3 found a real bug in the analogous "does
# mise make this reachable automatically" assumption for Rails' gem.
# Idempotent via a command -v guard.
omawsl_install_codex_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Codex CLI"; then
    return 0
  fi

  if command -v codex &>/dev/null; then
    return 0
  fi

  mise exec node@lts -- npm install -g @openai/codex

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/codex" <<'WRAPPER'
#!/usr/bin/env bash
exec mise exec node@lts -- codex "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/codex"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_codex_cli
fi
