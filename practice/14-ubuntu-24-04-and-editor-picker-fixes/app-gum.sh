#!/usr/bin/env bash
set -euo pipefail

# TODO: omawsl_install_gum [apt_sources_file] [keyrings_dir]
#
# gum (the TUI tool the installer's own prompts run on) only ships in
# Ubuntu's built-in "universe" apt repo starting with Ubuntu 26.04. On the
# 24.04/25.x floor this project actually promises, a plain
# `apt-get install gum` 404s with "Unable to locate package gum" - and
# since gum is what every later prompt runs on, that breaks the installer
# before it can even ask the user anything.
#
# The fix: add Charm's own apt repository (https://repo.charm.sh/apt/),
# GPG-signed, so gum resolves on every supported Ubuntu version the same
# way, instead of branching install logic on the Ubuntu version number.
#
# Implement this function, taking two OPTIONAL arguments so a check script
# can point it at scratch locations instead of real system paths:
#   $1 - apt_sources_file, defaulting to
#        /etc/apt/sources.list.d/charm.list
#   $2 - keyrings_dir, defaulting to /etc/apt/keyrings
#
# Behavior:
#   1. If apt_sources_file does NOT already exist, add the repo (this part
#      should run at most once ever, on a real machine - guarded by the
#      sources file's own existence, not a separate marker):
#        a. sudo install -m 0755 -d <keyrings_dir>
#        b. Fetch Charm's GPG signing key from https://repo.charm.sh/apt/gpg.key
#           with curl, and dearmor it into <keyrings_dir>/charm.gpg via
#           `sudo gpg --yes --dearmor -o <keyrings_dir>/charm.gpg`
#           (pipe the curl output into that gpg command).
#        c. Write one apt sources line to apt_sources_file (via
#           `sudo tee`, not a plain redirect - the file lives under
#           /etc/apt, which an unprivileged redirect can't write to):
#             deb [signed-by=<keyrings_dir>/charm.gpg] https://repo.charm.sh/apt/ * *
#   2. Always (whether or not the repo was just added):
#        sudo apt-get update -qq
#        sudo apt-get install -y gum
#      (apt-get install is already idempotent on its own - it no-ops if
#      gum is already at the candidate version - so no extra `command -v
#      gum` guard is needed here.)
#
# omawsl_install_gum() {
#   ...
# }
