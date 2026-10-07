#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DOC="$REPO_ROOT/docs/updating.md"

@test "docs/updating.md exists" {
  [ -f "$DOC" ]
}

@test "docs/updating.md documents all four update groups" {
  grep -qi "omawsl update" "$DOC"
  grep -qi "mise upgrade" "$DOC"
  grep -qi "apt upgrade" "$DOC"
  grep -qi "VS Code" "$DOC"
  grep -qi "own update" "$DOC"
}

@test "docs/updating.md lists every orphan tool by name" {
  for tool in Zellij LazyDocker opencode "Claude Code CLI" "Codex CLI" "Antigravity CLI" "GitHub Copilot CLI" Herdr; do
    grep -qF "$tool" "$DOC" || { echo "missing tool: $tool"; return 1; }
  done
}
