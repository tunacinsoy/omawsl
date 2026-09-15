#!/usr/bin/env bash
set -euo pipefail

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failed=0

# Resolve the learner's script to an absolute path before any cd below.
script="$(cd "$(dirname "$0")" && pwd)/starship.sh"

# --- containment for the dangerous half: omawsl_starship_install_steps ---
# It performs a real network download (curl) and a real install outside
# $HOME (sudo install ... /usr/local/bin/starship). A HOME override gives
# zero containment for either — /usr/local/bin isn't under $HOME, and a
# network call isn't a path at all — so curl/sudo/tar are shadowed with
# logging stubs instead (check-generation.md Technique 2). These are
# plain function definitions, not `export -f`: every invocation below
# runs inside a `( ... )` subshell, which is a fork of this already-
# running process and so inherits this shell's function table directly.
# `export -f` only matters when crossing into a genuinely separate
# process (e.g. `bash -c '...'` or `bash somefile.sh`), which nothing
# here does.
call_log="$scratch/calls.log"
curl() { echo "curl $*" >> "$call_log"; }
sudo() { echo "sudo $*" >> "$call_log"; }
tar()  { echo "tar $*" >> "$call_log"; cat >/dev/null 2>&1 || true; }

# --- omawsl_starship_asset (pure — no side effects, but still run inside
# the same cd+HOME-contained subshell as everything else, for uniformity
# with the rest of this Strategy B check) -----------------------------
result="$( ( uname() { echo x86_64; }; cd "$scratch" && HOME="$scratch" && source "$script" && omawsl_starship_asset ) 2>/dev/null || echo '<error>')"
if [[ "$result" == "starship-x86_64-unknown-linux-gnu.tar.gz" ]]; then
  echo "PASS: omawsl_starship_asset picks the gnu build for x86_64"
else
  echo "FAIL: omawsl_starship_asset (x86_64) returned '$result', expected starship-x86_64-unknown-linux-gnu.tar.gz"
  failed=1
fi

result="$( ( uname() { echo aarch64; }; cd "$scratch" && HOME="$scratch" && source "$script" && omawsl_starship_asset ) 2>/dev/null || echo '<error>')"
if [[ "$result" == "starship-aarch64-unknown-linux-musl.tar.gz" ]]; then
  echo "PASS: omawsl_starship_asset picks the musl build for aarch64"
else
  echo "FAIL: omawsl_starship_asset (aarch64) returned '$result', expected starship-aarch64-unknown-linux-musl.tar.gz"
  failed=1
fi

# --- omawsl_starship_install_steps ------------------------------------
: > "$call_log"
( cd "$scratch" && HOME="$scratch" && source "$script" && omawsl_starship_install_steps ) >/dev/null 2>&1 || true
calls="$(cat "$call_log" 2>/dev/null || true)"

if [[ "$calls" == *"curl"* && "$calls" == *"starship"* && "$calls" == *"github.com/starship/starship"* ]]; then
  echo "PASS: omawsl_starship_install_steps downloads a starship release from GitHub via curl"
else
  echo "FAIL: omawsl_starship_install_steps never called curl against a starship GitHub release URL"
  failed=1
fi

if [[ "$calls" == *"sudo"* && "$calls" == *"/usr/local/bin/starship"* ]]; then
  echo "PASS: omawsl_starship_install_steps installs the binary to /usr/local/bin/starship via sudo"
else
  echo "FAIL: omawsl_starship_install_steps never used sudo to install to /usr/local/bin/starship"
  failed=1
fi

# --- omawsl_write_starship_theme --------------------------------------
( cd "$scratch" && HOME="$scratch" && source "$script" && omawsl_write_starship_theme tokyo-night \
    "#F93357" "#9ECE6A" "#7AA2F7" "#E0AF68" "#BB9AF7" "#FF9E64" "#2AC3DE" "#383E5A" "#C0CAF5" "#1A1B26" "#A9B1D6" \
) >/dev/null 2>&1 || true

toml="$scratch/.config/starship.toml"

if [[ -f "$toml" ]]; then
  echo "PASS: omawsl_write_starship_theme created ~/.config/starship.toml"
else
  echo "FAIL: ~/.config/starship.toml was not created"
  failed=1
fi

if [[ -f "$toml" ]] && grep -qE '^[[:space:]]*palette[[:space:]]*=[[:space:]]*"tokyo-night"' "$toml"; then
  echo "PASS: starship.toml selects the tokyo-night palette"
else
  echo "FAIL: starship.toml doesn't contain palette = \"tokyo-night\""
  failed=1
fi

if [[ -f "$toml" ]] && grep -qE '^[[:space:]]*\[palettes\.tokyo-night\]' "$toml"; then
  echo "PASS: starship.toml defines a [palettes.tokyo-night] section"
else
  echo "FAIL: starship.toml has no [palettes.tokyo-night] section"
  failed=1
fi

if [[ -f "$toml" ]] \
  && grep -qE 'red[[:space:]]*=[[:space:]]*"#F93357"' "$toml" \
  && grep -qE 'green[[:space:]]*=[[:space:]]*"#9ECE6A"' "$toml" \
  && grep -qE 'blue[[:space:]]*=[[:space:]]*"#7AA2F7"' "$toml"; then
  echo "PASS: starship.toml remaps red/green/blue to tokyo-night's own hex values"
else
  echo "FAIL: starship.toml is missing one or more of the recolored red/green/blue values"
  failed=1
fi

# A second, different theme must overwrite the first unconditionally —
# same as omawsl theme <name>'s always-overwrite behavior on a real
# machine (an explicit user action, not a passive install-time default).
( cd "$scratch" && HOME="$scratch" && source "$script" && omawsl_write_starship_theme rose-pine \
    "#b4637a" "#286983" "#56949f" "#ea9d34" "#907aa9" "#fe640b" "#d7827e" "#f2e9e1" "#575279" "#faf4ed" "#575279" \
) >/dev/null 2>&1 || true

if [[ -f "$toml" ]] \
  && grep -qE '^[[:space:]]*palette[[:space:]]*=[[:space:]]*"rose-pine"' "$toml" \
  && ! grep -qE '^[[:space:]]*palette[[:space:]]*=[[:space:]]*"tokyo-night"' "$toml"; then
  echo "PASS: a second call to omawsl_write_starship_theme overwrites the previous theme unconditionally"
else
  echo "FAIL: starship.toml still shows tokyo-night after writing the rose-pine theme over it"
  failed=1
fi

# --- omawsl_ensure_starship_bashrc_line -------------------------------
printf '# .bashrc\nsome earlier line\neval "$(mise activate bash)"\nsome later line\n' > "$scratch/.bashrc"

( cd "$scratch" && HOME="$scratch" && source "$script" && omawsl_ensure_starship_bashrc_line ) >/dev/null 2>&1 || true

bashrc="$scratch/.bashrc"
mise_line="$(grep -n 'mise activate bash' "$bashrc" 2>/dev/null | head -n1 | cut -d: -f1 || true)"
starship_line="$(grep -n 'starship init bash' "$bashrc" 2>/dev/null | head -n1 | cut -d: -f1 || true)"

if [[ -n "$starship_line" ]]; then
  echo "PASS: omawsl_ensure_starship_bashrc_line added a starship init line to ~/.bashrc"
else
  echo "FAIL: ~/.bashrc has no 'starship init bash' line after calling omawsl_ensure_starship_bashrc_line"
  failed=1
fi

if [[ -n "$mise_line" && -n "$starship_line" && "$starship_line" -gt "$mise_line" ]]; then
  echo "PASS: the starship init line comes after the mise activation line"
else
  echo "FAIL: the starship init line is not positioned after 'eval \"\$(mise activate bash)\"' (mise line: ${mise_line:-none}, starship line: ${starship_line:-none})"
  failed=1
fi

# Idempotency: running it again on an already-patched bashrc must not
# duplicate the line.
( cd "$scratch" && HOME="$scratch" && source "$script" && omawsl_ensure_starship_bashrc_line ) >/dev/null 2>&1 || true
count="$(grep -c 'starship init bash' "$bashrc" 2>/dev/null || true)"
if [[ "${count:-0}" -eq 1 ]]; then
  echo "PASS: calling omawsl_ensure_starship_bashrc_line twice doesn't duplicate the starship line"
else
  echo "FAIL: expected exactly 1 'starship init bash' line after two calls, found ${count:-0}"
  failed=1
fi

# No mise line at all to anchor after — must still succeed, not crash.
rm -f "$scratch/.bashrc"
printf '# .bashrc\nsome unrelated line\n' > "$scratch/.bashrc"
if ( cd "$scratch" && HOME="$scratch" && source "$script" && omawsl_ensure_starship_bashrc_line ) >/dev/null 2>&1; then
  echo "PASS: omawsl_ensure_starship_bashrc_line runs cleanly even with no mise line present"
else
  echo "FAIL: omawsl_ensure_starship_bashrc_line raised an error when ~/.bashrc has no mise activation line"
  failed=1
fi
if grep -q 'starship init bash' "$scratch/.bashrc" 2>/dev/null; then
  echo "PASS: the starship init line is still added when there's no mise line to anchor after"
else
  echo "FAIL: no starship init line was added when ~/.bashrc had no mise activation line"
  failed=1
fi

exit "$failed"
