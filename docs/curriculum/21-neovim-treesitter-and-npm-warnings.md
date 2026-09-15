# Lesson 21: Neovim Tree-sitter CLI and Precise npm Warning Filtering

## 1. Concept

This is the last phase in the build. There's no new subsystem here — no
new picker item, no new file category. It's two small, unrelated bug
fixes that both happened to land the same week (issues #17 and #27), each
worth internalizing for a different reason.

The first fix, `omawsl_install_treesitter_cli`, is a straightforward "the
version omawsl was relying on doesn't do the thing anymore" bug: LazyVim's
starter config pins its `nvim-treesitter` plugin to that project's `main`
branch, and that branch's installer needs a `tree-sitter-cli` newer than
the one Ubuntu's package manager ships. The interesting part isn't the bug
itself — it's the idempotency check that guards the fix, which has to be
careful about what "already installed" even means when a *broken* version
of the tool is already sitting on `$PATH`.

The second fix is the one worth sitting with longer, because it's a
pattern that generalizes past this codebase entirely: a warning appears in
some tool's output, it's noise, and the natural first instinct is to
suppress output wholesale. That instinct shipped first (`--loglevel=error`
on every affected `npm install`), got caught in code review, and was
replaced with something that filters for the *exact known-safe message*
instead. The lesson isn't "always write more code" — it's that the size of
a fix and the correctness of a fix are different axes, and a fix that
silences an entire category of output to eliminate one specific line
usually costs you visibility you didn't mean to give up.

## 2. Walkthrough

### Part A — a working `tree-sitter-cli`

First, the concept `tree-sitter-cli` sits on top of. **Tree-sitter** is a
parsing library: it reads source code text and builds a **syntax tree** —
a structured, in-memory representation of the code's grammar (this
function call contains these arguments, this `if` block contains this
body, and so on) instead of just a flat string. Neovim's `nvim-treesitter`
plugin uses that tree for accurate syntax highlighting, code folding, and
"smart" text objects (e.g. "select the whole function this cursor is
inside"), instead of the much cruder regex-based highlighting Vim
traditionally relied on.

Tree-sitter needs a separate **parser** for each language — a small
grammar-specific plugin. Those parsers start life as generated C source
code, and before Neovim can actually use one, it has to be **compiled**:
turned from that C source into a small, machine-specific shared library
(a `.so` file) that Neovim's runtime can load. `tree-sitter-cli` is the
tool that does that compiling — among other things, its `build`
subcommand is specifically "take this parser's C source and produce the
compiled shared library nvim-treesitter's `main` branch installer expects
to find."

That `build` subcommand is exactly what's missing on a fresh WSL2 Ubuntu
box:

> LazyVim's starter config pins nvim-treesitter to its `main` branch,
> whose installer shells out to `tree-sitter build` to compile parsers.
> Ubuntu Noble's apt tree-sitter-cli package (0.20.8-5) predates that
> subcommand, so every parser except the 3 bundled in Neovim's own
> runtime (c, lua, vimdoc) silently failed to compile on a fresh install
> (issue #17).
> — commit `004ae3b`

The original fix, in `install/terminal/app-neovim.sh`:

```bash
omawsl_install_treesitter_cli() {
  if [[ -x "$HOME/.local/bin/tree-sitter" ]]; then
    return 0
  fi

  mise exec node@lts -- npm install -g tree-sitter-cli

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/tree-sitter" <<'WRAPPER'
#!/usr/bin/env bash
exec mise exec node@lts -- tree-sitter "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/tree-sitter"
}
```

`mise` is the same version-manager tool omawsl already uses elsewhere in
the project to install language runtimes (Node, Python, Ruby, ...) without
touching Ubuntu's system-wide packages. `mise exec node@lts -- CMD` runs
`CMD` with a *private*, mise-managed Node.js runtime active — a completely
separate Node install from whatever (if anything) `apt` put on the
system. `npm install -g tree-sitter-cli` inside that context installs the
npm package globally, but "globally" here means into *that private
runtime's* global package directory, not anywhere on the normal system
`$PATH`. That's the whole reason the rest of the function exists: the
installed binary genuinely isn't reachable by typing `tree-sitter` at a
plain shell prompt yet.

The fix for that is the **wrapper script**: a tiny file written to
`$HOME/.local/bin/tree-sitter` whose entire job is `exec mise exec
node@lts -- tree-sitter "$@"` — every time this wrapper runs, it re-enters
the mise-managed environment and hands off to the real tool inside it,
forwarding whatever arguments it was called with. Since omawsl's `bashrc`
already puts `$HOME/.local/bin` ahead of `/usr/bin` on `$PATH`, this
wrapper automatically wins over any old apt-installed `tree-sitter-cli`
the next time a shell resolves the name `tree-sitter` — without needing to
uninstall the apt package at all.

The idempotency guard is the one line worth reading twice:

```bash
if [[ -x "$HOME/.local/bin/tree-sitter" ]]; then
  return 0
fi
```

This checks for *this function's own wrapper file* specifically — not
`command -v tree-sitter`, which is the more obvious-looking check. That
distinction matters here in a way it wouldn't in most idempotency guards:
an old, broken apt-installed `tree-sitter-cli` is *already* going to
resolve successfully under `command -v tree-sitter` — that's the entire
bug this function exists to fix. If the guard checked "does some
`tree-sitter` already exist on `$PATH`," it would see the broken apt copy,
conclude "already installed," and never apply the fix at all. Checking
for the wrapper file specifically means the guard is really asking "has
*my* fix already been applied," not "does something answering to this
name already exist" — a distinction worth carrying forward any time an
idempotency check might be fooled by a prior, broken attempt at the same
capability.

### Code review: three follow-up refinements

Commit `07f30da` ("address code review on tree-sitter-cli provisioning")
made three changes, each worth separating out:

**1. A migration for existing installs.** A fresh `omawsl_install_neovim`
run now gets the fix automatically — but the people actually hitting
issue #17 already *have* Neovim/LazyVim installed. They'd only see this
fix by re-running the editor picker and re-selecting Neovim, which nobody
does. omawsl's `migrations/` mechanism exists for exactly this shape of
problem: a versioned, one-time script that `omawsl update` runs so an
existing install converges to the same state a fresh install would reach,
without the user doing anything beyond running the update command they
already run periodically. `migrations/1786492800.sh`:

```bash
if [[ -d "$HOME/.config/nvim" ]]; then
  omawsl_install_treesitter_cli
fi
```

`[[ -d "$HOME/.config/nvim" ]]` is the same "is Neovim actually installed"
signal `app-neovim.sh`'s own clone guard and `doctor.sh` already use — not
`OMAWSL_EDITORS` (which only reflects choices made *through* omawsl's own
picker, not a config directory a user brought with them some other way).
Because `omawsl_install_treesitter_cli` is already idempotent, this
migration is safe to run on every single `omawsl update` forever, even
long after everyone's already picked up the fix once — it'll just hit the
wrapper-exists guard and return immediately.

**2. Isolating each editor's install call.** Before this fix,
`omawsl_install_apply_editor` called each editor's installer as a bare,
unguarded statement:

```bash
omawsl_install_neovim
omawsl_install_codex_cli
omawsl_install_gh_copilot
```

Under this file's `set -euo pipefail`, *any* single command that exits
non-zero aborts the entire script immediately. A flaky npm registry or a
corporate proxy blocking an outbound `npm install` inside
`omawsl_install_neovim` would abort the whole loop — meaning
`omawsl_install_codex_cli` and everything queued after it would silently
never run at all, even though the user had already picked all of those
editors. The fix wraps each call:

```bash
omawsl_install_neovim || echo "omawsl: failed to install Neovim - skipping, continuing with the rest." >&2
```

`cmd || echo "..."` converts a failing command into a logged warning
instead of a script-ending error — the `||`'s right-hand side only runs
if the left-hand side failed, and once it's run (successfully — `echo`
essentially never fails), the overall exit status of that line is zero,
so `set -e` has nothing to abort on. One editor's bad luck can no longer
take every other editor down with it — the same "log it, then keep going"
shape `orphan-tools.sh`'s update path already used elsewhere in the
project.

**3. Extracting the shared `omawsl_install_npm_cli_wrapper` helper.** The
install-a-package / write-a-wrapper / `chmod +x` shape in
`omawsl_install_treesitter_cli` above was already duplicated, nearly
line-for-line, in `app-codex-cli.sh` (for `@openai/codex`) and
`app-gh-copilot.sh` (for `@github/copilot`). The refactor pulls it into
one shared function in `install/lib.sh`:

```bash
omawsl_install_npm_cli_wrapper() {
  local package="$1" bin_name="$2"
  mise exec node@lts -- npm install -g "$package" || return 1

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/$bin_name" <<WRAPPER
#!/usr/bin/env bash
exec mise exec node@lts -- $bin_name "\$@"
WRAPPER
  chmod +x "$HOME/.local/bin/$bin_name"
}
```

Note the heredoc here is *unquoted* (`<<WRAPPER`, not `<<'WRAPPER'`) —
deliberately, since `$bin_name` needs to be substituted into the written
file's content (so the wrapper for `codex` execs `mise exec node@lts --
codex "$@"`, and the wrapper for `tree-sitter` execs `... tree-sitter
"$@"`). The one thing that must *not* get substituted is `"$@"` itself —
that needs to stay literal text in the written file, to be re-evaluated
every time the wrapper runs, not evaluated once right now while writing
it. That's what `\"\$@\"` (escaping both the `$` and the quotes) does
inside the unquoted heredoc: it tells bash "don't touch this token, write
it out exactly as `"$@"`."

Now `omawsl_install_treesitter_cli` is three lines:

```bash
omawsl_install_treesitter_cli() {
  if [[ -x "$HOME/.local/bin/tree-sitter" ]]; then
    return 0
  fi

  omawsl_install_npm_cli_wrapper tree-sitter-cli tree-sitter
}
```

The idempotency guard stays local to `omawsl_install_treesitter_cli`
rather than moving into the shared helper — the helper doesn't know or
care what "already installed" means for a given caller (codex and copilot
have no equivalent apt-package-collision problem to guard against), so
that decision correctly stays with the caller who actually needs it.

### Part B — filtering, not silencing, an npm warning

npm packages can declare **install scripts** — `preinstall`, `install`,
and `postinstall` entries in `package.json` that npm runs automatically,
as ordinary shell commands, the moment the package finishes downloading.
That's a real, well-known supply-chain risk: installing *any* dependency
can mean running its author's arbitrary code on your machine, not just
adding files to `node_modules`. Recent npm versions (11.16+) added an
**allow-scripts advisory** in response: whenever you `npm install`
something whose scripts haven't already been explicitly approved and
recorded, npm prints a warning naming the package and suggesting you run
`npm approve-scripts` to review it.

`tree-sitter-cli` has exactly such a script (`install: node install.js`),
so every `omawsl_install_npm_cli_wrapper` call for it started printing
this warning. The warning is genuine noise in this specific situation, not
a real problem to act on:

> Its suggested remedy, `npm approve-scripts`, errors out for a global
> install anyway since there's no project package.json to record the
> approval in (upstream npm/cli#9463), so the warning has no actionable
> fix and just makes a successful `omawsl update` look broken (#27).
> — commit `f5e1b64`

There's no project-level `package.json` for a global `-g` install to
persist an "I approved this" decision into, so the suggested fix is a
dead end — the warning would print on every single run, forever, with
nothing the user can do about it except learn to ignore it.

**The first attempt** reached for the broadest available lever:

```bash
mise exec node@lts -- npm install -g "$package" --loglevel=error || return 1
```

npm's logging has several severity tiers — `silent`, `error`, `warn`,
`notice`, `http`, `info`, `verbose`, `silly`, from quietest to noisiest —
and `--loglevel=X` tells npm to only print messages at severity `X` or
worse. `--loglevel=error` means "only show me `error`," which hides the
entire `warn` and `notice` tiers wholesale. That does silence the
allow-scripts warning — but it silences *everything else* in those two
tiers too, for all three callers of this shared function: dependency
deprecation notices, `EBADENGINE` warnings (your Node/npm version doesn't
match what a package expects), `ERESOLVE` warnings (conflicting
dependency version requirements), and npm's own "a newer version is
available" notices. None of those are the problem being fixed; all of
them went dark anyway, for every package this helper ever installs, from
now on.

**Code review caught this precisely**, and the fix (`ffdeba5`) replaced
the flag with output filtering:

```bash
omawsl_install_npm_cli_wrapper() {
  local package="$1" bin_name="$2"
  local npm_output
  npm_output="$(mise exec node@lts -- npm install -g "$package" 2>&1)" || {
    printf '%s\n' "$npm_output" >&2
    return 1
  }
  printf '%s\n' "$npm_output" | grep -v '^npm warn allow-scripts' || true

  # ... wrapper-writing unchanged ...
}
```

Walking through it:

- `2>&1` inside the command substitution redirects npm's stderr into the
  same stream as its stdout, so both are captured together into
  `npm_output` as one combined block of text — npm's warnings are
  reported on stderr, and this fix needs to inspect them, so they have to
  be captured rather than left to stream straight past the function
  uninspected.
- If the command fails (`||`), the raw, **completely unfiltered**
  captured output is printed to stderr before returning failure. A real
  failure's diagnostic text is never touched by the filtering below it —
  only a successful install's output gets filtered at all.
- On success, `grep -v '^npm warn allow-scripts'` reads the captured text
  and prints every line **except** ones matching that pattern. `-v`
  inverts grep's usual behavior (print matching lines) to print
  non-matching ones instead. The `^` anchors the match to the *start* of
  the line, and the pattern is the literal, fixed advisory prefix — not a
  bare substring search for the word "allow-scripts" that might also
  swallow an unrelated line that happens to mention it, but an exact
  "does this line begin with npm's own known warning text" check.
- `|| true` at the end matters for a subtler reason: `grep -v` exits with
  status `1` if *every* line it was given matched the pattern (i.e.,
  nothing survived to be printed) — a distinct case from "the pattern was
  never found at all," which behaves differently for plain `grep`, but
  `-v`'s "print nothing, because everything was filtered out" case still
  counts as failure for `grep`'s own exit code. Under `set -euo pipefail`
  (in force everywhere this function is sourced), that non-zero grep exit
  would otherwise abort the function — for a case that isn't actually a
  failure. `|| true` absorbs specifically that outcome.

The commit message's own justification for going this direction is worth
reading as the generalizable takeaway, not just the local fix:

> `--loglevel=error` suppressed npm's entire warn/notice tier
> (deprecations, EBADENGINE, ERESOLVE, update notices) for all 3 callers
> of the shared wrapper, not just the allow-scripts advisory, and diverged
> from the repo's existing "match the one known-benign message, keep
> everything else visible" precedent (`omawsl_install_azure_cli`'s curl
> 404 handling). Capture npm's output and filter only lines matching the
> advisory's stable "npm warn allow-scripts" prefix instead — verified
> live that a real install still surfaces an unrelated npm notice this
> way.
> — commit `ffdeba5`

The `--loglevel=error` version was a smaller diff — one flag, one line
changed. It was still the wrong fix, because "smaller change" and
"correct fix" are different measures. The habit worth keeping from this:
when a tool prints a warning you've specifically identified as
known-benign, filter for *that exact message* — a fixed string, an
anchored prefix, a specific error code — not for the whole class of
output it happens to belong to. The narrower filter costs a few more
lines of code up front, in exchange for never silently hiding a real
problem that just happens to share a severity level with the noise you
meant to suppress.

## 3. Exercise

Close this lesson and rebuild both fixes from scratch, blind, in
`practice/21-neovim-treesitter-and-npm-warnings/`.

**Part 1 (not automatically checked).** In
`practice/21-neovim-treesitter-and-npm-warnings/lib.sh`, write:

- `omawsl_install_npm_cli_wrapper <npm_package> <bin_name>` — installs
  `<npm_package>` globally via a private mise-managed Node runtime and
  writes an executable `$HOME/.local/bin/<bin_name>` wrapper that execs
  the tool through that same runtime, forwarding all arguments. A failed
  install must not leave a wrapper behind, and must cause this function
  to return non-zero.
- `omawsl_install_treesitter_cli` — no arguments, calls the helper above
  for `tree-sitter-cli`/`tree-sitter`, guarded by an idempotency check
  that looks for evidence *this function's own fix* has already been
  applied — not evidence that something merely answering to the name
  `tree-sitter` already exists somewhere on `$PATH`. Think back to why
  that distinction mattered in the Walkthrough before picking what to
  check for.

There is no check script for this part — it installs real software via a
real package manager, which practice exercises must never actually do.
Once you're done, compare your version against the real
`install/lib.sh`'s `omawsl_install_npm_cli_wrapper` and
`install/terminal/app-neovim.sh`'s `omawsl_install_treesitter_cli` in this
repo, purely to see how your idempotency check and wrapper-writing compare
in style — not as a grade.

**Part 2 (checked).** In
`practice/21-neovim-treesitter-and-npm-warnings/npm-filter.sh`, write a
function:

```
omawsl_filter_allow_scripts_warning
```

that takes no arguments. It reads npm's captured install output from its
own **standard input**, and writes every line to standard output
**except** lines that are the allow-scripts advisory — i.e. lines that
begin with the literal prefix `npm warn allow-scripts`. Every other line
— including npm warnings that have nothing to do with allow-scripts, and
ordinary success output — must be written through completely unchanged,
in its original order. The function must exit successfully (status `0`)
even in the edge case where *every* line of its input happens to match
and get filtered out, leaving nothing to print.

## 4. Check

Run:

```bash
practice/21-neovim-treesitter-and-npm-warnings/check.sh
```

It sources your `npm-filter.sh` and pipes several canned samples of npm
output through `omawsl_filter_allow_scripts_warning` — no real `npm` or
`mise` command runs, and nothing touches the network. One sample mixes
the full multi-line allow-scripts advisory block with an unrelated real
npm warning (a deprecation notice) and an ordinary success line; the
check asserts the advisory is gone from your output while the unrelated
warning and the success line both survive, byte-for-byte, in their
original order. A second sample contains *only* advisory lines, checking
that your function still exits `0` instead of erroring out once
everything gets filtered away. A third sample contains no advisory lines
at all, checking that ordinary input passes straight through untouched.

Every assertion prints its own `PASS:`/`FAIL:` line, and the script keeps
going after a failure rather than stopping at the first one, so a single
run shows you everything that's wrong at once. Read a `FAIL:` line as a
description of *behavior* that didn't match — e.g. "still contains
allow-scripts" means your filter's pattern is too narrow or anchored
wrong, while "unrelated warning was removed" means it's too broad (the
same "loglevel vs. precise filter" mistake this lesson is about, just
inside your own implementation instead of npm's flag surface). A passing
check means your filtering logic is behaviorally correct even if it's
structured completely differently from the real `grep -v` one-liner — a
`while read` loop, a `case` statement, an `awk` invocation, anything that
satisfies the same input/output contract is fine. If you want to compare
style purely as a study aid afterward, look at the real fix with
`git show ffdeba5 -- install/lib.sh` in this repo — but only after your
check passes, and only for style, never as the grade.
