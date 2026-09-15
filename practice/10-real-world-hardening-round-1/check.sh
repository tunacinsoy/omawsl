#!/usr/bin/env bash
set -euo pipefail

# Side effects: none — every assertion below either sources a pure
# function (lib.sh has no unconditional dispatcher, so sourcing is
# safe) or invokes mini-boot.sh through its real entry point (it DOES
# have an unconditional dispatcher, by design — see the lesson — so it
# is never sourced here, only ever run as a child process). Any file
# writes exercised below (omawsl_atomic_replace) target an explicit
# scratch directory passed in as an argument, never the learner's
# practice/ directory or a relative/cwd-derived path.

here="$(cd "$(dirname "$0")" && pwd)"
lib="$here/lib.sh"
boot="$here/mini-boot.sh"

failed=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

# ---------------------------------------------------------------------
# omawsl_docker_reachable (sourced directly — pure function, no
# dispatcher, no writes)
# ---------------------------------------------------------------------

source "$lib"

fakebin="$(mktemp -d)"
trap 'rm -rf "$fakebin"' EXIT

# A shim that's on PATH and satisfies `command -v` but isn't actually
# functional — exactly the Docker Desktop non-integrated-shim scenario
# the real bug hit.
cat > "$fakebin/docker" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == "info" ]]; then
  echo "unable to reach the daemon - enable WSL integration" >&2
  exit 1
fi
exit 0
SH
chmod +x "$fakebin/docker"

if ! (PATH="$fakebin:$PATH" omawsl_docker_reachable); then
  pass "omawsl_docker_reachable returns false for a docker shim that's on PATH but not functional"
else
  fail "omawsl_docker_reachable returned true for a docker shim that's on PATH but 'docker info' fails (the false-positive bug is back)"
fi

# A shim that's fully functional.
cat > "$fakebin/docker" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$fakebin/docker"

if (PATH="$fakebin:$PATH" omawsl_docker_reachable); then
  pass "omawsl_docker_reachable returns true for a genuinely working docker"
else
  fail "omawsl_docker_reachable returned false for a genuinely working docker"
fi

# No docker on PATH at all.
if ! (PATH="/nonexistent" omawsl_docker_reachable); then
  pass "omawsl_docker_reachable returns false when docker isn't on PATH at all"
else
  fail "omawsl_docker_reachable returned true when docker isn't on PATH at all"
fi

# ---------------------------------------------------------------------
# omawsl_atomic_replace (sourced directly — pure function, no
# dispatcher; writes target an explicit scratch dir passed as an arg)
# ---------------------------------------------------------------------

scratch="$(mktemp -d)"
trap 'rm -rf "$fakebin" "$scratch"' EXIT

printf 'hello world' > "$scratch/tmp.txt"

if (omawsl_atomic_replace "$scratch/tmp.txt" "$scratch/dest.txt" 2>/dev/null); then
  pass "omawsl_atomic_replace ran without error"
else
  fail "omawsl_atomic_replace raised an error — check the implementation for a syntax or runtime error"
fi

dest_content="$(cat "$scratch/dest.txt" 2>/dev/null || echo '<missing>')"
if [[ "$dest_content" == "hello world" ]]; then
  pass "omawsl_atomic_replace: dest_path ends up with tmp_path's exact content"
else
  fail "omawsl_atomic_replace: dest_path was '$dest_content', expected 'hello world'"
fi

if [[ ! -e "$scratch/tmp.txt" ]]; then
  pass "omawsl_atomic_replace: tmp_path no longer exists afterward"
else
  fail "omawsl_atomic_replace: tmp_path still exists after the call"
fi

# ---------------------------------------------------------------------
# mini-boot.sh (real entry point — has an unconditional dispatcher by
# design, so it is invoked as a child process, never sourced)
# ---------------------------------------------------------------------

# 1. The crash bug: piping the script's own text into bash (the exact
#    shape of the real `curl -fsSL ... | bash` one-liner) must not
#    crash, and must still reach the "install" step when confirmation
#    is assumed.
piped_output="$(OMAWSL_ASSUME_YES=1 bash -c "cat '$boot' | bash" 2>&1 || true)"
if [[ "$piped_output" == *"INSTALL_RAN"* && "$piped_output" != *"unbound variable"* ]]; then
  pass "mini-boot.sh runs correctly when piped into bash via stdin, the same way curl | bash invokes it"
else
  fail "mini-boot.sh failed when piped into bash via stdin (output was: $piped_output)"
fi

# 2. The confirmation bug: stdin containing "y" must NOT be accepted as
#    the answer — only a real controlling terminal (or
#    OMAWSL_ASSUME_YES) counts. setsid detaches the child from any
#    controlling terminal, so a correct implementation's /dev/tty read
#    fails safely and falls through to "Aborted.", proving piped stdin
#    was ignored rather than misread as "yes". Bounded by `timeout` in
#    case a broken implementation blocks waiting for input instead of
#    failing fast.
declined_output="$(timeout 5 setsid bash -c "echo y | bash '$boot'" 2>&1 || true)"
if [[ "$declined_output" == *"Aborted."* && "$declined_output" != *"INSTALL_RAN"* ]]; then
  pass "mini-boot.sh does not accept a confirmation from piped stdin — only a real terminal or OMAWSL_ASSUME_YES counts"
else
  fail "mini-boot.sh accepted piped stdin ('y') as the confirmation answer, or hung/crashed instead of aborting (output was: $declined_output)"
fi

# 3. No controlling terminal available at all (and no
#    OMAWSL_ASSUME_YES): must abort gracefully, not hang or crash.
no_tty_output="$(timeout 5 setsid bash -c "bash '$boot' < /dev/null" 2>&1 || true)"
if [[ "$no_tty_output" == *"Aborted."* ]]; then
  pass "mini-boot.sh aborts gracefully (not a hang or crash) when no controlling terminal is available at all"
else
  fail "mini-boot.sh did not abort cleanly with no controlling terminal available (output was: $no_tty_output)"
fi

exit "$failed"
