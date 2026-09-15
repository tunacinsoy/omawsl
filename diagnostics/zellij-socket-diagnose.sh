#!/usr/bin/env bash
# One-off diagnostic for GitHub issue #34 (zellij "failed to create the
# Zellij socket directory... Permission denied" on a new terminal).
#
# configs/bashrc already exports ZELLIJ_SOCKET_DIR=/tmp/zellij-$(id -u)
# right before every `exec zellij`, specifically to route around
# $XDG_RUNTIME_DIR/zellij permission failures (microsoft/WSL#9689,
# zellij-org/zellij#4155) - that fix landed 2026-07-15, before issue #34
# was filed, and can't be reproduced on the machine that wrote this
# script. This gathers evidence for whether something corp-specific
# (EDR/AV hooking WSL's filesystem, GPO-forced env vars, a non-systemd
# WSL setup, a stale root-owned socket dir from an earlier `sudo`/root
# session, etc.) still defeats it elsewhere.
#
# Entirely read-only: no real file, session, or process is created or
# removed - the one working file is a throwaway mktemp copy of bashrc,
# cleaned up on exit.
#
# Usage: bash diagnostics/zellij-socket-diagnose.sh 2>&1 | tee /tmp/zellij-diagnose.txt
# Then share the output (or the tee'd file) back. Can be run from any
# directory.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

section() { printf '\n=== %s ===\n' "$1"; }

section "Timestamp / identity"
date -Is
whoami
id

section "WSL / kernel / distro"
uname -a
cat /proc/version 2>/dev/null
echo "--- /etc/os-release ---"
cat /etc/os-release 2>/dev/null
echo "--- /etc/wsl.conf (if present) ---"
cat /etc/wsl.conf 2>/dev/null || echo "(no /etc/wsl.conf)"
command -v wslinfo &>/dev/null && wslinfo --version 2>&1

section "systemd status (affects who owns /run/user/<uid>)"
ps -p 1 -o comm= 2>/dev/null
systemctl is-system-running 2>&1 || true
loginctl show-user "$(whoami)" 2>&1 || echo "(loginctl unavailable)"

section "Relevant env vars in THIS shell"
env | grep -E '^(ZELLIJ|XDG_RUNTIME_DIR|HOME|USER)=' | sort

section "Socket/runtime dir permissions"
uid="$(id -u)"
for d in "${XDG_RUNTIME_DIR:-/run/user/$uid}" "${XDG_RUNTIME_DIR:-/run/user/$uid}/zellij" "/tmp/zellij-$uid" "/mnt/wslg/runtime-dir"; do
  if [ -e "$d" ]; then
    stat -c '%n  owner=%U(%u) group=%G(%g) mode=%a' "$d" 2>&1
  else
    echo "$d  (does not exist)"
  fi
done

section "Mount options for /run and /tmp"
mount | grep -E ' on /run | on /tmp ' || echo "(no matching mount lines)"

section "Deployed omawsl checkout vs this repo"
if [ -d "$HOME/.local/share/omawsl/.git" ]; then
  git -C "$HOME/.local/share/omawsl" log -1 --format='HEAD: %H  %ad  %s' --date=iso -- configs/bashrc
  echo "--- ZELLIJ_SOCKET_DIR line present? ---"
  grep -n 'ZELLIJ_SOCKET_DIR' "$HOME/.local/share/omawsl/configs/bashrc" || echo "MISSING - fix not present in deployed checkout"
else
  echo "(no git checkout at ~/.local/share/omawsl)"
fi

section "Simulated brand-new interactive shell (env right before exec zellij)"
# Can't shadow the real `exec zellij` call with a PATH-prepended stub
# binary or a same-named function: `exec` is a POSIX "special builtin",
# which bash always resolves before checking functions or even PATH
# order for the *builtin itself* - and separately, this repo's own
# `mise activate bash` line does an unconditional full PATH reassignment
# (not a prepend relative to the live shell), which would stomp a PATH
# based stub anyway. So instead: source a throwaway copy of the real
# bashrc with only its trailing `exec zellij` line swapped for a harmless
# echo, in a genuinely fresh (ZELLIJ unset) interactive shell.
tmprc="$(mktemp)"
trap 'rm -f "$tmprc"' EXIT
sed 's/^\( *\)exec zellij$/\1echo "[would exec here] ZELLIJ_SOCKET_DIR=${ZELLIJ_SOCKET_DIR:-<unset>} XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-<unset>}"/' "$OMAWSL_ROOT_DIR/configs/bashrc" > "$tmprc"
if ! grep -q '\[would exec here\]' "$tmprc"; then
  echo "WARNING: could not find/replace the 'exec zellij' line - configs/bashrc's shape may have changed; skipping this probe."
else
  # --norc: Debian/Ubuntu's bash auto-sources ~/.bashrc (hence the real,
  # unmodified configs/bashrc and its real `exec zellij`) as part of
  # ordinary interactive-shell startup, before a -c command string ever
  # runs - without --norc this probe would silently launch the real
  # zellij instead of testing the patched copy.
  env -u ZELLIJ bash --norc -ic "source '$tmprc'" 2>&1 | grep -v -E 'job control|process group'
fi

section "Real zellij: does XDG_RUNTIME_DIR/zellij actually fail here right now?"
echo "--- without ZELLIJ_SOCKET_DIR override ---"
env -u ZELLIJ_SOCKET_DIR timeout 5 zellij list-sessions 2>&1
echo "--- with the omawsl override ---"
ZELLIJ_SOCKET_DIR="/tmp/zellij-$uid" timeout 5 zellij list-sessions 2>&1

section "Corp EDR/AV agents commonly seen hooking WSL2 filesystem/IPC"
ps aux 2>/dev/null | grep -iE 'defender|crowdstrike|carbonblack|cortex|sentinelone|zscaler|netskope|forcepoint|cyberark|falcon' | grep -v grep || echo "(none of the usual suspects found in ps aux)"

section "GPO/corp-injected env overrides for XDG_RUNTIME_DIR or ZELLIJ*"
grep -riE 'XDG_RUNTIME_DIR|ZELLIJ' /etc/environment /etc/profile /etc/profile.d/*.sh /etc/bash.bashrc 2>/dev/null || echo "(none found in system-wide profile files)"

section "Recent kernel/journal entries mentioning zellij or the runtime dir"
journalctl -b --no-pager 2>/dev/null | grep -i 'zellij' | tail -20 || echo "(journalctl unavailable or empty)"

echo
echo "=== Done. Please paste the full output back. ==="
