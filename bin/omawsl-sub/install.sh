#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OMAWSL_ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../../install/lib.sh
source "$OMAWSL_ROOT_DIR/install/lib.sh"
# shellcheck source=items.sh
source "$SCRIPT_DIR/items.sh"

# omawsl_install_prompt_multi <header> <preselected_csv> <options...>
# Same shape as install/first-run-choices.sh's omawsl_prompt_multi, plus
# gum choose's --selected flag (verified live to accept a comma-list of
# labels to pre-check) so already-installed items show pre-checked, per
# design spec §14's "no-args" picker behavior.
omawsl_install_prompt_multi() {
  local header="$1" preselected="$2"; shift 2
  gum choose --no-limit --selected "$preselected" --header "$header" "$@" | paste -sd, -
}

# omawsl_install_apply_language <picked_labels_csv> <existing_labels_csv>
omawsl_install_apply_language() {
  local picked="$1" existing="$2"
  local merged; merged="$(omawsl_merge_csv "$existing" "$picked")"
  export OMAWSL_LANGUAGES="$merged"
  omawsl_save_choice OMAWSL_LANGUAGES "$merged"
  # shellcheck source=/dev/null
  source "$OMAWSL_ROOT_DIR/install/terminal/select-dev-language.sh"
  # shellcheck source=/dev/null
  source "$OMAWSL_ROOT_DIR/install/terminal/cloud-tools.sh"
  omawsl_select_dev_language
  omawsl_cloud_tools
}

# omawsl_install_apply_editor <picked_labels_csv> <existing_labels_csv>
omawsl_install_apply_editor() {
  local picked="$1" existing="$2"
  local merged; merged="$(omawsl_merge_csv "$existing" "$picked")"
  export OMAWSL_EDITORS="$merged"
  omawsl_save_choice OMAWSL_EDITORS "$merged"
  local f
  for f in app-vscode app-neovim app-opencode app-cursor app-claude-cli app-codex-cli app-gh-copilot app-antigravity-cli; do
    # shellcheck source=/dev/null
    source "$OMAWSL_ROOT_DIR/install/terminal/$f.sh"
  done
  omawsl_install_vscode
  omawsl_install_neovim
  omawsl_install_opencode
  omawsl_install_cursor
  omawsl_install_claude_cli
  omawsl_install_codex_cli
  omawsl_install_gh_copilot
  omawsl_install_antigravity_cli
}

# omawsl_install_apply_storage <picked_labels_csv> <existing_labels_csv>
omawsl_install_apply_storage() {
  local picked="$1" existing="$2"
  local merged; merged="$(omawsl_merge_csv "$existing" "$picked")"
  export OMAWSL_STORAGE="$merged"
  omawsl_save_choice OMAWSL_STORAGE "$merged"
  # shellcheck source=/dev/null
  source "$OMAWSL_ROOT_DIR/install/terminal/select-dev-storage.sh"
  omawsl_install_storage
}

# omawsl_install_apply_cloud <picked_labels_csv> <existing_labels_csv>
omawsl_install_apply_cloud() {
  local picked="$1" existing="$2"
  local merged; merged="$(omawsl_merge_csv "$existing" "$picked")"
  export OMAWSL_CLOUD_CLIS="$merged"
  omawsl_save_choice OMAWSL_CLOUD_CLIS "$merged"
  # shellcheck source=/dev/null
  source "$OMAWSL_ROOT_DIR/install/terminal/cloud-clis.sh"
  omawsl_cloud_clis
}

# omawsl_install_category_language
omawsl_install_category_language() {
  local existing; existing="$(omawsl_load_choice OMAWSL_LANGUAGES)"
  local labels=() slug
  while IFS= read -r slug; do labels+=("$(omawsl_item_label "$slug")"); done < <(omawsl_item_slugs language)
  local picked
  picked="$(omawsl_install_prompt_multi "Languages & cloud tools (already-installed items are pre-checked)" "$existing" "${labels[@]}")" || picked=""
  omawsl_install_apply_language "$picked" "$existing"
}

# omawsl_install_category_editor
omawsl_install_category_editor() {
  local existing; existing="$(omawsl_load_choice OMAWSL_EDITORS)"
  local labels=() slug
  while IFS= read -r slug; do labels+=("$(omawsl_item_label "$slug")"); done < <(omawsl_item_slugs editor)
  local picked
  picked="$(omawsl_install_prompt_multi "Editors & AI tooling (already-installed items are pre-checked)" "$existing" "${labels[@]}")" || picked=""
  omawsl_install_apply_editor "$picked" "$existing"
}

# omawsl_install_category_storage
omawsl_install_category_storage() {
  local existing; existing="$(omawsl_load_choice OMAWSL_STORAGE)"
  local labels=() slug
  while IFS= read -r slug; do labels+=("$(omawsl_item_label "$slug")"); done < <(omawsl_item_slugs storage)
  local picked
  picked="$(omawsl_install_prompt_multi "Storage (already-installed items are pre-checked)" "$existing" "${labels[@]}")" || picked=""
  omawsl_install_apply_storage "$picked" "$existing"
}

# omawsl_install_category_cloud
omawsl_install_category_cloud() {
  local existing; existing="$(omawsl_load_choice OMAWSL_CLOUD_CLIS)"
  local labels=() slug
  while IFS= read -r slug; do labels+=("$(omawsl_item_label "$slug")"); done < <(omawsl_item_slugs cloud)
  local picked
  picked="$(omawsl_install_prompt_multi "Cloud CLIs (already-installed items are pre-checked)" "$existing" "${labels[@]}")" || picked=""
  omawsl_install_apply_cloud "$picked" "$existing"
}

# omawsl_install_direct <category> <slug>
omawsl_install_direct() {
  local category="$1" slug="$2"
  local item_category
  if ! item_category="$(omawsl_item_category "$slug")"; then
    echo "omawsl: unknown item '$slug'" >&2
    return 1
  fi
  if [[ "$item_category" != "$category" ]]; then
    echo "omawsl: '$slug' isn't in the '$category' category (it's '$item_category')" >&2
    return 1
  fi

  local label; label="$(omawsl_item_label "$slug")"
  case "$category" in
    language) omawsl_install_apply_language "$label" "$(omawsl_load_choice OMAWSL_LANGUAGES)" ;;
    cloud)    omawsl_install_apply_cloud    "$label" "$(omawsl_load_choice OMAWSL_CLOUD_CLIS)" ;;
    editor)   omawsl_install_apply_editor   "$label" "$(omawsl_load_choice OMAWSL_EDITORS)" ;;
    storage)  omawsl_install_apply_storage  "$label" "$(omawsl_load_choice OMAWSL_STORAGE)" ;;
  esac
}

# omawsl_install_interactive
# The no-args path (design spec §14): pick a category, then that
# category's own multi-select re-appears with already-installed items
# pre-checked.
omawsl_install_interactive() {
  local category
  category="$(gum choose --header "What do you want to add?" "Language/tool" "Cloud CLIs" "Editors & AI tooling" "Storage")" || category=""
  [[ -n "$category" ]] || return 0
  case "$category" in
    "Language/tool")         omawsl_install_category_language ;;
    "Cloud CLIs")            omawsl_install_category_cloud ;;
    "Editors & AI tooling")  omawsl_install_category_editor ;;
    "Storage")               omawsl_install_category_storage ;;
  esac
}

# omawsl_install_command [category] [item]
# Entry point for `bin/omawsl install [category] [item]` (design spec
# §14). Category names here are the human words used in the interactive
# picker's own choices ("language", "cloud", "editor", "storage"), matching the
# spec's own examples ("install language go", "install editor vscode").
omawsl_install_command() {
  local category="${1:-}" item="${2:-}"

  if [[ -z "$category" ]]; then
    omawsl_install_interactive
    return
  fi

  if [[ -z "$item" ]]; then
    echo "Usage: omawsl install [category] [item]" >&2
    echo "Categories: language, cloud, editor, storage" >&2
    return 1
  fi

  case "$category" in
    language|cloud|editor|storage) omawsl_install_direct "$category" "$item" ;;
    *)
      echo "omawsl: unknown category '$category' (expected language, cloud, editor, or storage)" >&2
      return 1
      ;;
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_command "$@"
fi
