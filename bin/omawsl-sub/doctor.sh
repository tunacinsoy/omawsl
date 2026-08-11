#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=items.sh
source "$SCRIPT_DIR/items.sh"
# shellcheck source=../../install/terminal/docker.sh
source "$OMAWSL_ROOT_DIR/install/terminal/docker.sh"

# omawsl_doctor_language_installed <slug>
# Terraform/Azure CLI aren't mise-managed (design spec §12), so they're
# checked via command -v; the 8 mise-managed tools are checked against
# `mise ls --current`'s own tool-name column - this is what mise use
# --global actually configures (verified live: `mise ls --current` lists
# exactly go/python/ruby on the real test WSL2 instance after those three
# were selected).
_omawsl_doctor_mise_current_cache=""
_omawsl_doctor_mise_current_cached=0
omawsl_doctor_language_installed() {
  local slug="$1"
  case "$slug" in
    terraform) command -v terraform &>/dev/null ;;
    *)
      local mise_tool
      case "$slug" in
        ruby) mise_tool=ruby ;; node) mise_tool=node ;; go) mise_tool=go ;;
        php) mise_tool=php ;; python) mise_tool=python ;; elixir) mise_tool=elixir ;;
        rust) mise_tool=rust ;; java) mise_tool=java ;;
        *) return 1 ;;
      esac
      if [[ "$_omawsl_doctor_mise_current_cached" -eq 0 ]]; then
        _omawsl_doctor_mise_current_cached=1
        command -v mise &>/dev/null && _omawsl_doctor_mise_current_cache="$(mise ls --current 2>/dev/null | awk '{print $1}')"
      fi
      [[ -n "$_omawsl_doctor_mise_current_cache" ]] && grep -qx "$mise_tool" <<< "$_omawsl_doctor_mise_current_cache"
      ;;
  esac
}

# omawsl_doctor_cloud_installed <slug>
omawsl_doctor_cloud_installed() {
  local slug="$1"
  case "$slug" in
    azure) command -v az &>/dev/null ;;
    aws) command -v aws &>/dev/null ;;
    gcp) command -v gcloud &>/dev/null ;;
    *) return 1 ;;
  esac
}

# omawsl_doctor_editor_installed <slug>
omawsl_doctor_editor_installed() {
  local slug="$1"
  case "$slug" in
    vscode) omawsl_code_reachable ;;
    cursor) omawsl_cursor_reachable ;;
    neovim) [[ -d "$HOME/.config/nvim" ]] ;;
    opencode) command -v opencode &>/dev/null ;;
    claude) command -v claude &>/dev/null ;;
    codex) command -v codex &>/dev/null ;;
    antigravity) command -v agy &>/dev/null ;;
    gh-copilot) command -v copilot &>/dev/null ;;
    *) return 1 ;;
  esac
}

# omawsl_doctor_storage_installed <slug>
# The report loop now calls this once per registered slug rather than
# once per selected one (see omawsl_doctor_report_category below), so the
# `sudo docker ps -a` + `docker info` round-trip is cached across calls
# within one doctor run instead of re-shelling out per slug - otherwise a
# single-item selection would still probe the daemon once per *registry*
# entry on every invocation. That also means it now runs on every doctor
# invocation whenever docker is reachable, even for users who never
# selected any storage item - `sudo -n` (rather than plain `sudo`) keeps
# that from turning into a surprise interactive password prompt (or an
# indefinite wait for one) on a report-only diagnostic; no cached sudo
# ticket just means the storage section can't confirm anything, same as
# docker being unreachable at all.
_omawsl_doctor_storage_containers_cache=""
_omawsl_doctor_storage_containers_cached=0
omawsl_doctor_storage_installed() {
  local slug="$1" container
  case "$slug" in
    mysql) container=omawsl-mysql ;;
    redis) container=omawsl-redis ;;
    postgresql) container=omawsl-postgresql ;;
    *) return 1 ;;
  esac
  if [[ "$_omawsl_doctor_storage_containers_cached" -eq 0 ]]; then
    _omawsl_doctor_storage_containers_cached=1
    if omawsl_docker_reachable; then
      _omawsl_doctor_storage_containers_cache="$(sudo -n docker ps -a --format '{{.Names}}' 2>/dev/null)" || true
    fi
  fi
  [[ -n "$_omawsl_doctor_storage_containers_cache" ]] && grep -qx "$container" <<< "$_omawsl_doctor_storage_containers_cache"
}

# omawsl_doctor_docker_proxy_pending [dir]
# True if Engine mode is active, a proxy is present in the environment,
# and omawsl hasn't (yet) configured the daemon for it - either the
# choice was made before this feature existed, or the environment's
# proxy changed since the last install.sh run. False (silent) once
# configured, once no proxy is present, or once another file already
# provides one - mirrors omawsl_configure_docker_proxy's own back-off
# logic exactly (design spec
# docs/superpowers/specs/2026-07-29-docker-daemon-proxy-autoconfig-design.md),
# since doctor only ever reports, it never writes anything itself.
omawsl_doctor_docker_proxy_pending() {
  local dir="${1:-${OMAWSL_DOCKER_SERVICE_D_DIR:-/etc/systemd/system/docker.service.d}}"
  [[ "$(omawsl_load_choice OMAWSL_DOCKER_MODE)" == "Docker Desktop for Windows" ]] && return 1
  local http_proxy_val https_proxy_val
  http_proxy_val="$(omawsl_detect_proxy_env HTTP_PROXY)"
  https_proxy_val="$(omawsl_detect_proxy_env HTTPS_PROXY)"
  [[ -n "$http_proxy_val" || -n "$https_proxy_val" ]] || return 1
  [[ -f "$dir/omawsl-proxy.conf" ]] && return 1
  omawsl_docker_proxy_conflict "$dir" "$dir/omawsl-proxy.conf" && return 1
  return 0
}

# omawsl_doctor_docker_proxy_stale [dir]
# True if omawsl's own proxy drop-in exists but no proxy is currently
# present in the environment - e.g. the machine moved off the corp
# network since the drop-in was written. omawsl never auto-removes this:
# a false positive (install.sh run from a shell that simply forgot to
# export the proxy vars) would silently break a working corp setup if
# acted on automatically, so this is report-only, same as
# omawsl_doctor_docker_proxy_pending.
omawsl_doctor_docker_proxy_stale() {
  local dir="${1:-${OMAWSL_DOCKER_SERVICE_D_DIR:-/etc/systemd/system/docker.service.d}}"
  [[ "$(omawsl_load_choice OMAWSL_DOCKER_MODE)" == "Docker Desktop for Windows" ]] && return 1
  [[ -f "$dir/omawsl-proxy.conf" ]] || return 1
  local http_proxy_val https_proxy_val
  http_proxy_val="$(omawsl_detect_proxy_env HTTP_PROXY)"
  https_proxy_val="$(omawsl_detect_proxy_env HTTPS_PROXY)"
  [[ -z "$http_proxy_val" && -z "$https_proxy_val" ]]
}

# omawsl_doctor_starship_missing
# Unlike zellij (never promised universal, just always installed in
# practice), starship is explicitly meant to be on every machine after
# design spec docs/superpowers/specs/2026-08-09-starship-default-prompt-design.md
# ships, so a silently failed install (offline box, corp proxy blocking
# GitHub) needs to surface somewhere - doctor is that somewhere.
#
# Deliberately its own `command -v starship` one-liner rather than
# reusing bin/omawsl-sub/orphan-tools.sh's near-identical
# omawsl_orphan_tool_installed starship case: that file is a much
# heavier dependency (it sources apps-terminal.sh plus 5 app-*.sh files
# and cloud-clis.sh just to get its own registry), and
# tests/omawsl_doctor_test.bats sources doctor.sh in isolation
# specifically so this file's own tests don't have to stub all of that
# too. Matches the precedent orphan-tools.sh's own
# omawsl_orphan_tool_installed comment already documents for the other 6
# non-always-on tools - same tradeoff, same direction, just made from
# doctor.sh's side of it this time.
omawsl_doctor_starship_missing() {
  ! command -v starship &>/dev/null
}

# omawsl_doctor_report_category <category> <check_fn> <choices_key>
# Reports every item in the category's registry that's either actually
# installed (regardless of whether it was ever selected through omawsl's
# own picker - e.g. pre-existing on the machine, or installed via
# `omawsl update`'s orphan-tool apply path, which bypasses the selection
# guard entirely, see install/terminal/app-opencode.sh) or selected but
# still missing. Items that are neither installed nor selected stay
# silent - matches the "additive only, nothing surprise-installs" design
# principle (design spec §14) by not nagging about tools nobody asked
# for. Originally this only cross-checked selected items and silently
# skipped anything else, which meant an already-installed-but-unselected
# tool (aws/opencode/node/gcloud in the field) never appeared at all,
# contradicting doctor's own "checking what's installed/configured"
# banner - see issue #4.
omawsl_doctor_report_category() {
  local category="$1" check_fn="$2" choices_key="$3"
  local selected; selected="$(omawsl_load_choice "$choices_key")"

  local slug label printed=0
  while IFS= read -r slug; do
    label="$(omawsl_item_label "$slug")"
    if "$check_fn" "$slug"; then
      echo "  [OK]      $label"
      printed=1
    elif omawsl_list_has "$selected" "$label"; then
      echo "  [PENDING] $label - run: omawsl install $category $slug"
      printed=1
    fi
  done < <(omawsl_item_slugs "$category")

  if [[ "$printed" -eq 0 ]]; then
    echo "  (none selected)"
  fi
}

# omawsl_doctor
# Entry point for `bin/omawsl doctor` (design spec §14).
omawsl_doctor() {
  echo "omawsl doctor - checking what's installed/configured:"
  echo
  echo "Languages:"
  omawsl_doctor_report_category language omawsl_doctor_language_installed OMAWSL_LANGUAGES
  echo
  echo "Cloud CLIs:"
  omawsl_doctor_report_category cloud omawsl_doctor_cloud_installed OMAWSL_CLOUD_CLIS
  echo
  echo "Editors & AI tooling:"
  omawsl_doctor_report_category editor omawsl_doctor_editor_installed OMAWSL_EDITORS
  echo
  echo "Storage:"
  omawsl_doctor_report_category storage omawsl_doctor_storage_installed OMAWSL_STORAGE

  if [[ "$(omawsl_load_choice OMAWSL_DOCKER_MODE)" == "Docker Desktop for Windows" ]] && ! omawsl_docker_reachable; then
    echo
    echo "Docker:"
    echo "  [PENDING] Docker Desktop for Windows - see docs/windows-setup.md#docker-desktop"
  elif omawsl_doctor_docker_proxy_pending; then
    echo
    echo "Docker:"
    echo "  [PENDING] Docker daemon proxy config - re-run install.sh to pick up your HTTP_PROXY/HTTPS_PROXY"
  elif omawsl_doctor_docker_proxy_stale; then
    echo
    echo "Docker:"
    echo "  [PENDING] Docker daemon proxy config looks stale - no HTTP_PROXY/HTTPS_PROXY is set in this shell, but omawsl-proxy.conf still exists. Off that network now? sudo rm <path-to-omawsl-proxy.conf> && sudo systemctl daemon-reload && sudo systemctl restart docker. Still on it? Export the proxy vars and re-run install.sh instead."
  fi

  if omawsl_doctor_starship_missing; then
    echo
    echo "Starship:"
    echo "  [PENDING] Starship not installed - prompt is using the legacy fallback. Re-run: omawsl update"
  fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_doctor
fi
