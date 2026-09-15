#!/usr/bin/env bash
set -euo pipefail

# practice/08-self-update-mechanism/orphan-tools.sh
#
# Rebuild the orphan-tool registry, version-check adapters, and
# bounded-wait parallel runner described in
# docs/curriculum/08-self-update-mechanism.md's Exercise section.
#
# This file should end up containing only function definitions - no
# unconditional dispatcher, no code that runs just by sourcing the file.
# practice/08-self-update-mechanism/check.sh sources this file directly
# and calls the functions below by name, so their names/arguments have to
# match what the lesson's Exercise section specifies even though your
# implementation doesn't have to look anything like the original.
#
# Functions to implement (see the lesson for full detail on each):
#
# Registry:
#   omawsl_orphan_tool_slugs
#   omawsl_orphan_tool_label <slug>
#   omawsl_orphan_tool_installed <slug>
#
# Version-check adapters:
#   omawsl_orphan_extract_semver <text>
#   omawsl_orphan_latest_from_github <owner/repo>
#   omawsl_orphan_latest_from_npm <package>
#   omawsl_orphan_tool_version_installed <slug>
#   omawsl_orphan_tool_version_latest <slug>
#
# Display:
#   omawsl_orphan_tools_format_line <slug> <installed> <latest>
#
# Bounded-wait parallel runner:
#   omawsl_orphan_wait_with_timeout <pid> <limit_seconds>
#   omawsl_orphan_tools_check_versions <tmp_dir> <timeout_seconds> <slug...>
