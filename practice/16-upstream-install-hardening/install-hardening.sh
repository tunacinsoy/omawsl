#!/usr/bin/env bash
set -euo pipefail

# Phase 16 practice scaffold - upstream-install-hardening
#
# Implement each function below. Nothing here is wired up to a dispatcher
# and nothing here should actually run apt, sudo, or a real network
# request when you're done - every "dangerous" step (the real curl
# download, the real `sudo install` of a binary) belongs in a separate
# *_install function you are NOT asked to write for this exercise. What
# you ARE asked to write is the decision logic in front of it: which
# path/URL/header would this reach for, given the current machine and
# environment - see the lesson's Exercise section for the exact
# requirements and behavior of each function.
#
# check.sh sources this file directly and calls these functions by name,
# so keep the names and general shape (arguments in, a value on stdout,
# exit status for success/failure) as specified in the lesson.

# omawsl_resolve_cmd_exe
# TODO: find cmd.exe even when it's not on $PATH.
omawsl_resolve_cmd_exe() {
  :
}

# omawsl_orphan_github_token
# TODO: best-effort GitHub token from the environment/gh CLI.
omawsl_orphan_github_token() {
  :
}

# omawsl_orphan_github_auth_args
# TODO: curl -H arguments (one per line) built from the token above.
omawsl_orphan_github_auth_args() {
  :
}

# omawsl_lazygit_arch
# TODO: map dpkg's architecture name to lazygit's release-asset naming.
omawsl_lazygit_arch() {
  :
}

# omawsl_lazydocker_arch
# TODO: map dpkg's architecture name to lazydocker's release-asset naming.
omawsl_lazydocker_arch() {
  :
}

# omawsl_fastfetch_arch
# TODO: map dpkg's architecture name to fastfetch's release-asset naming.
omawsl_fastfetch_arch() {
  :
}

# omawsl_lazygit_release_url
# TODO: resolve the latest lazygit version via the GitHub API (using the
# auth helpers above) and print the full download URL for the current
# architecture. Do NOT download or install anything here - just print
# the URL that the real install step would fetch.
omawsl_lazygit_release_url() {
  :
}

# omawsl_lazydocker_release_url
# TODO: same idea as omawsl_lazygit_release_url, for lazydocker. Check
# lazydocker's actual release filenames before assuming they look like
# lazygit's.
omawsl_lazydocker_release_url() {
  :
}

# omawsl_fastfetch_release_url
# TODO: print fastfetch's download URL for the current architecture.
# fastfetch's release filenames don't embed a version number, so this
# one needs no GitHub API call at all.
omawsl_fastfetch_release_url() {
  :
}
