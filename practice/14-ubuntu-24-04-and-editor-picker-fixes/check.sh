#!/usr/bin/env bash
set -euo pipefail

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failed=0

dir="$(cd "$(dirname "$0")" && pwd)"
opencode_script="$dir/app-opencode.sh"
copilot_script="$dir/app-gh-copilot.sh"
gum_script="$dir/app-gum.sh"
editors_script="$dir/editor-options.sh"

# A PATH with nothing real on it - so "is this command already installed?"
# checks below are deterministic, regardless of what happens to be
# installed on the machine actually running this check.
empty_path="$scratch/emptybin"
mkdir -p "$empty_path"

# shellcheck source=/dev/null
source "$opencode_script"
# shellcheck source=/dev/null
source "$copilot_script"
# shellcheck source=/dev/null
source "$gum_script"
# shellcheck source=/dev/null
source "$editors_script"

# ---------------------------------------------------------------------------
# 1. opencode: PATH-timing false negative
# ---------------------------------------------------------------------------

# Case A: opencode already resolvable on PATH -> must not reinstall.
fakebin="$scratch/fakebin-opencode"
mkdir -p "$fakebin"
printf '#!/usr/bin/env bash\n' > "$fakebin/opencode"
chmod +x "$fakebin/opencode"
log="$scratch/opencode-a.log"
home_a="$scratch/home-a"
mkdir -p "$home_a"
if ( export OMAWSL_TEST_LOG="$log" HOME="$home_a" PATH="$fakebin:$empty_path" OMAWSL_EDITORS=""
     omawsl_install_opencode ) > /dev/null 2>&1; then
  if ! grep -q "install_steps called" "$log" 2>/dev/null; then
    echo "PASS: opencode already on PATH -> no reinstall"
  else
    echo "FAIL: opencode already on PATH, but install steps ran anyway"
    failed=1
  fi
else
  echo "FAIL: omawsl_install_opencode errored (already-on-PATH case) - check for a syntax/runtime error, or that the function exists"
  failed=1
fi

# Case B (the real bug): NOT on PATH, but the binary already sits at
# $HOME/.opencode/bin/opencode - the exact false-negative scenario the fix
# addresses. Must still not reinstall.
log="$scratch/opencode-b.log"
home_b="$scratch/home-b"
mkdir -p "$home_b/.opencode/bin"
printf '#!/usr/bin/env bash\n' > "$home_b/.opencode/bin/opencode"
chmod +x "$home_b/.opencode/bin/opencode"
if ( export OMAWSL_TEST_LOG="$log" HOME="$home_b" PATH="$empty_path"
     omawsl_install_opencode ) > /dev/null 2>&1; then
  if ! grep -q "install_steps called" "$log" 2>/dev/null; then
    echo "PASS: opencode installed but not yet on PATH -> no reinstall (the actual bug this fixes)"
  else
    echo "FAIL: opencode installed at \$HOME/.opencode/bin/opencode but not on PATH -> install steps ran anyway (PATH-timing false negative not fixed)"
    failed=1
  fi
else
  echo "FAIL: omawsl_install_opencode errored (installed-but-not-on-PATH case)"
  failed=1
fi

# Case C: genuinely not installed anywhere -> must install.
log="$scratch/opencode-c.log"
home_c="$scratch/home-c"
mkdir -p "$home_c"
if ( export OMAWSL_TEST_LOG="$log" HOME="$home_c" PATH="$empty_path"
     omawsl_install_opencode ) > /dev/null 2>&1; then
  if grep -q "install_steps called" "$log" 2>/dev/null; then
    echo "PASS: opencode not installed anywhere -> installs"
  else
    echo "FAIL: opencode not installed anywhere, but install steps never ran"
    failed=1
  fi
else
  echo "FAIL: omawsl_install_opencode errored (not-installed case)"
  failed=1
fi

# ---------------------------------------------------------------------------
# 2. GitHub Copilot CLI: idempotency check must match the real binary name
# ---------------------------------------------------------------------------

# Case A: `copilot` already resolvable on PATH -> must not reinstall.
fakebin="$scratch/fakebin-copilot"
mkdir -p "$fakebin"
printf '#!/usr/bin/env bash\n' > "$fakebin/copilot"
chmod +x "$fakebin/copilot"
log="$scratch/copilot-a.log"
if ( export OMAWSL_TEST_LOG="$log" PATH="$fakebin:$empty_path"
     omawsl_install_gh_copilot ) > /dev/null 2>&1; then
  if ! grep -q "install_steps called" "$log" 2>/dev/null; then
    echo "PASS: copilot already on PATH -> no reinstall"
  else
    echo "FAIL: copilot already on PATH, but install steps ran anyway"
    failed=1
  fi
else
  echo "FAIL: omawsl_install_gh_copilot errored (already-installed case) - check for a syntax/runtime error, or that the function exists"
  failed=1
fi

# Case B: not installed at all -> must install. A guard that still checked
# for the old `gh extension` shape (rather than `command -v copilot`) would
# wrongly reinstall forever OR never detect a real install - either way,
# this and the case above are what distinguish a correct guard.
log="$scratch/copilot-b.log"
if ( export OMAWSL_TEST_LOG="$log" PATH="$empty_path"
     omawsl_install_gh_copilot ) > /dev/null 2>&1; then
  if grep -q "install_steps called" "$log" 2>/dev/null; then
    echo "PASS: copilot not installed -> installs"
  else
    echo "FAIL: copilot not installed, but install steps never ran"
    failed=1
  fi
else
  echo "FAIL: omawsl_install_gh_copilot errored (not-installed case)"
  failed=1
fi

# ---------------------------------------------------------------------------
# 3. Editor picker: Antigravity CLI replaces Gemini CLI
# ---------------------------------------------------------------------------

options="$(omawsl_editor_picker_options 2>/dev/null || echo '<error>')"

if [[ "$options" == *"Antigravity CLI"* ]]; then
  echo "PASS: picker options include Antigravity CLI"
else
  echo "FAIL: picker options do not include Antigravity CLI"
  failed=1
fi

if [[ "$options" != *"Gemini CLI"* ]]; then
  echo "PASS: picker options no longer include Gemini CLI"
else
  echo "FAIL: picker options still include Gemini CLI"
  failed=1
fi

# ---------------------------------------------------------------------------
# 4. gum: install from Charm's own apt repo, never the real apt-get/curl/gpg
# ---------------------------------------------------------------------------
# `sudo` and `curl` are intercepted via a fake executable placed earlier on
# $PATH than the real ones (see check-generation.md: stubbing `sudo` itself
# is required here - a stub of the inner command like `apt-get` is never
# consulted for a `sudo apt-get ...` call, since sudo execs the real target
# binary directly). Nothing here ever touches the real system's apt
# sources, GPG keyring, or package state.

fakebin="$scratch/fakebin-gum"
mkdir -p "$fakebin"

sudo_log="$scratch/sudo.log"
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\nexit 0\n' "$sudo_log" > "$fakebin/sudo"
chmod +x "$fakebin/sudo"

curl_log="$scratch/curl.log"
printf '#!/usr/bin/env bash\necho "$*" >> "%s"\necho "fake-gpg-key-data"\nexit 0\n' "$curl_log" > "$fakebin/curl"
chmod +x "$fakebin/curl"

# Case A: sources file doesn't exist yet -> adds the repo, then installs.
sources_file="$scratch/charm-a.list"
keyrings_dir="$scratch/keyrings-a"
: > "$sudo_log"
: > "$curl_log"
if ( PATH="$fakebin:$PATH" omawsl_install_gum "$sources_file" "$keyrings_dir" ) > /dev/null 2>&1; then
  ok=1
  grep -q -- "-d $keyrings_dir" "$sudo_log" 2>/dev/null || ok=0
  grep -q "gpg.key" "$curl_log" 2>/dev/null || ok=0
  grep -q "dearmor" "$sudo_log" 2>/dev/null || ok=0
  grep -q "$sources_file" "$sudo_log" 2>/dev/null || ok=0
  grep -q "apt-get update -qq" "$sudo_log" 2>/dev/null || ok=0
  grep -q "apt-get install -y gum" "$sudo_log" 2>/dev/null || ok=0
  if [[ "$ok" -eq 1 ]]; then
    echo "PASS: sources file missing -> adds Charm's apt repo (keyring + GPG key + sources line) and installs gum"
  else
    echo "FAIL: sources file missing, but the repo-add steps (or the install itself) didn't happen as expected - see $sudo_log / $curl_log"
    failed=1
  fi
else
  echo "FAIL: omawsl_install_gum errored (sources-file-missing case) - check for a syntax/runtime error, or that the function exists"
  failed=1
fi

# Case B: sources file already exists -> skips the repo-add, still installs.
sources_file="$scratch/charm-b.list"
keyrings_dir="$scratch/keyrings-b"
: > "$sources_file"
: > "$sudo_log"
: > "$curl_log"
if ( PATH="$fakebin:$PATH" omawsl_install_gum "$sources_file" "$keyrings_dir" ) > /dev/null 2>&1; then
  ok=1
  [[ ! -s "$curl_log" ]] || ok=0
  grep -q "dearmor" "$sudo_log" 2>/dev/null && ok=0
  grep -q "apt-get install -y gum" "$sudo_log" 2>/dev/null || ok=0
  if [[ "$ok" -eq 1 ]]; then
    echo "PASS: sources file already present -> skips the repo-add, still installs gum"
  else
    echo "FAIL: sources file already present, but the repo-add ran again (or gum wasn't installed) - see $sudo_log / $curl_log"
    failed=1
  fi
else
  echo "FAIL: omawsl_install_gum errored (sources-file-present case)"
  failed=1
fi

exit "$failed"
