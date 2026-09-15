#!/usr/bin/env bash
# practice/04-editors-and-ai-tooling/editors.sh
#
# Rebuild a small version of install/terminal.sh's dispatch table plus
# three of the app-*.sh scripts it drives, from scratch. See
# docs/curriculum/04-editors-and-ai-tooling.md, section 3 (Exercise), for
# the exact fixed dispatch order, the OMAWSL_EDITORS labels, and the
# required behavior of each tool.
#
# This file is meant to be *executed* (bash editors.sh), same as every
# app-*.sh script in this project - it needs the same guard those scripts
# use at the bottom (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ...; fi`)
# so that running it directly dispatches all four tools, in order, but
# sourcing it (the way a test might, to reach individual pieces) does not
# auto-run anything.
#
# Reads:
#   OMAWSL_EDITORS - comma-delimited, may contain any subset of exactly
#     these four labels: "VS Code", "GitHub Copilot CLI", "Cursor",
#     "Neovim". Membership must be a whole-token match, not a bare
#     substring check.
#
# Fixed dispatch order (this order matters - the check depends on it):
#   1. vscode      - gated on "VS Code"
#   2. gh-copilot   - gated on "GitHub Copilot CLI"
#   3. cursor      - gated on "Cursor"
#   4. neovim      - gated on "Neovim"
#
# Required behavior per tool, when selected:
#   vscode:      cp baseline-settings.json (next to this file) to
#                $HOME/.vscode-server/data/Machine/settings.json
#                (mkdir -p any missing parent directories first).
#   cursor:      cp the SAME baseline-settings.json to
#                $HOME/.cursor-server/data/Machine/settings.json.
#   neovim:      if $HOME/.config/nvim does NOT already exist, call the
#                external command `neovim_installer` (no args). If it
#                DOES already exist, do not call neovim_installer at all.
#   gh-copilot:  call the external command `gh_copilot_installer` (no
#                args). This command can fail - isolate that failure so
#                cursor and neovim (scheduled after it) still run.
#
# TODO: implement the four tool functions, a dispatch table, and the
# guarded entry point described above.
