#!/usr/bin/env bash
# Given — you do not need to change this file.
#
# A tiny slug<->label registry, the same shape as the real project's
# bin/omawsl-sub/items.sh, trimmed down to three items so the add/remove/
# doctor behavior you're building in cli.sh is easy to reason about and to
# check. In the real project this file is the single place that knows a
# slug's exact display label — install.sh, uninstall.sh, and doctor.sh all
# call into it instead of each spelling the label out themselves.

# omawsl_item_label <slug>
# Prints the exact label used in choices.env's comma-list and in doctor's
# report. Returns 1 for an unregistered slug.
omawsl_item_label() {
  case "$1" in
    go) echo "Go" ;;
    node) echo "Node.js" ;;
    vscode) echo "VS Code" ;;
    *) return 1 ;;
  esac
}

# omawsl_item_slugs
# Every registered slug, one per line, in a fixed display order. This is
# the order cli.sh's doctor report should walk — not the order items were
# added in.
omawsl_item_slugs() {
  printf '%s\n' go node vscode
}
