#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DOC="$REPO_ROOT/README.md"

@test "README.md exists" {
  [ -f "$DOC" ]
}

@test "README.md has a Before you begin section" {
  grep -qF "## Before you begin" "$DOC"
}

@test "README.md has a What omawsl deliberately excludes section" {
  grep -qF "## What omawsl deliberately excludes" "$DOC"
}

@test "README.md excludes section names all three required items" {
  grep -q "37signals" "$DOC"
  grep -q "desktop-app layer" "$DOC"
  grep -q "automatic Windows-side software installation" "$DOC"
}

@test "README.md links to windows-setup.md's quick-reference table instead of duplicating it" {
  grep -q "docs/windows-setup.md#quick-reference" "$DOC"
  # guard against accidental duplication: the pipe-table syntax from windows-setup.md's
  # quick-reference table should not also appear verbatim in README.md
  ! grep -q "^| If you picked" "$DOC"
}

@test "README.md contains the real boot.sh one-liner" {
  grep -q "curl -fsSL https://raw.githubusercontent.com/tunacinsoy/omawsl/master/boot.sh | bash" "$DOC"
}
