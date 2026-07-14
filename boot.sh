#!/usr/bin/env bash
set -euo pipefail

OMAWSL_REPO="https://github.com/tunacinsoy/omawsl"
OMAWSL_HOME="${OMAWSL_HOME:-$HOME/.local/share/omawsl}"
OMAWSL_REF="${OMAWSL_REF:-master}"

# omawsl_clone_failure_help
# Printed when `git clone`/`git pull` fails for any reason, instead of
# letting git's own (potentially confusing) error propagate on its own.
# Points at the two most likely causes with a concrete next step each,
# rather than a vague "something went wrong."
omawsl_clone_failure_help() {
  cat <<'EOF'

omawsl: couldn't reach the omawsl repository on GitHub.

This is almost always one of:
  1. No internet connection right now - check your network and try again.
  2. You're on a corporate/restricted network that blocks github.com -
     ask your IT team to allow it, or run this from an unrestricted
     network instead.

If neither applies, GitHub itself may be having an outage - check
https://www.githubstatus.com and try again shortly.
EOF
}

omawsl_boot() {
  # Plain bordered text, not a hand-fabricated block-letter font: an earlier
  # draft of this banner used a figlet-style ASCII-art rendering that was
  # never actually verified to spell "omawsl" - a real user running this for
  # real caught it rendering as something unreadable. A bordered plain-text
  # banner has no font-rendering ambiguity to get wrong.
  cat <<'BANNER'
================================================
                 o m a w s l
================================================

Bring your WSL2 Ubuntu install up to Omakub-parity in one run.
BANNER

  if [[ "${OMAWSL_ASSUME_YES:-}" != "1" ]]; then
    local reply=""
    read -r -p "Continue? [y/N] " reply || true
    [[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
  fi

  sudo apt-get update -qq
  sudo apt-get install -y git curl

  if [[ -d "$OMAWSL_HOME/.git" ]]; then
    echo "omawsl: existing checkout found at $OMAWSL_HOME, pulling latest instead of re-cloning."
    if ! git -C "$OMAWSL_HOME" pull; then
      omawsl_clone_failure_help
      exit 1
    fi
  else
    if ! git clone "$OMAWSL_REPO" "$OMAWSL_HOME"; then
      omawsl_clone_failure_help
      exit 1
    fi
  fi

  if [[ "$OMAWSL_REF" != "master" ]]; then
    git -C "$OMAWSL_HOME" checkout "$OMAWSL_REF"
  fi

  # Invoke via `bash` explicitly rather than relying on the file's own
  # executable bit: this repo is authored on Windows, where git does not
  # reliably track the executable bit on checkout into WSL2's ext4 - a
  # plain `exec "$OMAWSL_HOME/install.sh"` would fail with "Permission
  # denied" the first time this actually runs for real, since the
  # committed file has no +x bit. Caught by the final whole-branch review,
  # not by any per-task test, since every test fabricates its own
  # already-executable stand-in install.sh rather than exec'ing the real
  # committed file.
  exec bash "$OMAWSL_HOME/install.sh"
}

# No `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` sourced-vs-executed guard here
# (unlike most other scripts in this repo): boot.sh is never sourced
# anywhere, and the guard actively breaks the documented one-liner
# (`curl -fsSL ... | bash`) - when bash reads a script from stdin instead
# of a real file, BASH_SOURCE is a zero-element array, so BASH_SOURCE[0] is
# a genuinely unbound reference under `set -u` and aborts before this line
# ever runs. Confirmed via direct reproduction: piping this file's own
# contents into `bash` hits the identical "unbound variable" error real
# users hit running the real one-liner.
omawsl_boot
