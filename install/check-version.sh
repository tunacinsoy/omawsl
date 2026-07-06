#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# omawsl_check_version [os_release_file] [arch] [kernel]
# All three arguments default to the real system values and are only ever
# overridden in tests, so this is fully unit-testable without needing to run
# inside an actual WSL2 Ubuntu instance for the failure branches.
omawsl_check_version() {
  local os_release_file="${1:-/etc/os-release}"
  local arch="${2:-$(uname -m)}"
  local kernel="${3:-$(uname -r)}"

  if [[ ! -f "$os_release_file" ]]; then
    echo "omawsl: cannot find $os_release_file - this doesn't look like a supported Linux system." >&2
    return 1
  fi

  local ID="" VERSION_ID=""
  # shellcheck disable=SC1090
  source "$os_release_file"

  if [[ "$ID" != "ubuntu" ]]; then
    echo "omawsl: detected OS '$ID', but omawsl only supports Ubuntu." >&2
    return 1
  fi

  if ! omawsl_version_ge "$VERSION_ID" "24.04"; then
    echo "omawsl: Ubuntu $VERSION_ID detected, but omawsl requires Ubuntu 24.04 or later." >&2
    return 1
  fi

  case "$arch" in
    x86_64|amd64|aarch64|arm64) ;;
    *)
      echo "omawsl: unsupported architecture '$arch'." >&2
      return 1
      ;;
  esac

  if ! omawsl_is_wsl2_kernel "$kernel"; then
    echo "omawsl: this doesn't look like WSL2 (kernel: $kernel). omawsl is built for WSL2 Ubuntu specifically - WSL1 lacks the systemd/networking support this tool relies on. See https://learn.microsoft.com/windows/wsl/install for upgrading to WSL2." >&2
    return 1
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_check_version
fi
