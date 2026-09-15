#!/usr/bin/env bash
set -euo pipefail

# omawsl_opencode_install_steps
# PROVIDED - do not change. Stands in for the real installer (which would
# really run `curl -fsSL https://opencode.ai/install | bash`). Just records
# that it ran, by writing to $OMAWSL_TEST_LOG - one line per call - so a
# check script can tell whether your guard function below called it or
# correctly skipped it, without any real network access.
omawsl_opencode_install_steps() {
  echo "install_steps called" >> "${OMAWSL_TEST_LOG:-/dev/null}"
}

# TODO: omawsl_install_opencode
#
# The real opencode installer places the binary at
# $HOME/.opencode/bin/opencode. That directory only reaches PATH via
# configs/bashrc, which runs when a *new* shell starts - not the shell
# that's mid-way through running this installer right now. So `command -v
# opencode` alone can wrongly report "not found" immediately after a real
# install, in the very same shell that just installed it.
#
# Implement this function so it:
#   1. Does nothing (returns 0) if opencode is already installed - checked
#      TWO ways, either of which counts as "already installed":
#        a. `opencode` is resolvable on the current $PATH, OR
#        b. an executable file exists at $HOME/.opencode/bin/opencode,
#           even if that directory isn't on $PATH yet in this shell.
#   2. Otherwise, calls omawsl_opencode_install_steps (defined above).
#
# omawsl_install_opencode() {
#   ...
# }
