# Migrations

Each file here is named `<unix-timestamp>.sh` and holds a one-off fix for a
breaking change introduced by omawsl itself between releases (e.g. a config
file that moved, a renamed mise tool) - never for upstream Ubuntu/apt changes
on their own.

`bin/omawsl migrate` (Phase 7) compares the timestamp recorded in
`~/.local/state/omawsl/version` against every file here, and runs only the
ones with a greater timestamp. There is no other tracking file - the
timestamp comparison is the only source of truth (matching Omakub's own
migration convention).

This directory is no longer empty: `1785266018.sh` handles the one-time
transition off the old `cp`-based `~/.bashrc`/`~/.inputrc` model (see
`docs/config-safety.md`). Future breaking changes each get their own new
`<unix-timestamp>.sh` file alongside it, following the same convention.
