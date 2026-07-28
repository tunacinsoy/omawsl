#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DOC="$REPO_ROOT/docs/config-safety.md"

@test "docs/config-safety.md exists" {
  [ -f "$DOC" ]
}

@test "docs/config-safety.md states the core policy" {
  grep -qF "omawsl never writes its own content directly into a file it doesn't exclusively own" "$DOC"
}

@test "docs/config-safety.md lists every never-touch file" {
  for path in '~/.zshrc' '/etc/zsh/zshenv' '~/.oh-my-zsh' '~/.curlrc' '/etc/apt/apt.conf.d' '/etc/profile.d' '/etc/sudoers' '~/.m2/settings.xml' '~/.git-templates' '~/.config/direnv/direnvrc' '/etc/systemd/system/wsl-vpnkit.service' '/etc/systemd/system/docker.service.d'; do
    grep -qF "$path" "$DOC" || { echo "missing never-touch entry: $path"; return 1; }
  done
}
