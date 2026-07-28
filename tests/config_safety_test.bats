#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# Best-effort static regression guard (design spec
# docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md):
# fails if any install/uninstall script ever gains a write-operation
# pattern targeting one of the never-touch files. Not exhaustive - a
# determined write in an unusual shape could slip past a literal-pattern
# grep - but cheap, root-free, and catches the common cases (cp, redirect,
# tee, cat >, append) the same way this project's other static
# doc-consistency tests do (tests/readme_test.bats).
@test "no install/uninstall script writes to a never-touch corp-managed file" {
  local forbidden=(
    '\.zshrc'
    '/etc/zsh/zshenv'
    '\.oh-my-zsh'
    '\.curlrc'
    '/etc/apt/apt\.conf\.d'
    '/etc/profile\.d'
    '/etc/sudoers'
    '\.m2/settings\.xml'
    '\.git-templates'
    '\.config/direnv/direnvrc'
    'wsl-vpnkit\.service'
    'docker\.service\.d'
  )
  local pattern
  for pattern in "${forbidden[@]}"; do
    if grep -rnE "(cp |> |>> |tee |cat > )[^|]*(${pattern})" "$REPO_ROOT/install" "$REPO_ROOT/uninstall" 2>/dev/null; then
      echo "found a write targeting a never-touch path matching: $pattern"
      return 1
    fi
  done
}
