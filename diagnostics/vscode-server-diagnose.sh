#!/usr/bin/env bash
# One-off diagnostic for GitHub issues #35 ("Updating VS Code Server ...
# Removing previous installation..." on `code .`) and #36 ("Could not
# fetch remote environment" / WebSocket close 1006).
#
# Both messages come from the Remote-WSL extension's own
# scripts/wslDownload.sh, which runs on every `code .` (via wslCode.sh,
# with the COMMIT hardcoded into whichever Windows-side `bin/code` wins
# on WSL's $PATH) and on every window connect (via wslServer.sh, with the
# connecting GUI's own commit). When ~/.vscode-server/bin/<COMMIT> is
# missing it `rm -rf`s every other 40-char commit dir there - including
# one a still-open window's server is running from, which is what kills
# that window's extension host (#36). So any time two different commits
# take turns asking, every `code .` reinstalls and every open window
# dies. PR #33's `update.mode: manual` only stops VS Code's own updater
# from moving the commit; it can't help if two installs (or a stale
# bin/code) disagree. #35's commit 0958016b is VS Code 1.120.0, about
# four months older than current stable when the issue was filed -
# suggesting the terminal's `code` was an older install than the GUI.
#
# This gathers the evidence to confirm or rule that out. Entirely
# read-only: lists, reads and queries; nothing is created, removed, or
# changed, on either the WSL or the Windows side.
#
# Usage: bash diagnostics/vscode-server-diagnose.sh 2>&1 | tee /tmp/vscode-diagnose.txt
# Best run right after seeing "Updating VS Code Server" (with the VS Code
# window still open). Then share the output (or the tee'd file) back.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"

section() { printf '\n=== %s ===\n' "$1"; }

# Every distinct commit seen, tagged by where it came from - the verdict
# at the end compares them.
declare -A SEEN=()
note_commit() { [[ -n "$2" ]] && SEEN["$1"]="$2"; }

# install_commits <install dir (WSL path)>
# Prints the commit its bin/code would request, and the commit(s) of the
# build(s) actually sitting in it (versioned-folder layout or the older
# flat one).
install_commits() {
  local dir="$1" pj
  echo "bin/code COMMIT: $(grep -m1 '^COMMIT=' "$dir/bin/code" 2>/dev/null | cut -d'"' -f2)"
  for pj in "$dir"/resources/app/product.json "$dir"/*/resources/app/product.json; do
    [[ -f "$pj" ]] || continue
    printf 'build: %s  version=%s  commit=%s\n' "${pj#"$dir"/}" \
      "$(grep -o '"version": *"[^"]*"' "${pj%product.json}package.json" 2>/dev/null | head -1 | cut -d'"' -f4)" \
      "$(grep -o '"commit": *"[^"]*"' "$pj" | head -1 | cut -d'"' -f4)"
  done
}

section "Timestamp / identity"
date -Is
whoami

section "WSL config (appendWindowsPath, automount root)"
cat /etc/wsl.conf 2>/dev/null || echo "(no /etc/wsl.conf)"
c_root="$(wslpath -u 'C:\' 2>/dev/null)"
echo "C: drive is mounted at: ${c_root:-<wslpath failed>}"

section "Every 'code' on PATH (the FIRST one is what 'code .' runs)"
type -a code 2>&1
i=0
while IFS= read -r c; do
  i=$((i + 1))
  commit="$(grep -m1 '^COMMIT=' "$c" 2>/dev/null | cut -d'"' -f2)"
  echo "[$i] $c -> $(readlink -f "$c")  COMMIT=${commit:-?}"
  note_commit "PATH code #$i ($c)" "$commit"
done < <(type -ap code)
echo "--- rc-file lines that mention VS Code / put code on PATH ---"
grep -nH -iE 'vs ?code|/bin/code|Microsoft VS Code' ~/.bashrc ~/.bashrc.local ~/.profile ~/.bash_profile /etc/profile.d/*.sh 2>/dev/null || echo "(none)"

section "omawsl's Windows profile lookup (what PR #33's fix depends on)"
echo "omawsl_resolve_cmd_exe: $(omawsl_resolve_cmd_exe || echo '<FAILED>')"
profile="$(omawsl_windows_userprofile)" || profile=""
echo "omawsl_windows_userprofile: ${profile:-<FAILED - so the update.mode fix silently did nothing>}"
echo "omawsl migration state version: $(cat "$(omawsl_choices_dir)/version" 2>/dev/null || echo '<none>') (PR #33's migration is 1788278074)"

section "Known VS Code installs on Windows"
candidates=()
[[ -n "$profile" ]] && candidates+=("$profile/AppData/Local/Programs/Microsoft VS Code")
[[ -n "$c_root" ]] && candidates+=("${c_root%/}/Program Files/Microsoft VS Code" "${c_root%/}/Program Files (x86)/Microsoft VS Code")
# Also the install dir behind every PATH `code`, in case it's somewhere else.
while IFS= read -r c; do candidates+=("$(dirname "$(dirname "$(readlink -f "$c")")")"); done < <(type -ap code)
declare -A done_dirs=()
for d in "${candidates[@]}"; do
  [[ -n "${done_dirs[$d]:-}" ]] && continue
  done_dirs["$d"]=1
  if [[ -d "$d" ]]; then
    echo "--- $d"
    install_commits "$d"
    ls -la --time-style=long-iso "$d" 2>/dev/null | grep -E ' [0-9a-f]{10}$|bin$|Code.exe$'
  else
    echo "--- $d (not present)"
  fi
done

section "Running VS Code GUI processes on Windows (which install is actually open)"
ps_exe="${c_root%/}/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
if [[ -n "$c_root" && -x "$ps_exe" ]]; then
  gui_paths="$("$ps_exe" -NoProfile -NonInteractive -Command \
    "Get-Process Code -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path -Unique" 2>&1 | tr -d '\r')"
  echo "${gui_paths:-(no Code.exe running)}"
  while IFS= read -r p; do
    [[ "$p" == *Code.exe ]] || continue
    gui_dir="$(wslpath -u "$(dirname "$p" | tr '/' '\\')" 2>/dev/null || true)"
    # Code.exe sits at the install root; the running build is its versioned
    # folder (or resources/ in the older flat layout).
    [[ -n "$gui_dir" ]] || continue
    echo "--- $gui_dir"
    install_commits "$gui_dir"
    gui_commit="$(install_commits "$gui_dir" | grep '^build:' | grep -o 'commit=[0-9a-f]*' | cut -d= -f2 | sort -u | head -1)"
    note_commit "running GUI ($p)" "$gui_commit"
  done <<< "$gui_paths"
else
  echo "(powershell.exe not reachable at $ps_exe - skipped)"
fi

section "Native settings.json update settings"
if [[ -n "$profile" ]]; then
  grep -n '"update\.' "$profile/AppData/Roaming/Code/User/settings.json" 2>/dev/null || echo "(no update.* keys - update.mode fix NOT applied)"
else
  echo "(profile unresolved - can't read native settings.json)"
fi

section "Installed WSL-side servers (~/.vscode-server)"
ls -la --time-style=full-iso ~/.vscode-server/bin 2>/dev/null || echo "(no ~/.vscode-server/bin)"
ls -la --time-style=full-iso ~/.vscode-server/cli/servers 2>/dev/null
for d in ~/.vscode-server/bin/*/; do
  b="$(basename "$d")"
  [[ "$b" =~ ^[0-9a-f]{40}$ ]] && note_commit "installed server ($b)" "$b"
done

section "Running WSL-side server processes (which commit open windows use)"
ps -eo pid,lstart,args 2>/dev/null | grep -E '\.vscode-server/(bin|cli)' | grep -v grep || echo "(none running)"
while IFS= read -r c; do note_commit "running server ($c)" "$c"; done < <(
  ps -eo args 2>/dev/null | grep -oE '\.vscode-server/bin/[0-9a-f]{40}' | cut -d/ -f3 | sort -u)

section "Recent server logs dirs (timestamps line up with reinstalls/disconnects)"
ls -1t ~/.vscode-server/data/logs 2>/dev/null | head -10 || echo "(none)"

section "Remote-WSL extension"
if [[ -n "$profile" ]]; then
  ls -d "$profile"/.vscode/extensions/ms-vscode-remote.remote-wsl-* 2>/dev/null || echo "(not found in $profile/.vscode/extensions)"
fi

section "Commit versions (from Microsoft's update API)"
for c in $(printf '%s\n' "${SEEN[@]}" | sort -u); do
  v="$(curl -s --max-time 5 "https://update.code.visualstudio.com/api/versions/commit:$c/win32-x64-user/stable" | grep -o '"productVersion":"[^"]*"' | cut -d'"' -f4)"
  echo "$c = ${v:-<lookup failed>}"
done

section "VERDICT"
for k in "${!SEEN[@]}"; do printf '%s  <- %s\n' "${SEEN[$k]}" "$k"; done | sort
distinct="$(printf '%s\n' "${SEEN[@]}" | sort -u | grep -c .)"
if [[ "$distinct" -gt 1 ]]; then
  echo
  echo "MISMATCH: $distinct different commits are in play. Each one that's missing"
  echo "from ~/.vscode-server/bin makes wslDownload.sh delete all the others -"
  echo "the reinstall (#35) and the dropped windows (#36)."
else
  echo
  echo "Only one commit seen - no install mismatch right now. If the reinstall"
  echo "happened just before this ran, the commit may have moved (an update);"
  echo "check the native settings.json section above."
fi

echo
echo "=== Done. Please paste the full output back. ==="
