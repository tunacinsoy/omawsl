#!/usr/bin/env bash
set -euo pipefail

OMAWSL_REPO="https://github.com/tunacinsoy/omawsl"
OMAWSL_HOME="${OMAWSL_HOME:-$HOME/.local/share/omawsl}"
OMAWSL_REF="${OMAWSL_REF:-master}"

omawsl_boot() {
  cat <<'BANNER'
   ____  __  __    ___          _
  / __ \|  \/  |  /   |_      _(_)________ ___
 / / / /| |\/| | / /| \ \ /\ / / / ___/ __ `__ \
/ /_/ / | |  | |/ ___ |\ V  V / (__  ) / / / / /
\____/  |_|  |_/_/  |_| \_/\_/_/____/_/ /_/ /_/

omawsl: bring your WSL2 Ubuntu install up to Omakub-parity in one run.
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
    git -C "$OMAWSL_HOME" pull
  else
    git clone "$OMAWSL_REPO" "$OMAWSL_HOME"
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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_boot
fi
