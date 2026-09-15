# Lesson 9: Aliases and Demo Docs

## 1. Concept

By this point in the build, omawsl already installs everything Omakub
installs — the terminal tools, the languages, the editors, the themes. But
"installs the same tools" and "feels like the same daily-driver
experience" are different claims. Omakub itself ships a curated layer of
shell aliases, a distinctive one-glyph prompt, and a `cd` override wired
to `zoxide` — the muscle-memory shortcuts a Rails-shop developer actually
types all day. omawsl's `configs/bashrc` never ported any of that; it only
ever had a couple of omawsl-original conveniences. This phase closes that
gap, for the parts of Omakub's alias set that actually make sense in a
WSL2 context (the spec explicitly drops a handful — see the Walkthrough).

Before going further, it's worth being precise about what an **alias**
actually is, since this phase leans on the distinction between it and two
things that look similar:

- **An alias** is a plain text substitution the shell performs *before* it
  tries to run a command. `alias ll='eza -la'` means: any time you type
  `ll` as the first word of a command, bash replaces it with `eza -la`
  before doing anything else. Aliases take no arguments of their own logic
  — `alias g='git'` lets you type `g status`, but that's just bash
  appending your typed `status` after the substituted `git`, not the alias
  itself doing anything with `status`. Aliases only exist for the
  lifetime of the shell that defined them, and — critically — they are
  normally only expanded in **interactive** shells, not when a script
  runs; that's one reason they live in `~/.bashrc` (sourced fresh into
  every new interactive shell) rather than being useful to put in a script
  file.
- **A function** is a named, reusable block of actual code. Like an alias
  it's invoked by typing its name, but unlike an alias it can inspect its
  arguments (`$1`, `$#`, `"$@"`), branch on them, loop, and do anything a
  script can do. This phase needs exactly one function, `n()`, because it
  has real logic: "if I was called with no arguments, open Neovim on the
  current directory; otherwise, open it on whatever files I was given."
  An alias can't express an `if` — `n` has to be a function.
- **A script** is a separate file, usually with its own shebang, run as a
  brand-new child process (`bash somefile.sh`, or `./somefile.sh` if
  executable). It has its own environment and doesn't share variables or
  functions with the shell that launched it unless you explicitly export
  something into it. Aliases and functions, by contrast, live *inside*
  the current shell process — no fork, no new process, just an
  instruction the same shell interprets differently going forward. That's
  exactly why `configs/bashrc` — a file that's `source`d, not executed —
  is where all of this lives: sourcing runs its lines *in* your
  interactive shell, so the aliases and the `n()` function it defines
  become available in that same shell, the same way Phase 1 relied on
  sourcing to pull functions from `install/lib.sh` into `install.sh`.

The second half of this phase looks unrelated at first — writing
`docs/demo-personal.md` and `docs/demo-corporate.md`, two live-demo
scripts for presenting omawsl — but it's taught alongside the aliases for
a reason: it's the same instinct applied to documentation instead of
code. Every alias in this phase is guarded by checking what's *actually*
on `$PATH`, not assumed to be there (see the `batcat`/`bat` bug below).
The demo docs apply that same discipline to prose: every command, install
slug, and theme name in them was checked against the real, current source
(`bin/omawsl-sub/items.sh`, `bin/omawsl-sub/theme.sh`, `bin/omawsl`'s own
usage text) before being written down, not typed from memory or
assumption. A demo script that references a slug that doesn't exist
anymore fails live, in front of an audience, exactly the way an untested
alias fails the first time someone types it. Documentation that a human
is going to *perform from*, live, deserves the same "did I verify this
actually works" discipline as code — that's the throughline this lesson
is grounded in.

## 2. Walkthrough

### The guard pattern, and a real bug it was hiding

Every alias in this phase (except the three directory-nav ones, explained
below) is wrapped the same way:

```bash
if command -v batcat &>/dev/null; then
  alias cat='batcat --paging=never'
fi
```

`command -v NAME` prints the path of `NAME` if it's found on `$PATH` (or
recognizes it as a builtin/function) and exits `0`; it exits non-zero and
prints nothing if it isn't found. It's the POSIX-correct way to ask "does
this command exist" — more portable than `which`, which isn't part of the
POSIX standard and behaves inconsistently across systems. `&>/dev/null`
redirects both stdout and stderr to the null device (`/dev/null`, a file
that silently discards anything written to it), so the check produces no
visible output either way — only its exit status matters to the `if`.

This guard exists so a fresh shell degrades gracefully instead of
surprising you: if `zellij` failed to install, or a corporate user's
language picker skipped Rails, the alias for it simply never gets
defined, rather than existing and immediately printing "command not
found" the first time you type it.

The `batcat` line above is also a real bug fix, worth understanding
concretely because the *kind* of bug generalizes. Ubuntu's apt package
named `bat` installs a pretty-printing `cat` replacement — but the
*binary* it installs is named `batcat`, not `bat`, because Debian already
had an unrelated, pre-existing package literally called `bat` (a
brightness-control tool) that owns that binary name. `fd-find` has the
identical situation: the package is `fd-find`, the installed binary is
`fdfind`. omawsl's bashrc had a guard checking `command -v bat` since
Phase 1 — which was never true on Ubuntu, so the intended `cat` alias had
silently never activated, for the entire life of the project up to this
phase. The general lesson: **an apt package's name and the name of the
binary it actually installs are not guaranteed to match** — you have to
verify what lands on disk, not assume the obvious name. (This is the same
category of "verify, don't assume" bug as Phase 1's `SCRIPT_DIR`
namespace collision and the mise-activation PATH-ordering bug described
next — this project has hit this class of mistake more than once.)

### Ordering inside the file matters — PATH has to exist first

```bash
# lazydocker has no apt package - it installs to $HOME/.local/bin, only
# reachable after the PATH export above.
if command -v lazydocker &>/dev/null; then
  alias lzd='lazydocker'
fi
```

`command -v` only sees what's on `$PATH` *at the moment it runs* — bash
executes a script (or a sourced file) top to bottom, sequentially, so a
guard placed before the line that adds `$HOME/.local/bin` to `$PATH`
would always fail, even on a machine where `lazydocker` really is
installed there. This is exactly the same bug class Phase 1's
`mise`-activation ordering fix addressed (confirmed as a real failure on
an actual WSL2 run: `mise --version` worked because the `PATH` export ran
unconditionally, but `mise activate` never fired because its guard ran
too early) — this phase's `lazydocker` and `rails` guards deliberately
sit *after* the `$HOME/.local/bin` export and *after* `mise activate`
respectively, for the identical reason.

### The `eza`/`ls` family, and a deliberate reuse trick

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

`lsa` and `lta` don't hardcode `eza` a second time — they alias to `ls -a`
and `lt -a` respectively, referencing the *names* `ls`/`lt`, not the
literal `eza` command. This relies on how bash resolves aliases: it
re-expands an alias name against the *current* alias table every time it
parses a command line, not once at the moment the alias was defined. So
if `ls` is ever redefined, `lsa` automatically follows, without needing
its own update — a small but deliberate reuse decision, matching the same
trick Omakub's own upstream aliases file uses. A single-quoted alias
definition (`alias lsa='ls -a'`, not double-quoted) is what makes this
safe: single quotes prevent bash from expanding anything inside the
string at definition time, so `ls` stays a literal, unexpanded name to be
looked up again later, at call time.

### `cd='z'`, and the `n()` function

```bash
if command -v zoxide &>/dev/null; then
  eval "$(zoxide init bash)"
  alias cd='z'
fi
```

`zoxide` is a smarter `cd` that learns your most-visited directories and
lets you jump to them by a fuzzy fragment of their name instead of a full
path. `zoxide init bash` prints the shell code that defines its own `z`
function; `eval` runs that printed text as if you'd typed it directly.
Omakub goes one step further than just offering `z` alongside `cd` — it
replaces `cd` itself with an alias to `z`, full parity with upstream. The
guard block places this *after* `zoxide init bash` runs, deliberately: `z`
has to already exist as a function before an alias can point at it.

```bash
if command -v nvim &>/dev/null; then
  n() { if [ "$#" -eq 0 ]; then nvim .; else nvim "$@"; fi; }
fi
```

This is the one place in this phase that needs a **function**, not an
alias, because it branches: `$#` is the count of positional arguments
passed to `n`; if there are none, open Neovim on `.` (the current
directory); otherwise, pass every argument through unchanged. `"$@"`
(quoted) expands to each argument as its own separate, still-quoted word
— the correct way to "forward all my arguments" when any of them might
contain spaces — as opposed to `"$*"`, which would glue them all into one
single string. An alias has no `if`, no `$#`; this genuinely can't be
written as one.

### Directory nav, and unconditional aliases

```bash
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
```

These three are the one place in this phase with *no* `command -v` guard.
They don't need one: `cd` always resolves to something — either the
bash builtin, or the `z` alias defined just above it if `zoxide` is
installed — so there's no tool whose absence these aliases need to defend
against.

### Reusing Phase 1's idempotent-append pattern

The outline for this phase describes its side effects as "none beyond the
pre-existing `~/.bashrc` edit already covered by an earlier phase" — that
earlier mechanism is `install/lib.sh`'s `omawsl_ensure_bashrc_source_line`,
already built in Phase 1:

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

Every alias this phase adds lives inside `configs/bashrc`, which that
function already ensures gets sourced from `~/.bashrc` exactly once —
this phase's new alias lines ride along on a mechanism that was already
built and already idempotent, rather than needing a second, separate
"how do I safely add lines to someone's dotfile" solution. Notice the
shape: `grep -qF` (fixed-string, quiet grep) checks whether the marker is
already present and returns early if so; otherwise it appends a
marker-delimited block inside a `{ ...; } >> file` group, which redirects
every `printf` inside the braces to the same single append. This exact
shape — check-marker-then-append-once — is what this lesson's exercise
asks you to reproduce for a block of alias lines, rather than a single
source line.

### The demo docs — documentation written like tested code

`docs/demo-personal.md` and `docs/demo-corporate.md` are the user's own
live-demo scripts — checkbox-driven, terse, "do this, say this, show
this" — not general-audience documentation. Each is split into two parts:

- **Prep** — anything slow or boring done *before* recording (installing
  Windows Terminal, downloading a font, making the GitHub repo public).
  Explicitly kept out of the timed live flow, because dead air during a
  recording is a real cost a checklist can plan around.
- **Live script** — numbered `- [ ]` steps in the literal order they'll be
  performed, each with the exact command (if any), a short **Say:**
  narration cue (a prompt to talk around, not a script to read verbatim),
  and a **⭐ Why this matters:** callout on any step landing one of four
  pre-selected differentiator beats (the full CLI surface, the update
  mechanism, granular install/uninstall, Windows Terminal theme sync).

The two files are fully self-contained — deliberately, per the design
spec's explicit "no cross-referencing the other file mid-demo" rule. A
DRY-minded instinct would want one shared file with branches for
corporate vs. personal; that's rejected here on purpose, because the cost
of a wrong assumption is different for docs performed live than for code:
losing your place flipping between two sections of a shared file, mid-
recording, is a real, visible failure a viewer sees happen. Duplication is
the right call specifically because the two audiences (a locked-down
corporate machine vs. a personal power-user machine) genuinely need
different framing at almost every step — Docker Desktop vs. Engine, VS
Code vs. opencode, one language pick vs. three — not just different
values plugged into an otherwise-identical script.

The part of this that mirrors the aliases half of this lesson most
directly: every install slug, theme name, and command shown in these two
files was verified against the real current source before being written
down — `bin/omawsl-sub/items.sh` for language/editor/storage slugs,
`bin/omawsl-sub/theme.sh` for the ten real theme names, `bin/omawsl`'s own
usage output and `README.md`'s feature list for the four differentiator
beats — rather than assumed from memory. That's the "documentation as a
tested artifact" idea from the Concept section made concrete: a script a
human is going to read from, live, on camera, gets the same "did I check
this is actually true" discipline a `command -v` guard gives an alias.

## 3. Exercise

Close this lesson and do the following in `practice/09-aliases-and-demo-docs/`,
blind — don't look back at the Walkthrough while you write.

**Part 1 (checked).** In `practice/09-aliases-and-demo-docs/aliases.sh`,
define a bash function:

```
append_omakub_aliases <target-file>
```

that appends a block of alias/function definitions to `<target-file>`,
wrapped between two marker comment lines, written exactly like this:

```
# >>> omawsl aliases >>>
...your block...
# <<< omawsl aliases <<<
```

The block must include, at minimum, guarded definitions for:

- the `eza`-backed `ls` family: `ls`, `lsa`, `ll`, `lt`, `lta` (guarded on
  `eza`)
- `cat` aliased to `batcat --paging=never` (guarded on `batcat`, **not**
  `bat`)
- `fd` aliased to `fdfind` (guarded on `fdfind`)
- `cd` aliased to `z` (guarded on `zoxide`)
- the three directory-nav aliases `..`, `...`, `....` (no guard needed)
- git shortcuts: `g`, `gcm`, `gcam`, `gcad` (guarded on `git`)
- tool shortcuts: `d` for `docker`, `r` for `rails`, `lzg` for `lazygit`,
  `lzd` for `lazydocker` (each guarded on its own tool)
- the `n()` function that opens Neovim on `.` with no arguments, or on its
  arguments otherwise (guarded on `nvim`)

The function must be **idempotent**: if `<target-file>` already contains
the `# >>> omawsl aliases >>>` marker line, calling `append_omakub_aliases`
again must leave the file unchanged — no second copy of the block, no
duplicated alias lines. Define the function only; don't call it
unconditionally at the bottom of the file (this file gets `source`d
directly by the check).

**Part 2 (not automatically checked — prose isn't gradable the way code
is).** In `practice/09-aliases-and-demo-docs/my-demo-notes.md`, sketch
your own Prep + Live-script checklist, in the same checkbox/**Say:**/⭐
style, for a command-line tool of your choosing that you could imagine
demoing live. There's no check script for this part; once you're done,
compare its structure — not its content — against `docs/demo-personal.md`
and `docs/demo-corporate.md` in this repo, purely to see how the real
ones split Prep from Live and where the ⭐ callouts land.

## 4. Check

Run:

```bash
practice/09-aliases-and-demo-docs/check.sh
```

It sources your `aliases.sh`, calls `append_omakub_aliases` against a
throwaway scratch file (never your real `~/.bashrc`), and checks that
file's contents for each required alias — then calls the function a
second time on the same file and checks that nothing got duplicated.
Every assertion prints its own `PASS:`/`FAIL:` line, and the script runs
all of them even after an early failure, so one run shows you everything
that's wrong, not just the first thing.

Read a `FAIL:` line as a description of *behavior* that didn't match —
e.g. "expected to find: alias cat='batcat --paging=never'" means your
block either guarded on the wrong command name (`bat` instead of
`batcat`) or used different flags, not that a specific line number is
wrong. A passing check means your `aliases.sh` is behaviorally correct
even if it's organized completely differently from the Walkthrough — a
different variable name for the marker, a different order of blocks, a
`case` statement instead of a chain of `if`s, all fine. If you want to
compare style purely as a study aid afterward, look at the real diff with
`git show c71b2f9 -- configs/bashrc` in this repo — but only after your
check passes, and only for style, never as the grade.
