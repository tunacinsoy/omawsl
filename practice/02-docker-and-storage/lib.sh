#!/usr/bin/env bash
set -euo pipefail

# omawsl_list_has <comma_delimited_list> <item>
# Carried over from Lesson 1 as given infrastructure - this phase's storage
# picker (select-dev-storage.sh) depends on it, but it isn't new material
# for this lesson, so it's implemented for you here.
omawsl_list_has() {
  local list="$1" item="$2"
  [[ ",$list," == *",$item,"* ]]
}

# omawsl_docker_reachable
# TODO(Lesson 2): implement this.
#
# True (exit 0) if a `docker` command is already reachable on PATH, false
# (exit 1) otherwise. See the lesson's Walkthrough for why this lives here
# as a shared helper rather than inside docker.sh - two different scripts
# in this phase both need to ask the same question.
