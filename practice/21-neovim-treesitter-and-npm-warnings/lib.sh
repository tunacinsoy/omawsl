#!/usr/bin/env bash
# practice/21-neovim-treesitter-and-npm-warnings/lib.sh
#
# Part 1 of this phase's exercise (NOT automatically checked — see
# docs/curriculum/21-neovim-treesitter-and-npm-warnings.md, section 3).
# This installs real software via a real package manager in the original
# codebase, which practice exercises must never actually do for real, so
# there's no check.sh coverage for this file. Once you're done, compare it
# against install/lib.sh's omawsl_install_npm_cli_wrapper and
# install/terminal/app-neovim.sh's omawsl_install_treesitter_cli in the
# real repo, purely as a style comparison.
#
# This file is meant to be *sourced*, not executed directly - functions
# only, no top-level code, no auto-run dispatcher at the bottom.
#
# Functions to implement here:
#   - omawsl_install_npm_cli_wrapper <npm_package> <bin_name>
#   - omawsl_install_treesitter_cli

# omawsl_install_npm_cli_wrapper <npm_package> <bin_name>
# TODO: install <npm_package> globally via a private mise-managed Node
# runtime, then write an executable $HOME/.local/bin/<bin_name> wrapper
# that execs the tool through that same runtime, forwarding all
# arguments. A failed install must not leave a wrapper behind, and must
# make this function return non-zero.
omawsl_install_npm_cli_wrapper() {
  :
}

# omawsl_install_treesitter_cli
# TODO: install tree-sitter-cli via the helper above, guarded by an
# idempotency check for evidence THIS function's own fix has already
# been applied - not evidence that something merely answering to the
# name `tree-sitter` already exists somewhere on $PATH. See the
# Walkthrough for why that distinction matters here specifically.
omawsl_install_treesitter_cli() {
  :
}
