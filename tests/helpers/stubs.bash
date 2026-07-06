#!/usr/bin/env bash
# Shared bats test helpers: command stubbing + a canned-response queue for
# the `gum` stub used across multiple test files.

STUB_LOG=""
export STUB_LOG

stub_init() {
  STUB_LOG="$(mktemp)"
}

stub_calls() {
  cat "$STUB_LOG"
}

# stub_command <name> [exit_code]
# Defines and exports a bash function named <name> that appends its
# invocation to STUB_LOG and returns exit_code (default 0), instead of
# running the real command. export -f makes it visible to child bash
# processes too (e.g. `run bash script.sh` in bats).
stub_command() {
  local name="$1" exit_code="${2:-0}"
  eval "
${name}() {
  echo \"${name} \$*\" >> \"\$STUB_LOG\"
  return ${exit_code}
}
export -f ${name}
"
}

# --- gum response queue -----------------------------------------------
# gum_stub_init must run before gum_stub_respond / using the gum stub.
# gum_stub_respond "line1
# line2" queues one gum-choose response (real newlines = multiple picked
# items for a multi-select, matching what `gum choose --no-limit` actually
# emits: one selection per line). Responses are returned in the order
# queued, one per call to `gum`.

GUM_RESPONSE_DIR=""
export GUM_RESPONSE_DIR

gum_stub_init() {
  GUM_RESPONSE_DIR="$(mktemp -d)"
  echo 0 > "$GUM_RESPONSE_DIR/.next"
  echo 0 > "$GUM_RESPONSE_DIR/.call"
}

gum_stub_respond() {
  local n; n="$(cat "$GUM_RESPONSE_DIR/.next")"
  printf '%s' "$1" > "$GUM_RESPONSE_DIR/response-$n"
  echo $((n + 1)) > "$GUM_RESPONSE_DIR/.next"
}

gum() {
  echo "gum $*" >> "$STUB_LOG"
  local n; n="$(cat "$GUM_RESPONSE_DIR/.call")"
  echo $((n + 1)) > "$GUM_RESPONSE_DIR/.call"
  cat "$GUM_RESPONSE_DIR/response-$n" 2>/dev/null || true
}
export -f gum
