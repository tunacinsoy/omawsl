#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

# Best-effort static regression guard (design spec
# docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md):
# fails if any install/uninstall/migrations/bin script ever gains a
# write-operation pattern targeting one of the never-touch files. migrations/
# and bin/ are scanned too, not just install/uninstall - migrations/ in
# particular exists solely to write to files under $HOME, so it's exactly
# the kind of directory this guard needs to cover. Not exhaustive - a
# determined write in an unusual shape could slip past a literal-pattern
# grep - but cheap, root-free, and catches the common cases (cp, redirect,
# tee, cat >, append) the same way this project's other static
# doc-consistency tests do (tests/readme_test.bats).
@test "no install/uninstall/migrations/bin script writes to a never-touch corp-managed file" {
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
  )
  local pattern
  for pattern in "${forbidden[@]}"; do
    if grep -rnE "(cp |> |>> |tee |cat > )[^|]*(${pattern})" "$REPO_ROOT/install" "$REPO_ROOT/uninstall" "$REPO_ROOT/migrations" "$REPO_ROOT/bin" 2>/dev/null; then
      echo "found a write targeting a never-touch path matching: $pattern"
      return 1
    fi
  done
}

# docker.service.d/* is never-touch except omawsl's own exclusively-owned
# omawsl-proxy.conf (design spec
# docs/superpowers/specs/2026-07-29-docker-daemon-proxy-autoconfig-design.md):
# omawsl writes only that one distinctly-named file, never the conventional
# http-proxy.conf name a corp manual would use, and never at all if another
# file in that directory already configures a proxy. This checks the real
# codebase for a write to anything else under docker.service.d/.
@test "docker.service.d writes are limited to omawsl's own omawsl-proxy.conf" {
  local matches
  matches="$(grep -rnE "(cp |> |>> |tee |cat > )[^|]*docker\.service\.d" "$REPO_ROOT/install" "$REPO_ROOT/uninstall" "$REPO_ROOT/migrations" "$REPO_ROOT/bin" 2>/dev/null | grep -v 'omawsl-proxy\.conf' || true)"
  if [[ -n "$matches" ]]; then
    echo "found a write targeting docker.service.d/ that isn't omawsl-proxy.conf:"
    echo "$matches"
    return 1
  fi
}

# Proves the exception above is narrow in both directions, independent of
# whatever the real codebase currently contains: a fixture write to the
# conventional http-proxy.conf name must still be caught, while a fixture
# write to omawsl-proxy.conf must be allowed.
@test "docker.service.d exception: a write to http-proxy.conf would still be caught" {
  local fixture="$BATS_TEST_TMPDIR/fixture.sh"
  echo 'echo "content" | sudo tee /etc/systemd/system/docker.service.d/http-proxy.conf' > "$fixture"
  run bash -c "grep -rnE '(cp |> |>> |tee |cat > )[^|]*docker\.service\.d' '$fixture' | grep -v 'omawsl-proxy\.conf'"
  [ -n "$output" ]
}

@test "docker.service.d exception: a write to omawsl-proxy.conf is allowed" {
  local fixture="$BATS_TEST_TMPDIR/fixture.sh"
  echo 'echo "content" | sudo tee /etc/systemd/system/docker.service.d/omawsl-proxy.conf' > "$fixture"
  run bash -c "grep -rnE '(cp |> |>> |tee |cat > )[^|]*docker\.service\.d' '$fixture' | grep -v 'omawsl-proxy\.conf'"
  [ -z "$output" ]
}
