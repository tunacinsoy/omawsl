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

@test "docs/updating.md lists all 7 orphan tools by name" {
  for tool in Zellij LazyDocker opencode "Claude Code CLI" "Codex CLI" "Gemini CLI" "GitHub Copilot CLI"; do
    grep -qF "$tool" "$DOC" || { echo "missing tool: $tool"; return 1; }
  done
}
