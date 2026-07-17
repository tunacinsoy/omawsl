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

# stub_hide_command <name> [<name> ...]
# Exports a PATH pointing at a fresh directory of symlinks to every real
# binary from the standard system directories, except the given name(s) -
# which are simply never linked in, so `command -v <name>` genuinely fails
# regardless of whether that command happens to be really installed
# somewhere on this host. More robust than excluding whole directories
# (which would also hide bash/coreutils living in the same /usr/bin,
# /bin) or a fixed "safe" directory list (which breaks the moment the
# excluded command gets installed to a new location - happened twice
# already: Docker Desktop's /mnt/c/... interop, then a real native
# docker-ce install; the same risk applies to any tool a test needs to
# simulate as "not installed", e.g. terraform/az after a real Task 6 run).
stub_hide_command() {
  local hide_names=("$@")
  local shadow_dir; shadow_dir="$(mktemp -d)"
  local sysdir hide
  for sysdir in /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin /usr/games /usr/local/games /usr/lib/wsl/lib; do
    [[ -d "$sysdir" ]] || continue
    # One `ln` invocation per directory (target-directory mode) instead of
    # one per file: forking `ln` per file - thousands of forks on a real
    # dev machine (/usr/bin alone can hold 1000+ entries) - made this
    # helper, which runs in `setup()` for every single test across the
    # whole suite, the dominant cost of a full bats run (multiple minutes
    # for what should be a sub-second stub setup). A later sysdir's file
    # of the same name fails silently (2>/dev/null) since the earlier
    # symlink already exists, preserving the original first-sysdir-wins
    # precedence.
    ln -s -t "$shadow_dir" "$sysdir"/* 2>/dev/null || true
  done
  for hide in "${hide_names[@]}"; do
    rm -f "$shadow_dir/$hide"
  done
  export PATH="$shadow_dir"
}
