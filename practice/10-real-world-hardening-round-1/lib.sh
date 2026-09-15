#!/usr/bin/env bash
# lib.sh — pure, sourceable helper functions for this phase's exercise.
# No top-level code should run when this file is sourced; every
# behavior belongs inside a function.

# omawsl_docker_reachable
# Return 0 only if a `docker` command is on PATH *and* actually works —
# not just present. (Docker Desktop drops a `docker` shim onto every
# WSL distro's PATH even when that distro doesn't have WSL integration
# turned on for it; the shim prints a nudge to enable integration and
# exits non-zero rather than behaving like "command not found".) Return
# 1 in every other case: no `docker` on PATH at all, or `docker` present
# but non-functional.
#
# Fill in the implementation below this line.

# omawsl_atomic_replace <tmp_path> <dest_path>
# Replace dest_path's contents with tmp_path's contents, and remove
# tmp_path afterward — without ever invoking `mv`. (Across certain
# filesystem boundaries, `mv`'s fallback copy-then-preserve-metadata
# path calls syscalls the destination filesystem doesn't support,
# printing a scary but harmless warning on every call.) After a
# successful call: dest_path contains exactly what tmp_path contained
# before the call, and tmp_path no longer exists.
#
# Fill in the implementation below this line.
