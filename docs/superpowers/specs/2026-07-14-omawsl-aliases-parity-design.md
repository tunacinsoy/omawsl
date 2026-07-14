# omawsl aliases parity — design

**Date:** 2026-07-14
**Status:** approved
**Scope:** item 2 of the post-launch roadmap (item 1, the update mechanism, is done — see `docs/superpowers/plans/2026-07-13-omawsl-update-mechanism.md`).

## Why

omawsl mirrors Omakub's dev-environment setup, but `configs/bashrc` has never ported Omakub's actual shell aliases/functions/prompt (`basecamp/omakub`'s `defaults/bash/{aliases,functions,init,prompt,shell}`) — it only carries a handful of omawsl-original conveniences (bare `eza`/`bat` guards, a colored `PS1`). This closes that gap for the parts that make sense in a WSL2 context.

## Source material

Fetched directly from `basecamp/omakub` (`gh api repos/basecamp/omakub/contents/defaults/bash/...`) on 2026-07-14:

- `defaults/bash/aliases` — file-system, directory-nav, tool-shortcut, and git aliases.
- `defaults/bash/functions` — `compress`/`decompress`, `webm2mp4`, plus several GNOME-desktop-specific helpers (`web2app`, `app2folder`, `fix_fkeys`, `fix_spotify_window_size`) and `iso2sd` (raw SD-card writing).
- `defaults/bash/prompt` — the icon-only `PS1`.
- `defaults/bash/init` — mise/zoxide/fzf activation (omawsl's bashrc already has equivalents).
- `defaults/bash/shell` — history/PATH settings (omawsl's bashrc already has its own equivalents; not touched by this feature).

## Scope decisions

Confirmed with the user during brainstorming:

1. **In scope:** file-system + directory-nav aliases, tool-shortcut aliases, git aliases, the prompt, and `cd` override.
2. **Out of scope:** `defaults/bash/functions` entirely — `compress`/`decompress`/`webm2mp4` were explicitly declined (general-purpose, not requested); `web2app`/`app2folder`/`fix_fkeys`/`fix_spotify_window_size` fall under omawsl's existing "GNOME desktop-app layer is out of scope" exclusion (see `docs/superpowers/specs/2026-07-05-omawsl-design.md`); `iso2sd` doesn't map to WSL2 (no direct block-device access to a physical SD card).
3. **`cd='z'`:** full Omakub parity — `cd` itself is aliased to zoxide's `z`, not left as the plain builtin. Placed inside the existing `zoxide` guard block, right after `eval "$(zoxide init bash)"` (so `z` exists before it's aliased).
4. **`ls` flags:** full Omakub parity — `ls` itself changes to `eza -lh --group-directories-first --icons=auto` (long format, icons, folders-first), not a bare `eza`. `ll` (existing, `eza -la`) and the `else` no-eza fallback (`ll='ls -la'`) are unchanged. New: `lsa='ls -a'`, `lt='eza --tree --level=2 --long --icons --git'`, `lta='lt -a'` — `lsa`/`lta` deliberately reuse the `ls`/`lt` aliases recursively (relying on bash's alias-expansion-at-call-time, same trick Omakub's own file uses), not a second hardcoded eza invocation.
5. **Prompt:** full Omakub parity — replaces the current colored `user@host:path` `PS1` with Omakub's icon-only prompt (a single Nerd Font glyph, codepoint U+F0A9, written as the bash escape ``, followed by a space; path moves to the terminal tab title via `\[\e]0;\w\a\]`). Nerd Fonts are already a Phase 6 deliverable, so the glyph renders correctly.
6. **bat/fd naming bug fix:** confirmed via Debian package file listings (`packages.debian.org/sid/amd64/{bat,fd-find}/filelist`) that apt's `bat` package installs the binary as `batcat`, and `fd-find` installs `fdfind` — this is why Omakub's own aliases hardcode `batcat`/`fdfind` rather than `bat`/`fd`. omawsl's existing bashrc has a latent bug: it checks `command -v bat` (which is never true on Ubuntu), so the intended `alias cat='bat --paging=never'` has never actually activated. Fixed as part of this change: guard on `batcat`, alias `cat='batcat --paging=never'`. New `alias fd='fdfind'` (guarded on `fdfind`) and new `ff` (fzf + batcat preview, guarded on both `fzf` and `batcat`) follow the same fix.
7. **Guard style:** every new/changed alias stays guarded with `command -v <tool> &>/dev/null`, consistent with omawsl's existing bashrc style (not Omakub's own unguarded style) — degrades gracefully if a tool failed to install or (for `rails`) was never picked via the language picker, at the cost of a few extra lines per alias.

## Final `configs/bashrc` content (by section)

**Prompt** (replaces the current `PS1=...` line). `$' '` is a bash ANSI-C-quoted string — `` is the literal 4-hex-digit unicode escape, not a raw pasted glyph:
```bash
PS1=$' '
PS1="\[\e]0;\w\a\]$PS1"
```

**`ls` family** (extends the existing `eza` guard block):
```bash
if command -v eza &>/dev/null; then
  alias ls='eza -lh --group-directories-first --icons=auto'
  alias lsa='ls -a'
  alias ll='eza -la'
  alias lt='eza --tree --level=2 --long --icons --git'
  alias lta='lt -a'
  alias tree='eza --tree'
else
  alias ll='ls -la'
fi
```

**bat/fd/ff** (replaces the existing `bat` guard block):
```bash
if command -v batcat &>/dev/null; then
  alias cat='batcat --paging=never'
fi

if command -v fdfind &>/dev/null; then
  alias fd='fdfind'
fi

if command -v fzf &>/dev/null && command -v batcat &>/dev/null; then
  alias ff="fzf --preview 'batcat --style=numbers --color=always {}'"
fi
```

**zoxide** (extends the existing block):
```bash
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init bash)"
  alias cd='z'
fi
```

**Directory nav** (new, unconditional — `cd` always resolves, builtin or the `z` alias above):
```bash
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
```

**Tool shortcuts + git aliases** (new):
```bash
if command -v git &>/dev/null; then
  alias g='git'
  alias gcm='git commit -m'
  alias gcam='git commit -a -m'
  alias gcad='git commit -a --amend'
fi

if command -v docker &>/dev/null; then
  alias d='docker'
fi

if command -v rails &>/dev/null; then
  alias r='rails'
fi

if command -v lazygit &>/dev/null; then
  alias lzg='lazygit'
fi

if command -v lazydocker &>/dev/null; then
  alias lzd='lazydocker'
fi

if command -v nvim &>/dev/null; then
  n() { if [ "$#" -eq 0 ]; then nvim .; else nvim "$@"; fi; }
fi
```

Exact placement within the file (relative to the untouched `EDITOR`/`INPUTRC`/`mise`/PATH sections) is an implementation detail for the plan, not fixed here.

## Testing

`tests/a_shell_test.bats` already establishes the right pattern for this file: `bash "$REPO_ROOT/install/terminal/a-shell.sh"` to deploy, then `bash -i -c '...'` to exercise the interactive shell, `stub_hide_command <tool>` (from `tests/helpers/stubs.bash`) to simulate a tool being absent, isolated `$HOME` per test. Extend it with:

- Each new/changed alias present when its tool is on PATH, absent (no bare passthrough, no "command not found" surprise) when hidden via `stub_hide_command`.
- The `batcat`/`fdfind` naming fix specifically (this changes existing behavior, not just adds new aliases) — assert `cat` does NOT get aliased when only `bat` (not `batcat`) is hidden/faked, and DOES get aliased when a fake `batcat` is on PATH.
- The prompt: `PS1` contains the expected icon/title-escape sequence after sourcing.
- `cd='z'` only when `zoxide` is present; plain builtin `cd` otherwise (already implied by the existing `zoxide` guard, worth a direct assertion since this is new user-visible behavior).

## Non-scope / explicitly deferred

- `defaults/bash/functions` (`compress`, `decompress`, `webm2mp4`) — declined by the user, not part of this change. Not flagged for a future phase either; can be revisited if the user wants it later.
- `defaults/bash/shell`'s `HISTSIZE`/`HISTFILESIZE`/PATH values — omawsl's existing bashrc already has its own equivalents; untouched by this feature.
- No new files, no changes outside `configs/bashrc` and its test file.

## Implementation approach

Direct TDD on `master` (per the user's explicit choice) — no isolated worktree, no subagent-driven-development. Single file + single test file, additive/well-understood change, no cross-file surface to review.
