#!/usr/bin/env bats

# omawsl is a solution for WSL, not for Windows: it never starts a Windows
# program from WSL. On a managed laptop that looks like an attack to
# security tools, and anything IT blocks there is IT's call, not something
# to work around. See CONTRIBUTING.md.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "no omawsl script starts cmd.exe or PowerShell" {
  local hits
  hits="$(cd "$REPO_ROOT" && grep -rnIiE 'cmd\.exe|powershell\.exe|pwsh' \
    bin install themes migrations uninstall configs diagnostics boot.sh install.sh 2>/dev/null |
    grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true)"
  [ -z "$hits" ] || { echo "$hits"; return 1; }
}

@test "CONTRIBUTING.md states the rule for people and AI tools" {
  grep -qF "never starts a Windows program" "$REPO_ROOT/CONTRIBUTING.md"
}
