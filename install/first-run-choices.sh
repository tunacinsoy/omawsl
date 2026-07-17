#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

omawsl_prompt_single() {
  local header="$1"; shift
  gum choose --header "$header" "$@"
}

# omawsl_prompt_multi <header> <options...>
# Nothing is pre-selected by default (design spec §6/§12: a public tool
# should not surprise-install anything the user didn't explicitly ask for).
# Joins multiple picks into a single comma-delimited string, since
# `gum choose --no-limit` emits one selection per line.
omawsl_prompt_multi() {
  local header="$1"; shift
  gum choose --no-limit --header "$header" "$@" | paste -sd, -
}

omawsl_first_run_choices() {
  OMAWSL_NETWORK_MODE="$(omawsl_prompt_single "Are you on a corporate/restricted network?" \
    "Corporate / restricted network" "Personal / unrestricted")"

  OMAWSL_DOCKER_MODE="$(omawsl_prompt_single "Docker: how should it be set up?" \
    "Docker Engine only, inside WSL (recommended)" "Docker Desktop for Windows")"

  OMAWSL_EDITORS="$(omawsl_prompt_multi "Editors & AI tooling (space to select, enter to confirm)" \
    "VS Code" "Neovim" "opencode" "Cursor" \
    "Claude Code CLI" "Codex CLI" "GitHub Copilot CLI" "Gemini CLI")"

  OMAWSL_LANGUAGES="$(omawsl_prompt_multi "Languages & cloud tools" \
    "Ruby on Rails" "Node.js" "Go" "PHP" "Python" "Elixir" "Rust" "Java" \
    "Terraform")"

  OMAWSL_CLOUD_CLIS="$(omawsl_prompt_multi "Cloud CLIs" \
    "Azure CLI" "AWS CLI" "GCP CLI")"

  OMAWSL_STORAGE="$(omawsl_prompt_multi "Storage (Docker containers)" \
    "MySQL" "Redis" "PostgreSQL")"

  # Neither option is "correct" (docs/windows-setup.md#fonts) - deliberately
  # not inferred from OMAWSL_NETWORK_MODE, since corporate-network
  # restriction and Nerd Font availability don't actually correlate (a corp
  # machine can still have one via IT policy; a personal machine's user
  # might just not bother installing one). Labels match that doc's own
  # option names exactly, since this choice only ever means "which one did
  # you merge into Windows Terminal" - configs/bashrc reads it back to pick
  # an icon-glyph prompt vs a plain user@host:path one, so a Nerd-Font-less
  # terminal doesn't render the icon as a tofu box.
  OMAWSL_FONT_MODE="$(omawsl_prompt_single "Which font did you set up in Windows Terminal? (docs/windows-setup.md#fonts)" \
    "Nerd Font (enhanced)" "Cascadia Mono (zero install)")"

  export OMAWSL_NETWORK_MODE OMAWSL_DOCKER_MODE OMAWSL_EDITORS OMAWSL_LANGUAGES OMAWSL_CLOUD_CLIS OMAWSL_STORAGE OMAWSL_FONT_MODE

  omawsl_save_choice OMAWSL_NETWORK_MODE "$OMAWSL_NETWORK_MODE"
  omawsl_save_choice OMAWSL_DOCKER_MODE "$OMAWSL_DOCKER_MODE"
  omawsl_save_choice OMAWSL_EDITORS "$OMAWSL_EDITORS"
  omawsl_save_choice OMAWSL_LANGUAGES "$OMAWSL_LANGUAGES"
  omawsl_save_choice OMAWSL_CLOUD_CLIS "$OMAWSL_CLOUD_CLIS"
  omawsl_save_choice OMAWSL_STORAGE "$OMAWSL_STORAGE"
  omawsl_save_choice OMAWSL_FONT_MODE "$OMAWSL_FONT_MODE"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_first_run_choices
fi
