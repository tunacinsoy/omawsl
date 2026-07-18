#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=items.sh
source "$SCRIPT_DIR/items.sh"
# shellcheck source=../../install/terminal/apps-terminal.sh
source "$OMAWSL_ROOT_DIR/install/terminal/apps-terminal.sh"
# shellcheck source=../../install/terminal/app-opencode.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-opencode.sh"
# shellcheck source=../../install/terminal/app-claude-cli.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-claude-cli.sh"
# shellcheck source=../../install/terminal/app-codex-cli.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-codex-cli.sh"
# shellcheck source=../../install/terminal/app-gemini-cli.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-gemini-cli.sh"
# shellcheck source=../../install/terminal/app-gh-copilot.sh
source "$OMAWSL_ROOT_DIR/install/terminal/app-gh-copilot.sh"
# shellcheck source=../../install/terminal/cloud-clis.sh
source "$OMAWSL_ROOT_DIR/install/terminal/cloud-clis.sh"

# Registry + version-check adapters for omawsl's "orphan" tools - tools
# omawsl installs that have no native update command of their own (no
# apt/mise coverage), per
# docs/superpowers/specs/2026-07-13-omawsl-update-mechanism-design.md §3.
# Deliberately separate from items.sh: items.sh is the install/uninstall/
# doctor picker registry (language/editor/storage categories only);
# zellij and lazydocker are always-on, not picker targets, so they don't
# belong there.

# omawsl_orphan_tool_slugs
# All 8 orphan-tool slugs, in a fixed display order.
omawsl_orphan_tool_slugs() {
  printf '%s\n' zellij lazydocker opencode claude codex gemini gh-copilot aws
}

# omawsl_orphan_tool_label <slug>
# zellij/lazydocker aren't in items.sh (always-on, not a picker target),
# so they get their own labels here; the other 6 slugs are already
# registered there under the exact same slug names install/uninstall/
# doctor use - reused via omawsl_item_label rather than duplicating the
# same 6 label strings a second time.
omawsl_orphan_tool_label() {
  case "$1" in
    zellij) echo "Zellij" ;;
    lazydocker) echo "LazyDocker" ;;
    opencode|claude|codex|gemini|gh-copilot|aws) omawsl_item_label "$1" ;;
    *) return 1 ;;
  esac
}

# omawsl_orphan_tool_installed <slug>
# Is this orphan tool actually present right now? zellij/lazydocker get a
# direct command -v check (they're not in items.sh, so
# bin/omawsl-sub/doctor.sh's own per-slug checks don't cover them
# either); the other 6 repeat the same one-line checks doctor.sh and
# each tool's own install-script guard already use - this repo already
# has that exact check duplicated in at least two places per tool
# (app-codex-cli.sh's own guard, doctor.sh's omawsl_doctor_editor_installed),
# so a third one-line copy here matches existing precedent rather than
# reaching across into doctor.sh's file for a shared helper.
omawsl_orphan_tool_installed() {
  local slug="$1"
  case "$slug" in
    zellij) command -v zellij &>/dev/null ;;
    lazydocker) command -v lazydocker &>/dev/null ;;
    opencode) command -v opencode &>/dev/null ;;
    claude) command -v claude &>/dev/null ;;
    codex) command -v codex &>/dev/null ;;
    gemini) command -v gemini &>/dev/null ;;
    gh-copilot) gh extension list 2>/dev/null | grep -q 'github/gh-copilot' ;;
    aws) command -v aws &>/dev/null ;;
    *) return 1 ;;
  esac
}

# omawsl_orphan_extract_semver <text>
# Pulls the first X.Y.Z-shaped token out of arbitrary command output -
# shared by every "installed version" check below, since each tool's own
# --version output format differs (single line vs. multi-line, with or
# without a leading tool name) but all of them contain a plain semver
# token somewhere in the output.
omawsl_orphan_extract_semver() {
  grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<< "$1" | head -n1 || true
}

# omawsl_orphan_latest_from_github <owner/repo>
# Latest release tag from the public GitHub REST API, unauthenticated -
# this must work on a fresh machine before any `gh auth login` has
# happened (the exact same real constraint already documented for
# gh-copilot's own install in app-gh-copilot.sh). Empty output on any
# failure (network, rate limit, malformed JSON) rather than erroring -
# the caller (Task 3) is what bounds the wait, not this function itself.
omawsl_orphan_latest_from_github() {
  local repo="$1"
  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null)" || tag=""
  echo "${tag#v}"
}

# omawsl_orphan_latest_from_npm <package>
# Latest published version from the npm registry, via the same private
# mise-managed Node runtime app-codex-cli.sh/app-gemini-cli.sh already
# use to install these two tools (`mise exec node@lts`) - never a bare
# `npm`, which isn't guaranteed on PATH at all (design spec §5).
omawsl_orphan_latest_from_npm() {
  local package="$1"
  mise exec node@lts -- npm view "$package" version 2>/dev/null || echo ""
}

# omawsl_orphan_tool_version_installed <slug>
omawsl_orphan_tool_version_installed() {
  local slug="$1"
  case "$slug" in
    zellij) omawsl_orphan_extract_semver "$(zellij --version 2>/dev/null || true)" ;;
    lazydocker) omawsl_orphan_extract_semver "$(lazydocker --version 2>/dev/null || true)" ;;
    opencode) omawsl_orphan_extract_semver "$(opencode --version 2>/dev/null || true)" ;;
    claude) omawsl_orphan_extract_semver "$(claude --version 2>/dev/null || true)" ;;
    codex) omawsl_orphan_extract_semver "$(codex --version 2>/dev/null || true)" ;;
    gemini) omawsl_orphan_extract_semver "$(gemini --version 2>/dev/null || true)" ;;
    gh-copilot) omawsl_orphan_extract_semver "$(gh extension list 2>/dev/null | grep 'github/gh-copilot' || true)" ;;
    aws) omawsl_orphan_extract_semver "$(aws --version 2>/dev/null || true)" ;;
    *) return 1 ;;
  esac
}

# omawsl_orphan_tool_version_latest <slug>
# GitHub Releases API for the 6 binary/curl-script-distributed tools
# (repo slugs confirmed live: zellij-org/zellij, jesseduffield/lazydocker,
# anomalyco/opencode [formerly sst/opencode - GitHub redirects the old
# path], anthropics/claude-code, github/gh-copilot, aws/aws-cli); npm
# registry for the 2 tools installed via a private mise-managed Node
# runtime.
omawsl_orphan_tool_version_latest() {
  local slug="$1"
  case "$slug" in
    zellij) omawsl_orphan_latest_from_github zellij-org/zellij ;;
    lazydocker) omawsl_orphan_latest_from_github jesseduffield/lazydocker ;;
    opencode) omawsl_orphan_latest_from_github anomalyco/opencode ;;
    claude) omawsl_orphan_latest_from_github anthropics/claude-code ;;
    codex) omawsl_orphan_latest_from_npm "@openai/codex" ;;
    gemini) omawsl_orphan_latest_from_npm "@google/gemini-cli" ;;
    gh-copilot) omawsl_orphan_latest_from_github github/gh-copilot ;;
    aws) omawsl_orphan_latest_from_github aws/aws-cli ;;
    *) return 1 ;;
  esac
}

# omawsl_orphan_wait_with_timeout <pid> <limit_seconds>
# Polls a background pid every 0.1s, killing it once <limit_seconds> has
# elapsed. Deliberately a poll loop, not the external `timeout` command:
# `timeout cmd` execs `cmd` directly via a real binary lookup, invisible
# to this repo's export -f-based command stubbing (tests/helpers/stubs.bash)
# - a stubbed `curl` bash function would never be seen by a real `timeout`
# process. Returns 0 if the process exited on its own before the
# deadline, 1 if it had to be killed (caller treats that result as
# unknown/empty).
# NOTE: `waited=$((waited + 1))` (plain assignment) is used instead of the
# more idiomatic `((waited++))` on purpose: under this file's `set -e`,
# `((expr))` is a command whose exit status reflects the *result* of the
# expression, and post-increment evaluates to the OLD value - so on the
# very first iteration (waited=0) `((waited++))` evaluates to 0, which
# `set -e` treats as a command failure and aborts the function before it
# ever calls `wait`/returns 0. A plain arithmetic assignment has no such
# truthiness trap.
omawsl_orphan_wait_with_timeout() {
  local pid="$1" limit="$2"
  local waited=0 max_iterations=$((limit * 10))
  while kill -0 "$pid" 2>/dev/null; do
    if (( waited >= max_iterations )); then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null || true
  return 0
}

# omawsl_orphan_tools_check_versions <tmp_dir> <timeout_seconds> <slug...>
# Launches one background job per slug - each resolving both the
# installed and latest version and writing "installed<TAB>latest" to
# <tmp_dir>/<slug>.result - so the network-bound "latest" lookups run in
# parallel rather than one after another. Blocks until every job has
# either finished or been killed by omawsl_orphan_wait_with_timeout, so
# the total wait is bounded by a single shared <timeout_seconds> deadline
# computed once up front, not <timeout_seconds> restarted fresh for each
# job in the wait loop - the latter would let N simultaneously-hanging
# jobs degenerate the total wait to N * timeout_seconds. Each wait call
# instead gets whatever's left of that shared deadline (clamped to >= 0),
# so the loop's total wall-clock time converges to timeout_seconds
# regardless of how many jobs are hanging concurrently. A killed job
# leaves no result file behind (its own subshell never reached the
# `printf`), so this function backfills an empty/empty result for it - a
# wholesale timeout (as opposed to just the network half being slow) is
# rare enough that falling back to "everything unknown" for that one tool
# is an acceptable, clearly-labeled degradation.
omawsl_orphan_tools_check_versions() {
  local tmp_dir="$1" timeout_seconds="$2"; shift 2
  local slugs=("$@")
  local slug
  local pids=()
  for slug in "${slugs[@]}"; do
    (
      local installed latest
      installed="$(omawsl_orphan_tool_version_installed "$slug" 2>/dev/null || true)"
      latest="$(omawsl_orphan_tool_version_latest "$slug" 2>/dev/null || true)"
      printf '%s\t%s\n' "$installed" "$latest" > "$tmp_dir/$slug.result"
    ) &
    pids+=("$!")
  done
  local deadline=$(( $(date +%s) + timeout_seconds ))
  local i now remaining
  for i in "${!pids[@]}"; do
    now="$(date +%s)"
    remaining=$(( deadline - now ))
    (( remaining < 0 )) && remaining=0
    omawsl_orphan_wait_with_timeout "${pids[$i]}" "$remaining" || true
    [[ -f "$tmp_dir/${slugs[$i]}.result" ]] || printf '\t\n' > "$tmp_dir/${slugs[$i]}.result"
  done
}

# omawsl_orphan_tools_format_line <slug> <installed> <latest>
# One rendered status line for a single orphan tool, given its already-
# resolved installed/latest versions (empty string for either means
# "unknown" - a genuine lookup failure/timeout, not a real "0" version).
# Shared by the picker labels and (Task 9) the live-redraw status phase,
# so they can never drift out of sync with each other.
omawsl_orphan_tools_format_line() {
  local slug="$1" installed="$2" latest="$3"
  local label; label="$(omawsl_orphan_tool_label "$slug")"
  local status
  if [[ -z "$latest" ]]; then
    status="unknown"
  elif [[ "$installed" == "$latest" ]]; then
    status="up to date"
  else
    status="update available"
  fi
  printf '%-22s current: %-10s latest: %-10s (%s)' \
    "$label" "${installed:-unknown}" "${latest:-unknown}" "$status"
}

# omawsl_orphan_tool_apply_update <slug>
# Re-runs the given orphan tool's install steps, guard bypassed, so an
# already-installed tool gets a genuine fresh install/update rather than
# the no-op its normal command -v guard would otherwise produce.
# gh-copilot is the one exception: its own "steps" function for THIS
# purpose is omawsl_gh_copilot_update_steps (`gh extension upgrade`), not
# omawsl_gh_copilot_install_steps (`gh extension install`, which errors
# on an already-present extension rather than upgrading it - Task 7).
# Isolated per tool (cloud-tools.sh's own `{ ... } || ok=0` pattern) so
# one tool's failed update doesn't abort the rest of the selected
# updates or the overall omawsl update run.
omawsl_orphan_tool_apply_update() {
  local slug="$1"
  local label; label="$(omawsl_orphan_tool_label "$slug")"
  local ok=1
  case "$slug" in
    zellij) omawsl_zellij_install_steps || ok=0 ;;
    lazydocker) omawsl_lazydocker_install_steps || ok=0 ;;
    opencode) omawsl_opencode_install_steps || ok=0 ;;
    claude) omawsl_claude_cli_install_steps || ok=0 ;;
    codex) omawsl_codex_cli_install_steps || ok=0 ;;
    gemini) omawsl_gemini_cli_install_steps || ok=0 ;;
    gh-copilot) omawsl_gh_copilot_update_steps || ok=0 ;;
    aws) omawsl_aws_cli_install_steps || ok=0 ;;
    *) echo "omawsl: unknown orphan tool slug '$slug'" >&2; return 1 ;;
  esac
  if [[ "$ok" -eq 0 ]]; then
    echo "omawsl: failed to update $label - skipping, continuing with the rest."
  else
    echo "omawsl: updated $label."
  fi
}

# omawsl_orphan_tools_installed_slugs
# Which of the 8 orphan tools are actually installed right now, in
# registry order.
omawsl_orphan_tools_installed_slugs() {
  local slug
  while IFS= read -r slug; do
    omawsl_orphan_tool_installed "$slug" && echo "$slug"
  done < <(omawsl_orphan_tool_slugs)
  return 0
}

# omawsl_orphan_tools_live_check <tmp_dir> <timeout_seconds> <slug...>
# TTY-only companion to omawsl_orphan_tools_check_versions (Task 3):
# prints a "checking..." placeholder line per tool immediately, runs the
# real check via that same function in the background (reused as-is, not
# reimplemented - this function only adds a live terminal redraw on top),
# and redraws the whole block in place every 0.2s using tput cursor
# movement until the background check itself exits. `tput` calls are
# each `|| true`-guarded so a terminal that doesn't support cursor
# movement degrades to extra scrollback rather than an error.
omawsl_orphan_tools_live_check() {
  local tmp_dir="$1" timeout_seconds="$2"; shift 2
  local slugs=("$@")
  local slug label installed latest

  for slug in "${slugs[@]}"; do
    label="$(omawsl_orphan_tool_label "$slug")"
    printf '%-22s checking...\n' "$label"
  done

  omawsl_orphan_tools_check_versions "$tmp_dir" "$timeout_seconds" "${slugs[@]}" &
  local runner_pid=$!

  while kill -0 "$runner_pid" 2>/dev/null; do
    sleep 0.2
    tput cuu "${#slugs[@]}" 2>/dev/null || true
    for slug in "${slugs[@]}"; do
      tput el 2>/dev/null || true
      if [[ -f "$tmp_dir/$slug.result" ]]; then
        IFS=$'\t' read -r installed latest < "$tmp_dir/$slug.result"
        omawsl_orphan_tools_format_line "$slug" "$installed" "$latest"
        echo
      else
        label="$(omawsl_orphan_tool_label "$slug")"
        printf '%-22s checking...\n' "$label"
      fi
    done
  done
  wait "$runner_pid" 2>/dev/null || true

  tput cuu "${#slugs[@]}" 2>/dev/null || true
  for slug in "${slugs[@]}"; do
    tput el 2>/dev/null || true
    IFS=$'\t' read -r installed latest < "$tmp_dir/$slug.result"
    omawsl_orphan_tools_format_line "$slug" "$installed" "$latest"
    echo
  done
}

# omawsl_orphan_tools_update
# Entry point called from omawsl_update (bin/omawsl-sub/update.sh) after
# its existing self-update + migrate steps (design spec §4). No-ops
# cleanly if no orphan tool is installed. Uses the live-redraw status
# phase only when connected to a real terminal (design spec §6 - `gum
# choose` itself can't live-update rows once shown, so this is a
# separate phase before the picker, not part of it); bats' `run` never
# provides a real TTY, so tests always exercise the plain
# omawsl_orphan_tools_check_versions path deterministically, while a real
# interactive run gets the live "checking..." -> resolved-version redraw.
omawsl_orphan_tools_update() {
  local slugs=() slug
  while IFS= read -r slug; do slugs+=("$slug"); done < <(omawsl_orphan_tools_installed_slugs)

  if [[ "${#slugs[@]}" -eq 0 ]]; then
    echo "omawsl: no orphan tools installed - nothing to check."
    return 0
  fi

  local tmp_dir; tmp_dir="$(mktemp -d)"
  if [[ -t 1 ]]; then
    omawsl_orphan_tools_live_check "$tmp_dir" 5 "${slugs[@]}"
  else
    omawsl_orphan_tools_check_versions "$tmp_dir" 5 "${slugs[@]}"
  fi

  local any_available=0 any_unknown=0
  local options=() selected=()
  for slug in "${slugs[@]}"; do
    local installed latest line
    IFS=$'\t' read -r installed latest < "$tmp_dir/$slug.result"
    line="$(omawsl_orphan_tools_format_line "$slug" "$installed" "$latest")"
    options+=("$line")
    if [[ -z "$latest" ]]; then
      any_unknown=1
    elif [[ "$installed" != "$latest" ]]; then
      any_available=1
      selected+=("$line")
    fi
  done
  rm -rf "$tmp_dir"

  if [[ "$any_available" -eq 0 && "$any_unknown" -eq 0 ]]; then
    echo "omawsl: everything is already up to date."
    return 0
  fi

  local preselected=""
  if [[ "${#selected[@]}" -gt 0 ]]; then
    preselected="$(printf '%s\n' "${selected[@]}" | paste -sd, -)"
  fi

  local picked
  picked="$(gum choose --no-limit --selected "$preselected" --header "Update orphan tools (no native updater of their own)" "${options[@]}")" || picked=""
  [[ -n "$picked" ]] || return 0

  local chosen_line
  while IFS= read -r chosen_line; do
    [[ -z "$chosen_line" ]] && continue
    for slug in "${slugs[@]}"; do
      if [[ "$chosen_line" == "$(omawsl_orphan_tool_label "$slug")"* ]]; then
        omawsl_orphan_tool_apply_update "$slug"
        break
      fi
    done
  done <<< "$picked"
}
