#!/usr/bin/env bash
set -euo pipefail

# TODO: omawsl_editor_picker_options
#
# The real first-run editor/AI-tooling picker prompt offers a fixed list of
# options. Google retired individual-account sign-in for Gemini CLI in
# favor of its Antigravity suite, so the picker swaps "Gemini CLI" out for
# "Antigravity CLI" - same slot in the list, same everything else about
# how the picker itself works.
#
# Implement this function to print the picker's option list, one option
# per line, in this exact order:
#   VS Code
#   Neovim
#   opencode
#   Cursor
#   Claude Code CLI
#   Codex CLI
#   GitHub Copilot CLI
#   Antigravity CLI
#
# (Not "Gemini CLI" - that option no longer exists in the picker.)
#
# omawsl_editor_picker_options() {
#   ...
# }
