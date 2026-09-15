#!/usr/bin/env bash
set -euo pipefail

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failed=0

script="$(cd "$(dirname "$0")" && pwd)/install-hardening.sh"

# --- Strategy B containment -------------------------------------------
# omawsl_lazygit_release_url / omawsl_lazydocker_release_url are supposed
# to call curl against api.github.com to resolve the latest version tag.
# That's a real network request, so `curl` is replaced with a shell
# function for the whole life of this script before install-hardening.sh
# is ever sourced. Because everything below runs in THIS process (we
# `source` the learner's file directly and call its functions by name -
# no separate `bash install-hardening.sh ...` child process is ever
# spawned), a plain function definition is enough to shadow the real
# `curl` binary; `export -f` is added on top only so the stub also
# reaches any command-substitution subshell the learner's own
# implementation might use internally.
curl_log="$scratch/curl-calls.log"
: > "$curl_log"
export curl_log
curl() {
  {
    printf 'CALL'
    for arg in "$@"; do printf '\x1f%s' "$arg"; done
    printf '\n'
  } >> "$curl_log"
  # Canned GitHub Releases API response - same shape for every repo this
  # exercise looks up, since only the tag_name field is ever read.
  printf '{"tag_name": "v0.63.1", "name": "v0.63.1"}\n'
}
export -f curl

# shellcheck source=install-hardening.sh
source "$script"

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc - expected '$expected', got '$actual'"
    failed=1
  fi
}

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc - expected to find '$needle'"
    failed=1
  fi
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc - did not expect to find '$needle'"
    failed=1
  fi
}

# =========================================================================
# 1. omawsl_resolve_cmd_exe - fixed-path fallback for cmd.exe
# =========================================================================
# This check might itself be running on a real WSL2 box (where the real
# cmd.exe genuinely is on PATH, and the real fixed fallback path genuinely
# exists) or on an ordinary Linux box (neither is true). Every case below
# controls for that instead of assuming one or the other: `no_windows_path`
# is an otherwise-empty directory, so pointing PATH at it alone is enough
# to make `command -v cmd.exe` fail deterministically regardless of what
# machine this runs on - resolve_cmd_exe itself only uses shell builtins
# (`command -v`, `[[ ]]`, `echo`), so restricting PATH this far doesn't
# break anything it needs.

no_windows_path="$scratch/no-windows-path"
mkdir -p "$no_windows_path"

fake_cmd_exe="$scratch/cmd.exe"
printf '#!/usr/bin/env bash\n' > "$fake_cmd_exe"
chmod +x "$fake_cmd_exe"

result="$( (PATH="$no_windows_path"; OMAWSL_CMD_EXE_FALLBACK="$fake_cmd_exe" omawsl_resolve_cmd_exe 2>/dev/null) || echo '<error>')"
assert_eq "resolve_cmd_exe uses the fallback when it exists and is executable" \
  "$fake_cmd_exe" "$result"

result="$( (PATH="$no_windows_path"; OMAWSL_CMD_EXE_FALLBACK="$scratch/does-not-exist.exe" omawsl_resolve_cmd_exe 2>/dev/null) || echo '<error>')"
assert_eq "resolve_cmd_exe fails when the fallback path doesn't exist" \
  "<error>" "$result"

# No override at all: must fall back to the literal, hardcoded
# /mnt/c/Windows/System32/cmd.exe - computed independently here (a plain
# filesystem check, not a call into the learner's code) so this assertion
# is correct whether or not that path exists on the machine running it.
default_fallback="/mnt/c/Windows/System32/cmd.exe"
if [[ -x "$default_fallback" ]]; then
  expected_default_result="$default_fallback"
else
  expected_default_result="<error>"
fi
result="$( (unset OMAWSL_CMD_EXE_FALLBACK; PATH="$no_windows_path" omawsl_resolve_cmd_exe 2>/dev/null) || echo '<error>')"
assert_eq "resolve_cmd_exe falls back to the literal /mnt/c/Windows/System32/cmd.exe when no override is set" \
  "$expected_default_result" "$result"

# =========================================================================
# 2. omawsl_orphan_github_token / omawsl_orphan_github_auth_args
# =========================================================================
# "No token available" has to mean gh itself is unreachable/unauthenticated,
# not "PATH is empty" - the token/auth_args/release_url functions below
# still need real `grep`/`dpkg`/(stubbed) `curl` on PATH to do their own
# work. So a fake `gh` that always fails is PREPENDED onto the real PATH
# (shadowing only the name `gh`, same PATH-prepend technique as the curl
# stub above) rather than replacing PATH outright.

fakebin="$scratch/fakebin"
mkdir -p "$fakebin"
printf '#!/usr/bin/env bash\nexit 1\n' > "$fakebin/gh"
chmod +x "$fakebin/gh"
no_gh_path="$fakebin:$PATH"

result="$( (export GH_TOKEN="tok-gh" GITHUB_TOKEN="tok-github"; omawsl_orphan_github_token 2>/dev/null) || echo '<error>')"
assert_eq "github_token prefers \$GH_TOKEN over \$GITHUB_TOKEN" "tok-gh" "$result"

result="$( (unset GH_TOKEN; export GITHUB_TOKEN="tok-github"; omawsl_orphan_github_token 2>/dev/null) || echo '<error>')"
assert_eq "github_token falls back to \$GITHUB_TOKEN when \$GH_TOKEN is unset" "tok-github" "$result"

result="$( (unset GH_TOKEN GITHUB_TOKEN; PATH="$no_gh_path" omawsl_orphan_github_token 2>/dev/null) || echo '<error>')"
assert_eq "github_token is empty when no env var is set and gh has no token" "" "$result"

result="$( (export GH_TOKEN="tok-gh"; omawsl_orphan_github_auth_args 2>/dev/null) || echo '<error>')"
assert_contains "auth_args includes -H when a token is available" "$result" "-H"
assert_contains "auth_args includes the correct Bearer header" "$result" "Authorization: Bearer tok-gh"

result="$( (unset GH_TOKEN GITHUB_TOKEN; PATH="$no_gh_path" omawsl_orphan_github_auth_args 2>/dev/null) || echo '<error>')"
assert_eq "auth_args is empty when no token is available" "" "$result"

# =========================================================================
# 3. Per-tool architecture mapping (real, harmless `dpkg --print-architecture`)
# =========================================================================

raw_arch="$(dpkg --print-architecture)"
case "$raw_arch" in
  arm64)
    expected_lazygit_arch="arm64"
    expected_lazydocker_arch="arm64"
    expected_fastfetch_arch="aarch64"
    ;;
  *)
    expected_lazygit_arch="x86_64"
    expected_lazydocker_arch="x86_64"
    expected_fastfetch_arch="amd64"
    ;;
esac

result="$(omawsl_lazygit_arch 2>/dev/null || echo '<error>')"
assert_eq "lazygit_arch maps dpkg '$raw_arch' correctly" "$expected_lazygit_arch" "$result"

result="$(omawsl_lazydocker_arch 2>/dev/null || echo '<error>')"
assert_eq "lazydocker_arch maps dpkg '$raw_arch' correctly" "$expected_lazydocker_arch" "$result"

result="$(omawsl_fastfetch_arch 2>/dev/null || echo '<error>')"
assert_eq "fastfetch_arch maps dpkg '$raw_arch' correctly" "$expected_fastfetch_arch" "$result"

# =========================================================================
# 4. omawsl_lazygit_release_url / omawsl_lazydocker_release_url
#    (authenticated: GH_TOKEN set)
# =========================================================================

: > "$curl_log"
result="$( (export GH_TOKEN="tok-gh"; omawsl_lazygit_release_url 2>/dev/null) || echo '<error>')"
expected="https://github.com/jesseduffield/lazygit/releases/download/v0.63.1/lazygit_0.63.1_linux_${expected_lazygit_arch}.tar.gz"
assert_eq "lazygit_release_url builds the correct download URL" "$expected" "$result"

log_contents="$(cat "$curl_log" 2>/dev/null || echo '')"
assert_contains "lazygit_release_url queries the lazygit releases/latest API" \
  "$log_contents" "https://api.github.com/repos/jesseduffield/lazygit/releases/latest"
assert_contains "lazygit_release_url sends the token as an Authorization: Bearer header" \
  "$log_contents" "Authorization: Bearer tok-gh"

: > "$curl_log"
result="$( (export GH_TOKEN="tok-gh"; omawsl_lazydocker_release_url 2>/dev/null) || echo '<error>')"
expected="https://github.com/jesseduffield/lazydocker/releases/download/v0.63.1/lazydocker_0.63.1_Linux_${expected_lazydocker_arch}.tar.gz"
assert_eq "lazydocker_release_url builds the correct download URL (note capitalized 'Linux')" "$expected" "$result"

log_contents="$(cat "$curl_log" 2>/dev/null || echo '')"
assert_contains "lazydocker_release_url queries the lazydocker releases/latest API" \
  "$log_contents" "https://api.github.com/repos/jesseduffield/lazydocker/releases/latest"
assert_contains "lazydocker_release_url sends the token as an Authorization: Bearer header" \
  "$log_contents" "Authorization: Bearer tok-gh"

# =========================================================================
# 5. Same lookup, unauthenticated fallback (no token anywhere reachable)
# =========================================================================

: > "$curl_log"
result="$( (unset GH_TOKEN GITHUB_TOKEN; PATH="$no_gh_path" omawsl_lazygit_release_url 2>/dev/null) || echo '<error>')"
expected="https://github.com/jesseduffield/lazygit/releases/download/v0.63.1/lazygit_0.63.1_linux_${expected_lazygit_arch}.tar.gz"
assert_eq "lazygit_release_url still resolves correctly with no token available" "$expected" "$result"

log_contents="$(cat "$curl_log" 2>/dev/null || echo '')"
assert_not_contains "lazygit_release_url sends no Authorization header when no token is available" \
  "$log_contents" "Authorization:"

# =========================================================================
# 6. omawsl_fastfetch_release_url - no version in the filename, no API call
# =========================================================================

result="$(omawsl_fastfetch_release_url 2>/dev/null || echo '<error>')"
expected="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${expected_fastfetch_arch}.deb"
assert_eq "fastfetch_release_url builds the correct fixed-latest download URL" "$expected" "$result"

exit "$failed"
