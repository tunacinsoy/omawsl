# Phase 15: corp-safe-config-editing

## 1. Concept

Every phase so far has treated `~/.bashrc` as omawsl's file: Phase 1 through
Phase 14 (`install/terminal/a-shell.sh`) simply `cp`-overwrote it with
omawsl's own `configs/bashrc` on every install and every re-run. That's fine
on a personal laptop where nothing else touches `~/.bashrc`. It is not fine
on a corporate-managed WSL2 machine — plenty of companies ship an internal
setup manual that also edits `~/.bashrc` (or `~/.curlrc`, `~/.m2/settings.xml`,
`/etc/wsl.conf`, and a dozen other files) to wire up a proxy, an internal
package mirror, or VPN settings. If omawsl's installer runs *after* that
manual, a blind `cp` silently deletes every line the corp manual added, with
no warning and no way back. omawsl doesn't know what's in those lines, can't
tell which ones are safe to lose, and has no way to find out — so the only
correct policy is to never make that judgment call at all.

A **dotfile** is just a config file in a user's home directory whose name
starts with a dot (`.bashrc`, `.inputrc`, `.gitconfig`, ...) — the leading
dot makes most shells and file managers hide it from a normal directory
listing by default, which is why they're called "dotfiles" rather than just
"config files." `~/.bashrc` is the dotfile bash reads and runs every time it
starts an interactive shell; `~/.inputrc` is the one `readline` (the library
that handles line-editing and history search for bash and lots of other
CLI tools) reads for keybinding/completion settings.

This phase is a policy change, not a feature: **omawsl stops writing its own
content directly into files it doesn't exclusively own.** Concretely:

- `~/.bashrc` and `~/.inputrc` live outside the project (in the user's home
  directory) and might be managed by someone else. omawsl doesn't own them,
  so it never overwrites them again.
- `configs/bashrc` and `configs/inputrc`, by contrast, live *inside* the
  omawsl repo checkout. omawsl is the sole author of those two files — it's
  always safe to rewrite them completely, and `omawsl update`'s `git pull`
  does exactly that.
- The bridge between "content omawsl owns" and "a file omawsl doesn't own"
  is the **source-line pattern**: add exactly one line to the file omawsl
  doesn't own, and that one line's entire job is to `source` (bash's command
  for "run this other file's contents as if it were typed right here") the
  file omawsl *does* own. Everything omawsl wants to configure lives in
  `configs/bashrc`; `~/.bashrc` itself only ever gains one small, easily
  recognizable addition, and every other line already in it — hand-written,
  corp-added, or left over from a previous omawsl version — survives
  untouched, forever.
- That one line has to be added **idempotently** — a term for an operation
  that produces the same end result no matter how many times it runs. Since
  omawsl's installer can run again (an update, a re-run after a crash, a
  fresh `omawsl install`), adding the source line unconditionally every time
  would eventually duplicate it. Idempotency here means: check whether the
  line is already there before adding it.
- Existing installs already have the *old*, fully-`cp`-overwritten
  `~/.bashrc`. Moving them onto the new model needs a **migration** — a
  script that changes something about an existing install exactly once,
  the moment the install first sees the new omawsl version, so users don't
  have to manually fix anything themselves. A migration script has a
  stricter safety bar than ordinary install code: it must be safe to run on
  a machine that has *never* been migrated (a truly fresh conversion) *and*
  safe to run again on a machine that already *has* been migrated (because
  `omawsl update` may call it on every update, not just the first one after
  this feature ships) — running it twice must never duplicate or corrupt
  anything. That's the same idempotency requirement as the source-line
  helper itself, just applied to a one-time transition instead of an
  ongoing install step.

The interesting design decision in this phase isn't the happy path — it's
what the project's own history shows getting *rejected* mid-implementation
once someone actually thought through the risk. That reversal is the real
lesson: designing for "we might be wrong about what's safe to touch," not
"we own this file and can do what we want with it."

## 2. Walkthrough

### The policy, stated once

`docs/config-safety.md` states the rule this whole phase exists to enforce:

> omawsl never writes its own content directly into a file it doesn't
> exclusively own. Content omawsl needs to provide lives in files under its
> own tree ... and is freely rewritten there - omawsl is the sole owner.
> Touching a shared file happens only through the smallest possible,
> idempotent, content-checked addition: the format's own drop-in mechanism
> if one exists (`/etc/profile.d/*`, `/etc/apt/apt.conf.d/*`,
> `/etc/sudoers.d/*`, a systemd `*.conf.d/` override directory), a single
> guarded include/source line added only if not already present, or - only
> for formats with neither, like `/etc/wsl.conf` - a content-based
> check-then-append.

That's a priority order, not three independent options: prefer a real
drop-in directory when the file format has one (omawsl doesn't need this
for anything in scope here); otherwise a guarded source line (this phase's
`~/.bashrc` case); and only when neither exists, a raw content-checked
append (`/etc/wsl.conf`, handled by `install/terminal/docker.sh`, whose
existing `systemd=true` check this phase also hardens — see below). The doc
also carries a "never touch" list — `~/.zshrc`, `~/.curlrc`,
`/etc/apt/apt.conf.d/*`, `~/.m2/settings.xml`, and others a corporate setup
manual commonly owns — files omawsl doesn't manage at all and isn't adding
support for here. `tests/config_safety_test.bats` greps `install/**/*.sh`
for write patterns against every path on that list, so a future change that
accidentally starts writing to one of them fails the test suite immediately.

### The helper: `omawsl_ensure_bashrc_source_line`

The whole feature's mechanical core is one function in `install/lib.sh`:

```bash
omawsl_ensure_bashrc_source_line() {
  local bashrc_file="$1" target_file="$2"
  touch "$bashrc_file"
  if grep -qF '# >>> omawsl >>>' "$bashrc_file"; then
    return 0
  fi
  {
    printf '\n# >>> omawsl >>>\n'
    printf '[ -f "%s" ] && source "%s"\n' "$target_file" "$target_file"
    printf '# <<< omawsl <<<\n'
  } >> "$bashrc_file"
}
```

Read it line by line:

- `touch "$bashrc_file"` — creates the file if it doesn't exist yet (a
  brand-new machine with no `~/.bashrc` at all), and is a no-op if it
  already exists. This means the rest of the function never has to special-
  case "file missing."
- `grep -qF '# >>> omawsl >>>' "$bashrc_file"` — the idempotency check.
  `-q` means "quiet" (don't print the matching line, just report found/not
  found via exit status); `-F` means "fixed string" (match `# >>> omawsl
  >>>` literally, not as a regular expression — irrelevant here since there
  are no regex metacharacters in that string, but it's a defensive habit:
  if the marker text ever changed to include something like `[boot]`,
  `-F` keeps it from being misinterpreted). If the marker's already there,
  `return 0` and do nothing else — this is what makes the whole function
  safe to call on every install and every update, forever.
- The `{ ... } >> "$bashrc_file"` block: three `printf`s, all redirected as
  one group with `>>` (*append*, never `>`, which would truncate the file).
  Grouping them in `{ }` means the `>>` redirection applies to the whole
  block rather than needing to be repeated on each line — a small syntactic
  convenience, not a safety requirement here, but it also guarantees the
  three lines land together with no other process able to interleave output
  in between.
- The marker comments (`# >>> omawsl >>>` / `# <<< omawsl <<<`) exist purely
  so the idempotency check has something unambiguous to search for — they
  don't do anything when bash parses the file (they're comments), but they
  give a human skimming `~/.bashrc` an obvious visual boundary around
  omawsl's one addition.
- The source line itself: `[ -f "%s" ] && source "%s"` — the `[ -f ... ] &&`
  guard means "only run the `source` if that file still exists." If
  `$OMAWSL_HOME` is ever moved or deleted, this line silently does nothing
  instead of erroring out every time a new shell starts — the shell just
  degrades to plain, unconfigured bash. That's the same defensive pattern
  every other optional-tool check in `configs/bashrc` already uses (e.g.
  `if command -v nvim &>/dev/null; then ...`).
- `target_file` is written in as an **absolute, resolved path** at call
  time, not as a literal `$OMAWSL_HOME` reference. That matters: `$OMAWSL_HOME`
  is a variable that exists while the *installer* runs, but it is never
  exported into the environment of a brand-new interactive shell later —
  if the source line read `source "$OMAWSL_HOME/configs/bashrc"` literally,
  it would try to expand an unset variable every time a new terminal opened.
  Baking in the real path at install time avoids that entirely.

Two parameters, not a hardcoded pair — `omawsl_ensure_bashrc_source_line
<bashrc_file> <target_file>` takes both "which file to edit" and "what to
source" as arguments. That's what lets the same helper serve two different
call sites in this codebase (a fresh install's `a-shell.sh`, and the
migration script below) without duplicating the append logic, and it's what
made the function testable against an arbitrary scratch file in
`tests/lib_test.bats` without touching a real `~/.bashrc`.

### Wiring it up: `install/terminal/a-shell.sh`

Before this phase, this file `cp`-overwrote `~/.bashrc` and `~/.inputrc`
directly. After:

```bash
omawsl_install_shell_config() {
  omawsl_ensure_bashrc_source_line "$HOME/.bashrc" "$OMAWSL_REPO_ROOT/configs/bashrc"
}
```

One call. `$OMAWSL_REPO_ROOT` is resolved earlier in the file from
`${BASH_SOURCE[0]}` — the same absolute-path resolution pattern
`apps-terminal.sh`'s `omawsl_install_cli` already used before this phase, so
this isn't a new technique, just a new place applying it. Notice what's
*not* here anymore: no `cp`, and nothing touches `~/.inputrc` at all.

### `~/.inputrc`: not written, only deferred to

`~/.inputrc` needed a different answer than `~/.bashrc`, because unlike
`~/.bashrc` (which every shell reads and where a `source` line composes
cleanly with anything else already there), `readline` only reads *one*
`~/.inputrc` — there's no way to make it also read a second file via a
source-line-style addition. So instead of writing anything to
`~/.inputrc` at all, `configs/bashrc` sets the `INPUTRC` environment
variable to point straight at omawsl's own `configs/inputrc`, but only when
the user doesn't already have a `~/.inputrc` of their own:

```bash
if [ -z "${INPUTRC:-}" ] && [ ! -f "$HOME/.inputrc" ]; then
  export INPUTRC="$(dirname "${BASH_SOURCE[0]}")/inputrc"
fi
```

Both conditions matter: `-z "${INPUTRC:-}"` (don't override if the user or
a corp policy already set `INPUTRC` some other way) and `[ ! -f
"$HOME/.inputrc" ]` (don't override if a real file is already sitting
there — readline would use it by default anyway, but this also keeps
omawsl from claiming ownership of a variable a hand-written `~/.inputrc`
implies the user wants respected). If either condition fails, this block
does nothing, and readline's own normal lookup behavior takes over
untouched. `$(dirname "${BASH_SOURCE[0]}")` resolves relative to
`configs/bashrc`'s *own* real location — the file already knows where it
lives without needing a separate path variable threaded in.

### Hardening the one file omawsl and a corp manual actually share:
`/etc/wsl.conf`

`install/terminal/docker.sh` sets `[boot] systemd=true` in `/etc/wsl.conf`
for Docker Engine mode — the one file in scope here that a corp manual is
actually likely to also set, and the one case in the whole project that
falls into the third, weakest tier of the policy's priority order
(`/etc/wsl.conf` has no drop-in directory and can't be `source`d — WSL reads
it as one literal file). The existing check-then-append got its match
regex tightened from `^systemd=true` to
`^[[:space:]]*systemd[[:space:]]*=[[:space:]]*true[[:space:]]*$` so that a
corp manual's `systemd = true` (with spaces) is recognized as
already-satisfied instead of triggering a redundant append. This isn't
about deleting anything — it's the same "don't assume you know the exact
byte-for-byte formatting of content you didn't write" caution applied to a
regex instead of a whole-file overwrite.

### The migration — and the design change worth studying closely

`migrations/1785266018.sh` handles converting an *existing* install's old,
fully-`cp`-overwritten `~/.bashrc`/`~/.inputrc` onto the new model. It's
picked up automatically: `migrations/README.md` explains that
`bin/omawsl migrate` compares a timestamp recorded in
`~/.local/state/omawsl/version` against every file in `migrations/`, named
`<unix-timestamp>.sh`, and runs any whose timestamp is newer than what's
recorded — this file's timestamp-named convention is how a one-time upgrade
step gets run exactly once across everyone's installs without a separate
tracking mechanism.

The design spec's first draft (still visible in
`docs/superpowers/specs/2026-07-28-corp-safe-config-editing-design.md`,
under "Migration for existing installs") proposed something that sounds
reasonable at first: check whether `~/.bashrc`'s content exactly matches a
known old `configs/bashrc` revision — omawsl's own banner comment as the
first line — and if so, *delete and replace* it with the new marker block,
since "there was nothing else in the file." Do the same content-match check
for `~/.inputrc`, deleting it on a match so the new `INPUTRC` fallback could
take over. That's how the migration was actually first written — you can
see it in the pre-fix version of `migrations/1785266018.sh` at commit
`b37975d`.

It shipped, and then got reverted one commit later, at `8e05f6c`, whose
message states the flaw plainly:

> A banner-line match only proves omawsl originally created the file - it
> says nothing about whether the user or corp IT appended content since
> their last omawsl update. Deleting on that basis could silently destroy
> exactly the content this feature exists to protect.

Walk through why that matters. Say a user installed omawsl eight months
ago (an exact-match, omawsl-authored `~/.bashrc`), and three months ago
their company's IT manual had them hand-append a proxy export to the
*bottom* of that same file. The file's *first line* still matches omawsl's
old banner — a check that only inspects the banner, or even one that diffs
the whole file against a single known-old revision, has no way to see that
appended content unless it happens to diff the file against literally every
revision `configs/bashrc` has ever had. The original design's "if it
matches, delete" logic would delete that user's proxy config along with the
old omawsl content, silently, during a routine `omawsl update` — the exact
kind of accidental data loss this whole phase exists to prevent, just moved
one layer down into the migration instead of the fresh-install path.

The fix, in the diff:

```diff
 omawsl_migrate_bashrc_to_source_line() {
-  local bashrc="$HOME/.bashrc"
-  if [[ -f "$bashrc" ]] && head -n1 "$bashrc" | grep -qF '# omawsl bashrc ...'; then
-    rm -f "$bashrc"
-  fi
-  omawsl_ensure_bashrc_source_line "$bashrc" "$OMAWSL_ROOT_DIR/configs/bashrc"
+  omawsl_ensure_bashrc_source_line "$HOME/.bashrc" "$OMAWSL_ROOT_DIR/configs/bashrc"
 }
```

No more content match, no more `rm -f`, no branching at all — the migration
now does *exactly* what a fresh install does: append the guarded marker
block if it's not already there, unconditionally, regardless of what's
above it. The old `cp`-written content (banner, aliases, the old file's
trailing `exec zellij`, and anything the user or corp IT appended after
that) all survives, sitting above the new marker block. Nothing is lost;
nothing needed to be provably safe to delete, because nothing gets deleted.

The `~/.inputrc` side of the migration went further — it just does nothing
at all. The comment left in the final code explains the accepted trade-off
plainly:

```bash
# No migration step for ~/.inputrc: since deletion isn't provably safe (see
# above), and there's nothing else safe to do to an existing file, any
# ~/.inputrc - omawsl-authored or not - is left exactly as-is. Accepted
# trade-off: a user with an old omawsl-authored ~/.inputrc won't benefit
# from the new INPUTRC-fallback pointing at omawsl's own copy, since that
# fallback only activates when ~/.inputrc is absent.
```

This is the concentrated version of the whole phase's lesson: when the only
way to get a *nicer* outcome (a cleaned-up `~/.inputrc` that benefits from
the new fallback) requires an operation (`rm`) that can't be proven safe for
every user who might hit it, the correct engineering call is to accept the
worse-but-safe outcome (leave it alone, forever) rather than gamble on a
check that only *usually* proves safety. "We might be wrong about what's
safe to touch" beats "we're pretty sure this is fine" every time the
downside is silent, unrecoverable data loss on someone else's machine you
will never see.

One loose end the migration can't clean up automatically: an old
`~/.bashrc` typically ends in `exec zellij` (`exec` replaces the running
shell process outright), so on a machine with zellij installed, that old
`exec` line fires *before* the shell ever reaches the newly-appended marker
block below it — the new `configs/bashrc` source line never actually loads.
`migrations/1785266018.sh` can't safely delete the old content to fix this
(same reasoning as above), so instead it just prints an advisory
(`omawsl_warn_if_old_bashrc_copy_present`) telling the user it's safe to
delete everything above the marker by hand, and leaves the decision to
them.

## 3. Exercise

Close this lesson and, in `practice/15-corp-safe-config-editing/lib.sh`,
implement:

```bash
ensure_source_line <file>
```

A stub for this file already exists in `practice/15-corp-safe-config-editing/`
— fill in the function body. Behavior to match, based on everything in the
walkthrough above:

- `<file>` is the path to a dotfile (e.g. a stand-in for `~/.bashrc`). If it
  doesn't exist yet, create it.
- Append a marker-delimited block using exactly these two marker lines:
  `# >>> omawsl >>>` and `# <<< omawsl <<<`, with a `source` line for
  omawsl's own config in between, guarded so it's a no-op if that config is
  missing (same `[ -f ... ] &&` shape as the real helper).
- The config being sourced always lives at
  `$HOME/.local/share/omawsl/configs/bashrc` — resolve that path through
  `$HOME` at the time the function runs (don't hardcode a literal home
  directory), matching what the real `install/lib.sh` helper does when it
  bakes in an absolute, resolved path rather than an unexpanded variable
  reference.
- If the marker is already present in `<file>`, do nothing and return
  successfully — no duplicate marker block, ever, no matter how many times
  the function runs.
- Never modify, reorder, or delete any line already in `<file>` that isn't
  part of omawsl's own marker block — appending is the only operation this
  function is allowed to perform on existing content.

This is a simplified, single-argument version of the real
`omawsl_ensure_bashrc_source_line <bashrc_file> <target_file>` (which takes
the target to source as a second argument, so it can be reused for
different config paths across call sites) — here the target is fixed, so
the function only needs the one argument.

## 4. Check

Run:

```bash
bash practice/15-corp-safe-config-editing/check.sh
```

It exercises `ensure_source_line` against three scratch files it sets up
for you — one that doesn't exist yet, one where the marker's already
present (checking that a second run doesn't duplicate it), and one
pre-loaded with unrelated lines a "user" supposedly wrote by hand (checking
that they survive byte-for-byte and aren't duplicated). Every check prints
its own `PASS:`/`FAIL:` line, and a failure tells you which *behavior*
didn't match — e.g. "unrelated pre-existing content was modified or
removed" — not which lines of your code differ from the original. A
passing check means your implementation is behaviorally correct even if it
doesn't look anything like `install/lib.sh`'s version — appending in a
different order, using `cat <<EOF` instead of three `printf`s, whatever you
chose is fine as long as the observable behavior matches. Once it passes,
you can open `install/lib.sh`'s real `omawsl_ensure_bashrc_source_line` and
compare purely as a style reference, never as the grade.
