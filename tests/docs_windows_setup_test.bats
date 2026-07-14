#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DOC="$REPO_ROOT/docs/windows-setup.md"

@test "docs/windows-setup.md exists" {
  [ -f "$DOC" ]
}

@test "docs/windows-setup.md has every heading the shipped code already links to" {
  for heading in "## Windows Terminal" "## Fonts" "## Docker Desktop" "## VS Code" "## Cursor" "## GitHub Copilot CLI" "## Windows Terminal theme" "## VS Code and Cursor theme"; do
    grep -qF "$heading" "$DOC" || { echo "missing heading: $heading"; return 1; }
  done
}

@test "docs/windows-setup.md opens with a quick-reference table before any numbered section" {
  local table_line section_line
  table_line="$(grep -n '^## Quick reference' "$DOC" | head -1 | cut -d: -f1)"
  section_line="$(grep -n '^## Windows Terminal$' "$DOC" | head -1 | cut -d: -f1)"
  [ -n "$table_line" ]
  [ -n "$section_line" ]
  [ "$table_line" -lt "$section_line" ]
}

@test "docs/windows-setup.md references both windows-terminal json fragments" {
  grep -q "windows/windows-terminal.json" "$DOC"
  grep -q "windows/windows-terminal-fallback.json" "$DOC"
}

@test "every anchor already hardcoded in shipped code has a matching explicit <a id> in this doc" {
  # design spec requires docs/windows-setup.md to be the single canonical target for
  # every pointer already shipped in install/*.sh and bin/omawsl-sub/*.sh. Checking the
  # literal <a id="..."> tag (not a heading-text-derived slug guess) is what actually
  # guarantees the anchor resolves, independent of how the heading text itself reads.
  grep -rhoE 'docs/windows-setup\.md#[a-z0-9-]+' "$REPO_ROOT/install" "$REPO_ROOT/bin" "$REPO_ROOT/themes" | sed 's/.*#//' | sort -u > "$BATS_TEST_TMPDIR/wanted_anchors"
  while read -r anchor; do
    grep -qF "<a id=\"$anchor\"></a>" "$DOC" || { echo "doc missing <a id=\"$anchor\"> for anchor referenced in code"; return 1; }
  done < "$BATS_TEST_TMPDIR/wanted_anchors"
}
