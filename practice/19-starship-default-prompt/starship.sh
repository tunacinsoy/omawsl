#!/usr/bin/env bash
# Lesson 19: starship as the default prompt.
#
# This file is a library of functions, not a CLI — nothing at the bottom
# dispatches on argv. The check script sources it directly and calls each
# function itself. Implement the four TODOs below; see
# docs/curriculum/19-starship-default-prompt.md for the walkthrough and
# what each one is for.
set -euo pipefail

# omawsl_starship_asset
# Echo the correct starship release asset filename for the current
# machine's CPU architecture, as reported by `uname -m`. starship's
# GitHub releases publish:
#   - x86_64  -> starship-x86_64-unknown-linux-gnu.tar.gz   (glibc build)
#   - aarch64 -> starship-aarch64-unknown-linux-musl.tar.gz (musl build —
#                starship publishes no aarch64-unknown-linux-gnu asset)
# Any other architecture should fall back to the x86_64 gnu name.
omawsl_starship_asset() {
  # TODO
  :
}

# omawsl_starship_install_steps
# Download the release asset omawsl_starship_asset names from starship's
# GitHub releases, extract the `starship` binary from the tarball, and
# install it to /usr/local/bin/starship. No guard here (that belongs in a
# separate wrapper, not required for this exercise) — this function
# always performs the install.
#
# This is the dangerous, non-$HOME-relative half of the lesson: a real
# network call, and a real write outside $HOME via sudo. Nothing about a
# HOME override contains either of those, so implement it with plain
# `curl`, `tar`, and `sudo install` calls — the check script intercepts
# those three commands itself before calling this function.
omawsl_starship_install_steps() {
  # TODO
  :
}

# omawsl_write_starship_theme <name> <red> <green> <blue> <yellow> \
#   <magenta> <orange> <cyan> <black> <white> <bg> <fg>
# Write a themed starship config to $HOME/.config/starship.toml:
#   - a line selecting the palette:      palette = "<name>"
#   - a section defining it:             [palettes.<name>]
#   - one `key = "value"` line per color inside that section, using
#     starship's own palette key names (red, green, blue, yellow,
#     magenta, orange, cyan, black, white, bg, fg).
# Always overwrite unconditionally — this mirrors `omawsl theme <name>`,
# an explicit user action, not a passive install-time default.
omawsl_write_starship_theme() {
  # TODO
  :
}

# omawsl_ensure_starship_bashrc_line
# Idempotently make sure $HOME/.bashrc invokes starship:
#   eval "$(starship init bash)"
# positioned AFTER any existing `mise activate bash` line (mise mutates
# PATH/env that starship's language-version modules need to read
# already-updated on every prompt render — see the lesson's Concept
# section for why the order matters).
#
# Must:
#   - create ~/.bashrc if it doesn't exist yet
#   - not add a second starship init line if one is already present
#   - not crash if there's no mise activation line to anchor after (just
#     add the starship line somewhere sensible, e.g. the end of the file)
omawsl_ensure_starship_bashrc_line() {
  # TODO
  :
}
