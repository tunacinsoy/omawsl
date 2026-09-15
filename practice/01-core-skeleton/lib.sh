#!/usr/bin/env bash
# practice/01-core-skeleton/lib.sh
#
# Rebuild install/lib.sh's shared helpers from scratch. See
# docs/curriculum/01-core-skeleton.md, section 3 (Exercise), for the exact
# function names, argument orders, and required behavior of each one.
#
# This file is meant to be *sourced*, not executed directly - it should
# define functions only, with no top-level code that runs on its own, and
# no auto-run dispatcher at the bottom (compare to a script like
# app-gum.sh, which does have one - lib.sh never did, since nothing here
# should "run" by itself).
#
# Functions to implement here:
#   - omawsl_version_ge <version> <minimum>
#   - omawsl_list_has <comma_delimited_list> <item>
#   - omawsl_is_wsl2_kernel <kernel_release_string>
#   - omawsl_is_wsl2
#   - omawsl_choices_dir
#   - omawsl_save_choice <key> <value>
#   - omawsl_load_choice <key>
#
# TODO: implement each function described above.
