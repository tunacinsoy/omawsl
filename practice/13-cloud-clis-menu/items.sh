#!/usr/bin/env bash
set -euo pipefail

# Given, as of the START of this lesson - this is a trimmed copy of the
# real project's bin/omawsl-sub/items.sh, frozen at the state it was in
# right before this phase: a shared slug<->label registry, one flat
# namespace, so install/uninstall/doctor code never has to spell out a
# slug's category or display label itself - they all call into this file
# instead.
#
# Right now Azure CLI ("azure") is filed under "language", alongside
# Terraform - a leftover from when the only cloud-provider CLI this
# project supported lived in the same picker as the 8 programming
# languages. Your job in this lesson (see docs/curriculum/13-cloud-clis-menu.md,
# section 3) is to edit this file in place:
#
#   1. Move "azure" OUT of the "language" arm of omawsl_item_category.
#   2. Add a new "cloud" arm: azure|aws|gcp -> "cloud".
#   3. Add labels for the two new slugs to omawsl_item_label:
#        aws -> "AWS CLI"
#        gcp -> "GCP CLI"
#      ("azure" already has its label below - it isn't changing, only
#      its category is.)
#   4. In omawsl_item_slugs, remove "azure" from the "language" case
#      and add a new "cloud" case: azure aws gcp (in that order).
#
# "language" keeps "terraform" - it isn't moving. Only Azure CLI moves,
# and two brand-new slugs (aws, gcp) join it in the new category.

# omawsl_item_category <slug>
omawsl_item_category() {
  case "$1" in
    go|terraform|azure) echo "language" ;;
    vscode) echo "editor" ;;
    *) return 1 ;;
  esac
}

# omawsl_item_label <slug>
# The exact string used in a picker's comma-delimited selection list and
# passed to each uninstall function - must match the real picker's own
# option strings verbatim.
omawsl_item_label() {
  case "$1" in
    go) echo "Go" ;;
    terraform) echo "Terraform" ;;
    azure) echo "Azure CLI" ;;
    vscode) echo "VS Code" ;;
    *) return 1 ;;
  esac
}

# omawsl_item_slugs <category>
# All slugs for one category, in picker order.
omawsl_item_slugs() {
  case "$1" in
    language) printf '%s\n' go terraform azure ;;
    editor) printf '%s\n' vscode ;;
    *) return 1 ;;
  esac
}
