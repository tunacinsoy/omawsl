#!/usr/bin/env bash
# practice/21-neovim-treesitter-and-npm-warnings/npm-filter.sh
#
# Part 2 of this phase's exercise (checked by check.sh in this directory).
# See docs/curriculum/21-neovim-treesitter-and-npm-warnings.md, section 3,
# for the exact required behavior.
#
# This file is meant to be *sourced*, not executed directly - it should
# define the function below only, with no top-level code and no auto-run
# dispatcher at the bottom. check.sh sources this file and pipes canned
# sample npm output through the function by name - no real npm or mise
# command ever runs as part of the check.

# omawsl_filter_allow_scripts_warning
# TODO: read npm's captured install output from stdin. Write every line
# to stdout EXCEPT lines that are the allow-scripts advisory - i.e. lines
# beginning with the literal prefix "npm warn allow-scripts". Every other
# line (including unrelated npm warnings and ordinary success output)
# must pass through unchanged, in its original order. Must exit 0 even
# if every input line matches and gets filtered out.
omawsl_filter_allow_scripts_warning() {
  :
}
