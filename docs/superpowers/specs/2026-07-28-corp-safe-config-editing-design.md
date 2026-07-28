# Corp-safe config editing policy — design

**Date:** 2026-07-28
**Status:** approved
**Scope:** how omawsl is allowed to touch files that a corporate IT policy, a company-specific WSL2 setup manual, or the user's own hand edits might also manage.

## Why

Corporate WSL2 setups typically follow a company-specific manual that edits a fixed list of files:
`/etc/wsl.conf`, `/etc/systemd/resolved.conf`, `~/.curlrc`, `/etc/apt/apt.conf.d/proxy`,
`/etc/profile.d/proxy.sh`, `/etc/zsh/zshenv`, `/etc/sudoers`, `~/.m2/settings.xml`, `~/.zshrc`,
`~/.oh-my-zsh/custom/aliases.zsh`, `~/.git-templates/hooks/prepare-commit-msg`,
`~/.config/direnv/direnvrc`, `/etc/systemd/system/wsl-vpnkit.service`, and
`/etc/systemd/system/docker.service.d/http-proxy.conf`. The exact list varies company to company,
so omawsl can't special-case any one company's manual — it needs a general rule that keeps its
hands off files like these regardless of what's in them.

Auditing the current codebase against that list found:

- omawsl doesn't touch most of these files at all today.
- The one real overlap is `/etc/wsl.conf`'s `[boot] systemd=true` line, set by
  `install/terminal/docker.sh`. It's already handled reasonably safely (content-checked, appended
  only if missing), just not as robustly as it could be.
- The one genuinely fragile pattern in the repo is `install/terminal/a-shell.sh`, which
  `cp`-overwrites `~/.bashrc` and `~/.inputrc` wholesale on every install and every re-run,
  discarding anything already there. No corp manual in scope targets these two files directly
  today, but this is the pattern most likely to collide with some other company's manual
  tomorrow, and it's worth fixing on general principle regardless.

This design generalizes the fix into a policy, applies it to the current `.bashrc`/`.inputrc`
pattern, hardens the existing `wsl.conf` append, and adds a documented + tested list of files
omawsl must never create or modify.

## Policy

omawsl never writes its own content directly into a file it doesn't exclusively own. Content
omawsl needs to provide lives in files under its own tree (the repo checkout at `$OMAWSL_HOME`,
default `$HOME/.local/share/omawsl`) and is freely rewritten there — omawsl is the sole owner.
Touching a shared file happens only through the smallest possible, idempotent, content-checked
addition, preferring in this order:

1. **The format's own drop-in mechanism**, if one exists (`/etc/profile.d/*`,
   `/etc/apt/apt.conf.d/*`, `/etc/sudoers.d/*`, a systemd `*.conf.d/` override directory).
2. **A single guarded include/source line**, added to the shared file only if not already
   present, for formats that support sourcing (shell rc files).
3. **A content-based check-then-append**, for formats with neither — used only for
   `/etc/wsl.conf`, which WSL reads as a single file with no override mechanism.

In every case: check for existing content before writing, never assume the file is empty or
omawsl-owned, and never remove or reorder content omawsl didn't itself add.

This is documented in a new `docs/config-safety.md`, which also carries the never-touch list
from the last section below — something a reader can point their own IT/security review at.

## Components

### 1. `~/.bashrc` — marker-guarded source line, not a copy

`install/terminal/a-shell.sh` stops `cp`-ing `configs/bashrc` into `~/.bashrc`. Instead:

- `configs/bashrc` stays in the repo checkout. omawsl never writes it anywhere else — it's
  sourced directly from `$OMAWSL_HOME/configs/bashrc`, so `omawsl update`'s `git pull` alone is
  enough to update its behavior in future shells, with no separate copy/install step.
- `~/.bashrc` receives exactly one addition, appended only if the marker isn't already present:

  ```bash
  # >>> omawsl >>>
  [ -f "$HOME/.local/share/omawsl/configs/bashrc" ] && source "$HOME/.local/share/omawsl/configs/bashrc"
  # <<< omawsl <<<
  ```

  The path is resolved to the real, absolute `$OMAWSL_HOME` at install time (same resolution
  `apps-terminal.sh`'s `omawsl_install_cli` already does for `root_dir`), not left as a literal
  env-var reference, since `$OMAWSL_HOME` won't be exported in the future shells that read this
  file.
- Everything else already in `~/.bashrc` — corp-added lines, hand edits, content from a previous
  omawsl version — is left exactly as-is, on first install and on every re-run.
- Non-goal: this design does not maintain a live-replaceable block. If `$OMAWSL_HOME` ever moves
  (the env var override exists mainly for tests; the real default path is stable), the existing
  marker line is left pointing at the old path rather than rewritten in place. Detecting and
  replacing an existing marker block is exactly the added complexity Approach 2 (marker-block
  ownership) would have required across every file type, deliberately avoided in favor of a
  single append-once check.

### 2. `~/.inputrc` — never written; `INPUTRC` fallback instead

`~/.inputrc` is no longer created by omawsl at all. `configs/bashrc`'s existing
`if [ -f ~/.inputrc ]; then export INPUTRC=~/.inputrc; fi` block (written for the old
copy-then-use model) is replaced with:

```bash
if [ -z "${INPUTRC:-}" ] && [ ! -f "$HOME/.inputrc" ]; then
  export INPUTRC="$HOME/.local/share/omawsl/configs/inputrc"
fi
```

If the user (or a corp manual) already has their own `~/.inputrc`, or `INPUTRC` is already set,
omawsl's own `configs/inputrc` is never referenced and the pre-existing one wins via readline's
normal lookup — omawsl never touches the file.

### 3. Migration for existing installs

Existing installs already have the *old* full-content `.bashrc`/`.inputrc` written by `cp`. A new
`migrations/<timestamp>.sh` (using the existing `bin/omawsl migrate` mechanism) handles the
one-time transition, run automatically the next time the user runs `bin/omawsl migrate` (which
`omawsl update` already calls):

- `~/.bashrc`: if its content exactly matches a known previous `configs/bashrc` revision (safe to
  detect — today's `cp`-then-overwrite behavior means the file, if untouched by the user, is
  either an exact match or was already silently reset to one on the last omawsl re-run), replace
  it with the new marker block. Nothing is lost, since there was nothing else in the file. If the
  content doesn't match — already diverged, hand-edited since the last omawsl run — leave it as
  written and just append the new guarded marker block, the same path a fresh install takes.
- `~/.inputrc`: same content-match check against the known omawsl `configs/inputrc`. If it
  matches, delete it, so the new `INPUTRC` fallback in `configs/bashrc` takes over pointing at
  omawsl's own copy. If it doesn't match, leave it untouched entirely — no export override is
  added, matching the fresh-install behavior for a pre-existing file.

### 4. `/etc/wsl.conf` — hardened idempotency check

`install/terminal/docker.sh`'s existing check-then-append stays the same shape, but the match
regex tightens from `^systemd=true` to `^\s*systemd\s*=\s*true\s*$`, tolerating whitespace
variants a corp manual or hand edit might use. This is the one setting both omawsl and a typical
corp manual set, so it's the one place this project directly relies on the check being robust:
running omawsl after a corp manual (already `systemd=true`) is a no-op; running a corp manual
after omawsl (also already `systemd=true`) is likewise a no-op on the corp side (its instructions
already describe checking for existing content before adding).

### 5. `docs/config-safety.md` (new)

States the policy above and lists the files omawsl must never create or modify:

`~/.zshrc`, `/etc/zsh/zshenv`, `~/.oh-my-zsh/**`, `~/.curlrc`, `/etc/apt/apt.conf.d/*`,
`/etc/profile.d/*`, `/etc/sudoers*`, `~/.m2/settings.xml`, `~/.git-templates/**`,
`~/.config/direnv/direnvrc`, `/etc/systemd/system/wsl-vpnkit.service`,
`/etc/systemd/system/docker.service.d/*`.

Framed generally (not tied to any one company's manual) so it holds regardless of which specific
corp setup a reader is comparing against.

### 6. Never-touch regression test

New `tests/config_safety_test.bats`: statically greps `install/**/*.sh` and `uninstall/**/*.sh`
for write-operation patterns (`cp `, `> `, `tee`, `cat >`, `>> `) combined with any path from the
never-touch list, failing the suite if a future change ever adds one. A best-effort static guard,
not an exhaustive runtime check — consistent with this repo's existing doc-consistency test style
(`tests/readme_test.bats`), and root-free/network-free like the rest of the suite.

## Data flow / install sequence

No change to install-time ordering: `configs/bashrc`'s content has only ever taken effect in
*future* interactive shells (it's never sourced during `install.sh` itself — install-time PATH
needs are handled separately, e.g. `mise.sh` exporting `PATH` directly for the current script).
Moving from copy-based to marker-based installation doesn't change when or how any other
install step gets its PATH entries.

## Error handling

- If `$OMAWSL_HOME/configs/bashrc` is missing when a shell starts (checkout moved or deleted),
  the `[ -f ... ] &&` guard makes the source line a silent no-op — the shell degrades to plain
  bash rather than erroring, consistent with every other `command -v`-guarded block already in
  `configs/bashrc`.
- The migration script guards on `[ -f "$HOME/.bashrc" ]` / `[ -f "$HOME/.inputrc" ]` before any
  content comparison, so it's a no-op on a fresh install that never had the old format.

## Testing

- `tests/a_shell_test.bats`: the current "re-running overwrites deterministically" test (which
  today asserts a hand-added `.bashrc` line gets wiped) is replaced with tests asserting the
  opposite — hand-added content survives a re-run, the marker block is added exactly once and
  stays idempotent across re-runs, and a pre-existing `~/.inputrc` is left untouched with no
  `INPUTRC` override.
- New migration test file (e.g. `tests/migration_bashrc_source_test.bats`), following the direct
  sourcing pattern already used throughout this suite: sources the migration script and asserts
  both branches — an unmodified old-style `.bashrc`/`.inputrc` gets converted cleanly, and a
  hand-diverged one is left alone with the marker block appended instead.
- New `tests/config_safety_test.bats` per Component 6.
- `install/terminal/docker.sh`'s existing wsl.conf tests get an added case for the whitespace
  variant (`systemd = true`) now recognized as already-satisfied.

## Non-scope / explicitly deferred

- Files omawsl doesn't touch today and this design doesn't add support for touching
  (`~/.m2/settings.xml`, `~/.git-templates/hooks/*`, `~/.config/direnv/direnvrc`, etc.) — these
  stay on the never-touch list. If omawsl ever needs to manage one of these (e.g. a future Java
  picker needing Maven config), it gets its own design applying the same policy (native drop-in
  first, then guarded include, then content-checked append), not decided here.
- Zsh support in general — omawsl ships bash only; the corp manual's zsh-specific steps
  (`~/.zshrc`, `/etc/zsh/zshenv`, oh-my-zsh) are out of scope for this change and stay on the
  never-touch list unmodified.
- Marker-block *replacement* (detecting and rewriting an existing block in place, e.g. if
  `$OMAWSL_HOME` moves) — deliberately not built; see the non-goal note under Component 1.
