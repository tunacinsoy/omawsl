#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
DOC="$DIR/docs/windows-setup.md"
WT_JSON="$DIR/windows/windows-terminal.json"
WT_FALLBACK_JSON="$DIR/windows/windows-terminal-fallback.json"
FONTS_README="$DIR/windows/fonts/README.md"
README="$DIR/README.md"

failed=0

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failed=1; }

# --- docs/windows-setup.md -------------------------------------------------

if [[ -f "$DOC" ]]; then
  pass "docs/windows-setup.md exists"
else
  fail "docs/windows-setup.md does not exist"
fi

if [[ -f "$DOC" ]]; then
  anchor_line="$(grep -n '<a id="quick-reference"></a>' "$DOC" | head -1 | cut -d: -f1 || echo '')"
  heading_line="$(grep -n '^## Quick reference' "$DOC" | head -1 | cut -d: -f1 || echo '')"

  if [[ -n "$anchor_line" && -n "$heading_line" && "$anchor_line" -lt "$heading_line" ]]; then
    pass "explicit <a id=\"quick-reference\"></a> anchor appears immediately before the Quick reference heading"
  else
    fail "no <a id=\"quick-reference\"></a> anchor found directly above a '## Quick reference' heading"
  fi

  if [[ -n "$heading_line" ]]; then
    other_first_heading_line="$(grep -n '^## ' "$DOC" | grep -v '^'"$heading_line"':' | head -1 | cut -d: -f1 || echo '')"
    if [[ -z "$other_first_heading_line" || "$heading_line" -lt "$other_first_heading_line" ]]; then
      pass "Quick reference is the first section in the doc"
    else
      fail "Quick reference is not the first '##' section in the doc"
    fi
  else
    fail "no '## Quick reference' heading found, so section ordering can't be checked"
  fi

  missing_anchors=()
  for anchor in windows-terminal fonts docker-desktop vscode cursor github-copilot-cli windows-terminal-theme; do
    if ! grep -qF "<a id=\"$anchor\"></a>" "$DOC"; then
      missing_anchors+=("$anchor")
    fi
  done
  if [[ "${#missing_anchors[@]}" -eq 0 ]]; then
    pass "all 7 required explicit anchors present (windows-terminal, fonts, docker-desktop, vscode, cursor, github-copilot-cli, windows-terminal-theme)"
  else
    fail "missing explicit <a id=\"...\"> anchor(s) for: ${missing_anchors[*]}"
  fi
else
  fail "skipping docs/windows-setup.md content checks - file does not exist"
fi

# --- windows/windows-terminal.json -----------------------------------------

if [[ -f "$WT_JSON" ]]; then
  if jq empty "$WT_JSON" > /dev/null 2>&1; then
    pass "windows/windows-terminal.json is valid JSON"

    face="$(jq -r '.profiles.defaults.font.face // empty' "$WT_JSON" 2>/dev/null || echo '')"
    if [[ "$face" == "CaskaydiaMono Nerd Font Mono" ]]; then
      pass "windows/windows-terminal.json sets profiles.defaults.font.face to 'CaskaydiaMono Nerd Font Mono'"
    else
      fail "windows/windows-terminal.json's profiles.defaults.font.face was '$face', expected 'CaskaydiaMono Nerd Font Mono'"
    fi

    keys="$(jq -r '[.actions[]? | select(.command == "unbound") | .keys] | sort | join(",")' "$WT_JSON" 2>/dev/null || echo '')"
    if [[ "$keys" == "alt+down,alt+left,alt+right,alt+up" ]]; then
      pass "windows/windows-terminal.json unbinds all four Alt+arrow chords"
    else
      fail "windows/windows-terminal.json's unbound keys were '$keys', expected alt+down,alt+left,alt+right,alt+up"
    fi
  else
    fail "windows/windows-terminal.json is not valid JSON"
  fi
else
  fail "windows/windows-terminal.json does not exist"
fi

# --- windows/windows-terminal-fallback.json ---------------------------------

if [[ -f "$WT_FALLBACK_JSON" ]]; then
  if jq empty "$WT_FALLBACK_JSON" > /dev/null 2>&1; then
    pass "windows/windows-terminal-fallback.json is valid JSON"

    face="$(jq -r '.profiles.defaults.font.face // empty' "$WT_FALLBACK_JSON" 2>/dev/null || echo '')"
    if [[ "$face" == "Cascadia Mono" ]]; then
      pass "windows/windows-terminal-fallback.json sets profiles.defaults.font.face to 'Cascadia Mono'"
    else
      fail "windows/windows-terminal-fallback.json's profiles.defaults.font.face was '$face', expected 'Cascadia Mono'"
    fi

    keys="$(jq -r '[.actions[]? | select(.command == "unbound") | .keys] | sort | join(",")' "$WT_FALLBACK_JSON" 2>/dev/null || echo '')"
    if [[ "$keys" == "alt+down,alt+left,alt+right,alt+up" ]]; then
      pass "windows/windows-terminal-fallback.json unbinds all four Alt+arrow chords"
    else
      fail "windows/windows-terminal-fallback.json's unbound keys were '$keys', expected alt+down,alt+left,alt+right,alt+up"
    fi
  else
    fail "windows/windows-terminal-fallback.json is not valid JSON"
  fi
else
  fail "windows/windows-terminal-fallback.json does not exist"
fi

# --- windows/fonts/README.md -------------------------------------------------

if [[ -f "$FONTS_README" ]]; then
  if grep -qF "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip" "$FONTS_README"; then
    pass "windows/fonts/README.md points at the real upstream nerd-fonts release URL"
  else
    fail "windows/fonts/README.md does not contain the upstream nerd-fonts release URL"
  fi
else
  fail "windows/fonts/README.md does not exist"
fi

# --- README.md ---------------------------------------------------------------

if [[ -f "$README" ]]; then
  if grep -qF "## Before you begin" "$README"; then
    pass "README.md has a '## Before you begin' section"
  else
    fail "README.md is missing a '## Before you begin' section"
  fi

  if grep -qF "docs/windows-setup.md#quick-reference" "$README"; then
    pass "README.md links docs/windows-setup.md#quick-reference instead of duplicating the table"
  else
    fail "README.md does not link docs/windows-setup.md#quick-reference"
  fi
else
  fail "README.md does not exist"
fi

exit "$failed"
