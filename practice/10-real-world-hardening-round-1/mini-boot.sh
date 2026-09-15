#!/usr/bin/env bash
set -euo pipefail

# mini-boot.sh — a scaled-down stand-in for the real boot.sh, built to
# expose the same two bugs the real one hit on its first real
# `curl | bash` run.
#
# Rebuild this so it behaves correctly BOTH when run normally
# (`bash mini-boot.sh`) AND when piped into bash the way the real
# one-liner works (`cat mini-boot.sh | bash`). A check that only ever
# runs `bash mini-boot.sh` against a real file on disk cannot catch
# either bug — you have to test the piped form too.
#
# Required behavior:
#
#   1. Print a banner line containing the word "omawsl" to stdout.
#
#   2. Unless OMAWSL_ASSUME_YES=1 is set in the environment, ask for
#      confirmation with a prompt containing "Continue?" and read the
#      answer from the REAL CONTROLLING TERMINAL, not from bash's own
#      stdin. (Under `curl | bash`, stdin is the script's own text
#      being fed to bash — not the user's keystrokes.)
#
#   3. If the answer is not "y"/"Y" — including when there's no
#      controlling terminal to read from at all — print exactly
#      "Aborted." on its own line and exit with status 1. Must not
#      hang and must not crash.
#
#   4. Otherwise (confirmed, or OMAWSL_ASSUME_YES=1), print exactly
#      "INSTALL_RAN" on its own line as a stand-in for the real
#      install step, and exit 0.
#
#   5. Must not crash with an "unbound variable" error (or any other
#      error) when bash reads this file from a pipe instead of from a
#      real file path on disk.
#
# Fill in the implementation below this line.
