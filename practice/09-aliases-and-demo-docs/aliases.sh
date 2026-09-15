#!/usr/bin/env bash
# Exercise (lesson 9, Part 1): implement append_omakub_aliases below.
#
#   append_omakub_aliases <target-file>
#
# Appends a block of guarded Omakub-parity alias/function definitions to
# <target-file>, wrapped between two marker comment lines:
#
#   # >>> omawsl aliases >>>
#   ...
#   # <<< omawsl aliases <<<
#
# Must be idempotent: if <target-file> already contains the
# "# >>> omawsl aliases >>>" marker line, calling this function again must
# not append a second copy of the block.
#
# See lesson 9's Exercise section (docs/curriculum/09-aliases-and-demo-docs.md)
# for the full list of aliases/functions the block must define and their
# guard conditions.
#
# Define the function only - this file gets `source`d directly by
# check.sh, so don't call append_omakub_aliases unconditionally down here.
