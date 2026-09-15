# Lesson 18: Copilot Autopilot Mode

## 1. Concept

By this point in the build, omawsl already has a working shape for "ask the
user something once, remember the answer forever": a first-run picker asks a
handful of multiple-choice questions (which editors, which languages, which
font), each answer gets written to `choices.env` as a `KEY="value"` line, and
every later shell or command reads it back instead of re-asking. This phase
adds one more persisted choice — but it's a different *kind* of choice than
the ones before it, and that difference is the whole lesson.

GitHub Copilot CLI (`copilot`) can run in two very different modes. By
default, it stops and asks for confirmation before it edits a file, runs a
command, or fetches a URL. It also has two flags — `--autopilot` (work
through a whole task without stopping between steps) and `--allow-all`
(auto-approve every one of those requests instead of asking) — that together
turn it into something that acts continuously and unsupervised. That's
genuinely useful. It's also a real change in what can happen to your files
and your shell without you personally clicking "yes" each time.

Issue #2, which this phase closes, asked for `copilot` to just always start
this way — a hardcoded `alias copilot="copilot --autopilot --allow-all"` in
`configs/bashrc`, no questions asked. The design spec
(`docs/superpowers/specs/2026-08-09-copilot-autopilot-mode-design.md`)
explicitly rejects that, quoting the project's own stated principle from
`install/first-run-choices.sh`: *"Nothing is pre-selected by default… a
public tool should not surprise-install anything the user didn't explicitly
ask for."* Every other alias in `configs/bashrc` — `alias g='git'`, `alias
d='docker'` — is a harmless shorthand. This one changes a safety property:
whether an AI agent asks before it acts. So instead of a hardcoded alias, it
becomes an explicit **opt-in**: a feature that stays off unless the user
affirmatively turns it on, as opposed to an **opt-out** feature that starts
on and has to be manually disabled. When the choice is safety-relevant,
opt-in is the only defensible default — the cost of a user never finding out
about a convenience feature is "they miss out on a shortcut"; the cost of a
user never finding out their AI CLI auto-approves everything is much worse.

That decision shapes everything else in this phase:

- The opt-in question can't live in the general picker (`OMAWSL_LANGUAGES`,
  `OMAWSL_EDITORS`, …) — it only makes sense to ask *after* the user has
  already chosen to install GitHub Copilot CLI at all. So it has to be a
  second, follow-up prompt, conditionally triggered by the first one.
- It has to fire from **two** places, not one: the normal first-run
  installer, and `omawsl install editor gh-copilot` — the "add this tool
  later" path a user who skipped Copilot CLI at first-run takes when they
  change their mind. A safety-relevant opt-in that only gets asked on day
  one, and silently defaults to "off, forever" for anyone who installs the
  tool afterward, would be a gap, not a feature. Both call sites need to
  share the exact same guard logic (ask once, don't nag), so it's written
  once as a shared helper and called from both places — not copy-pasted
  twice, which would risk the two copies drifting apart over time.
- The choice, once made, has to be **persisted** — written to disk so it
  survives closing the terminal — the same `choices.env` mechanism every
  other first-run answer uses. A boolean choice like this is really just a
  degenerate case of the same "ask once, remember forever" pattern lesson 1
  built `omawsl_save_choice`/`omawsl_load_choice` for.
- Uninstalling GitHub Copilot CLI has to **clear** that persisted choice, not
  leave it lying around. Otherwise, uninstall-then-reinstall silently
  inherits whatever the answer was months ago, without the re-prompt firing
  — a stale answer masquerading as a fresh decision.
- And separately, `omawsl doctor` — the command that reports what's actually
  installed versus what's still pending — had a real bug where it could
  under-report tools that were installed but never formally *selected*
  through the picker. Not really about autopilot mode specifically, but
  fixed in this same commit range, and worth understanding because it's a
  general shape of bug: a status check that only cross-references *intent*
  (what was selected) misses reality (what's actually there) whenever
  something got installed through a side door.

One more piece of vocabulary before the walkthrough: a shell **alias** is a
shorthand your shell substitutes in when you type a command interactively.
`alias copilot="copilot --autopilot --allow-all"`, once defined, means that
typing `copilot` at a prompt runs `copilot --autopilot --allow-all` instead
— the shell rewrites what you typed before running it. Aliases are defined
in a shell startup file — `~/.bashrc` for an interactive bash session — and
only take effect in shells that source that file; a script that calls
`/usr/bin/copilot` (or even just `copilot`) directly, non-interactively,
never sees them. That's exactly the mechanism this phase uses to make the
opt-in real: nothing about `copilot` itself changes, but *if and only if*
the user opted in, every new interactive shell quietly defines an alias that
makes typing `copilot` behave differently than running the program directly
would.

## 2. Walkthrough

### The shared helper: `install/lib.sh`

```bash
omawsl_prompt_copilot_autopilot_if_needed() {
  local picked="$1" existing="$2"
  omawsl_list_has "$picked" "GitHub Copilot CLI" || return 0
  omawsl_list_has "$existing" "GitHub Copilot CLI" && return 0
  [[ -z "$(omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT)" ]] || return 0

  local answer
  answer="$(gum choose --header "GitHub Copilot CLI: always start in autopilot mode (auto-approves all tool use, no confirmation)?" \
    "No - interactive by default (recommended)" "Yes - autopilot + allow-all")" || return 0
  omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT "$answer"
}
```

Three guard lines, each an early `return 0` ("nothing to do, exit quietly"),
each checking a different reason the prompt should *not* fire:

1. `omawsl_list_has "$picked" "GitHub Copilot CLI" || return 0` — if Copilot
   CLI isn't even in this run's selection, there's nothing to ask about.
2. `omawsl_list_has "$existing" "GitHub Copilot CLI" && return 0` — if it was
   *already* selected before this run (i.e. it's not new), don't re-ask.
   This is what makes "picked" and "existing" two separate arguments instead
   of one: the function needs to distinguish "just chosen this run" from
   "chosen previously," and that distinction only exists if the caller
   passes both the new selection and what was there before it.
3. `[[ -z "$(omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT)" ]] || return 0` —
   if an answer is already persisted (from some earlier run), don't ask
   again regardless of the other two checks.

Only if Copilot CLI is newly picked *and* nothing is persisted yet does the
function reach the `gum choose` call. Notice it calls `gum choose` directly
rather than going through `omawsl_prompt_single` (the wrapper
`install/first-run-choices.sh` defines for `OMAWSL_FONT_MODE`'s identical
two-option shape). That's not an oversight — `omawsl_prompt_single` lives in
`install/first-run-choices.sh`, and `install/lib.sh` is a lower-level file
that `first-run-choices.sh` itself sources. Having `lib.sh` reach back up to
call something defined in a file that depends on it would be a **circular
dependency** — file A needs file B, and file B needs file A — which bash
has no clean way to resolve. Calling the same underlying `gum choose`
primitive directly avoids introducing that cycle, at the cost of one
duplicated line of `gum` invocation. The design spec explicitly considered
and rejected `gum confirm` (a real, simpler-sounding yes/no prompt) for the
same reason it avoided `omawsl_prompt_single`: this project has never used
`gum confirm` anywhere, and introducing a second UI primitive just for this
one boolean would be a bigger surface to maintain than reusing the
`gum choose` shape everything else already uses.

The `|| return 0` on the `gum choose` call itself is not there by accident
either — it was added in a follow-up fix
(`1f3a0e6 fix: address final-review findings for copilot autopilot mode`)
after a real bug: `gum choose` returns non-zero if the user cancels it (Esc,
Ctrl-C) or if `gum` isn't on `PATH` at all. Watch what happens to a plain
assignment under this project's universal `set -euo pipefail`:

```bash
local answer
answer="$(gum choose ...)"
```

This is written as **two statements**, not one. That matters. A tempting
one-liner, `local answer="$(gum choose ...)"`, has a classic bash trap: when
`local` and a command substitution are combined on one line, the exit status
bash's `$?` sees afterward is `local`'s own exit status (almost always `0`),
not the command substitution's — so a failing `gum choose` inside a combined
`local var=$(...)` would be silently swallowed, and `set -e` would never
even notice. Splitting `local answer` and `answer="$(...)"` into two lines
avoids that trap: the second line is a plain assignment, so *its* exit
status genuinely is whatever `gum choose` returned. But that then creates
the opposite problem: under `set -e`, a plain assignment statement whose
command substitution fails **does** abort the script right there — so
without the `|| return 0`, a user pressing Ctrl-C on this one prompt would
have aborted the *entire* install, mid-run, for a reason that has nothing to
do with anything else the installer was doing. The fix keeps both correct
behaviors at once: a real failure is *not* swallowed silently (unlike the
combined-`local` trap), but it also doesn't crash the caller — it just
returns as if nothing had been persisted, so the prompt correctly fires
again next time instead of locking in a phantom answer or taking down the
whole run.

### Two call sites, one helper

`install/first-run-choices.sh`, right after the editors picker:

```bash
OMAWSL_EDITORS="$(omawsl_prompt_multi "Editors & AI tooling (space to select, enter to confirm)" \
  "VS Code" "Neovim" "opencode" "Cursor" \
  "Claude Code CLI" "Codex CLI" "GitHub Copilot CLI" "Antigravity CLI")"

omawsl_prompt_copilot_autopilot_if_needed "$OMAWSL_EDITORS" ""
```

The second argument is a literal empty string — on a first run, "existing"
selections are always empty, so the "was it already selected before"
guard can never fire here; the prompt fires purely based on whether Copilot
CLI shows up in this run's `$OMAWSL_EDITORS`.

`bin/omawsl-sub/install.sh`'s `omawsl_install_apply_editor` — the retrofit
path, used by both `omawsl install editor gh-copilot` and the interactive
`omawsl install` picker:

```bash
omawsl_install_apply_editor() {
  local picked="$1" existing="$2"
  omawsl_prompt_copilot_autopilot_if_needed "$picked" "$existing"
  local merged; merged="$(omawsl_merge_csv "$existing" "$picked")"
  export OMAWSL_EDITORS="$merged"
  omawsl_save_choice OMAWSL_EDITORS "$merged"
  local f
  for f in app-vscode app-neovim app-opencode app-cursor app-claude-cli app-codex-cli app-gh-copilot app-antigravity-cli; do
    ...
```

Here `existing` is genuinely populated — whatever editors were selected
before this call — so the "already selected" guard does real work: running
`omawsl install editor gh-copilot` a second time, after Copilot CLI is
already installed, correctly does not re-prompt. This is the exact scenario
the fresh-install call site can't exercise (its `existing` is always empty),
which is why this phase needed real test coverage on *both* call sites, not
just one.

### The alias itself: `configs/bashrc`

```bash
if command -v copilot &>/dev/null; then
  OMAWSL_COPILOT_AUTOPILOT="$(grep -m1 '^OMAWSL_COPILOT_AUTOPILOT=' "${OMAWSL_STATE_DIR:-$HOME/.local/state/omawsl}/choices.env" 2>/dev/null | cut -d'"' -f2)"
  if [[ "$OMAWSL_COPILOT_AUTOPILOT" == "Yes"* ]]; then
    alias copilot="copilot --autopilot --allow-all"
  fi
  unset OMAWSL_COPILOT_AUTOPILOT
fi
```

Two design decisions worth pulling out. First: this reads `choices.env` with
raw `grep`/`cut`, exactly like the pre-existing `OMAWSL_FONT_MODE` block
does — it deliberately does **not** `source` `choices.env`, for the same
reason `omawsl_load_choice` never does (lesson 1): a persisted value could
contain shell metacharacters, and `.bashrc` runs on *every* new terminal, so
sourcing untrusted file content there would be a standing command-injection
risk, not a one-time one. Second: `command -v copilot &>/dev/null` gates the
whole block, both for correctness (if Copilot CLI was uninstalled, the alias
must not exist regardless of what's persisted — matching every other
tool-conditional block in this file, like the `lazygit`/`lazydocker` ones
right above it) and for cost (the common case — most users don't have
`copilot` installed — skips the subshell fork and file read entirely,
instead of paying for it on every single new shell).

That block's *placement* in the file is itself the fix for a real bug, found
during final review (same `1f3a0e6` commit as the cancelled-prompt fix
above). It was originally placed up near the `lazygit` alias, *before* this
line, further down in the same file:

```bash
if [ -d "$HOME/.local/bin" ]; then
  export PATH="$HOME/.local/bin:$PATH"
fi
```

`copilot` has no `apt` package — like `lazydocker`, it installs a wrapper
into `$HOME/.local/bin`, which isn't on `PATH` yet at the point in the file
where the alias block originally sat. `command -v copilot` would therefore
always fail there, and the alias would never actually get defined, in any
real shell, ever — the exact same class of bug lesson 1 already called out
for `mise`: *"checking for a tool before its directory is on PATH always
fails and silently skips."* The fix was purely to move the block, unchanged,
to just after that PATH export — right alongside the `lazydocker` block,
which has the identical ordering requirement and says so in its own
comment. The lesson here isn't really about Copilot CLI specifically: any
time you add a conditional block that depends on a tool being "found," ask
where in the file that tool's own install step actually puts it, and
whether anything earlier in the file has made that location reachable yet.

### Clearing the choice on uninstall: `uninstall/app-gh-copilot.sh`

```bash
omawsl_uninstall_gh_copilot() {
  if command -v mise &>/dev/null; then
    mise exec node@lts -- npm uninstall -g @github/copilot || true
  fi
  rm -f "$HOME/.local/bin/copilot"

  if gh extension list 2>/dev/null | grep -q '^gh-copilot\|^gh copilot'; then
    gh extension remove gh-copilot || true
  fi

  omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT ""

  local editors
  editors="$(omawsl_load_choice OMAWSL_EDITORS)"
  omawsl_save_choice OMAWSL_EDITORS "$(omawsl_remove_from_csv "$editors" "GitHub Copilot CLI")"

  echo "omawsl: GitHub Copilot CLI removed."
}
```

`omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT ""` persists an empty value —
functionally identical to never having answered, so the guard in
`omawsl_prompt_copilot_autopilot_if_needed` sees it as unanswered and
re-prompts on the next install. That's the core of what this phase's
outline calls "clearing that one boolean choice correctly through install
and uninstall": the persisted value has exactly two meaningful states from
the guard's point of view — "answered" and "not answered" — and uninstall
has to put it back into the second one, not just leave a stale "Yes" (or
"No") sitting there forever.

The line right after it — removing `"GitHub Copilot CLI"` from
`OMAWSL_EDITORS` — was added in a second review pass
(`545bb05 fix: address PR #8 review findings`), for a subtler reason. This
uninstall script supports being run **directly** (`bash
uninstall/app-gh-copilot.sh`, which the test suite for this file does), not
only via `bin/omawsl-sub/uninstall.sh`'s general dispatcher, which has its
own separate step for removing an item from its `choices.env` list. Direct
invocation bypasses that separate step entirely. Without this line, a
direct uninstall would clear the autopilot answer but leave
`"GitHub Copilot CLI"` still listed as selected — so a later reinstall would
see it as "already existing" (the second guard in
`omawsl_prompt_copilot_autopilot_if_needed`) and silently skip the
re-prompt, even though the autopilot answer had just been cleared. Fixing
one piece of persisted state without checking whether something else
depends on it is a recurring bug shape worth internalizing: this feature
touches *two* pieces of persisted state (`OMAWSL_COPILOT_AUTOPILOT` and
membership in `OMAWSL_EDITORS`), and uninstall has to keep both consistent
with each other, not just one of them.

A third pass (`28f17be fix: don't let a failing gh extension remove skip
state cleanup on uninstall`) added the `|| true` on `gh extension remove
gh-copilot`. Under `set -euo pipefail`, if that command failed — a stale
auth token, no network, a corrupted extension — the function would abort
*right there*, before ever reaching the two `omawsl_save_choice` cleanup
calls below it, leaving `choices.env` stale in exactly the way this phase
exists to prevent. `|| true` makes that one step best-effort (matching the
npm uninstall step just above it, which was already written that way from
the start) specifically so a failure in an unrelated cleanup step can never
prevent the state cleanup that actually matters from running. This is the
same principle as the `gum choose` cancellation fix earlier in this lesson,
applied to a different command: under `set -e`, *any* unguarded command
failure partway through a function can silently skip everything after it —
so the commands whose success genuinely doesn't matter to the outcome need
to say so explicitly (`|| true`), rather than accidentally gating something
that does matter.

### The `doctor` fix: `bin/omawsl-sub/doctor.sh`

Not really about autopilot mode, but fixed in the same commit range and
worth understanding on its own. Before:

```bash
while IFS= read -r slug; do
  label="$(omawsl_item_label "$slug")"
  omawsl_list_has "$selected" "$label" || continue
  if "$check_fn" "$slug"; then
    echo "  [OK]      $label"
  else
    echo "  [PENDING] $label - run: omawsl install $category $slug"
  fi
done < <(omawsl_item_slugs "$category")
```

That `omawsl_list_has "$selected" "$label" || continue` line — "skip
anything not in the persisted selection" — silently dropped every item that
was actually *installed* but never *selected* through omawsl's own picker:
something pre-existing on the machine before omawsl ever ran, or something
installed via a different path that bypasses the picker's guard entirely
(the orphan-tools update mechanism, covered in a later phase). `doctor`'s
whole job is to report "what's installed/configured" — but this loop only
ever checked the *intent* list, never actual reality, for anything doctor
hadn't been told about through the front door.

After:

```bash
while IFS= read -r slug; do
  label="$(omawsl_item_label "$slug")"
  if "$check_fn" "$slug"; then
    echo "  [OK]      $label"
  elif omawsl_list_has "$selected" "$label"; then
    echo "  [PENDING] $label - run: omawsl install $category $slug"
  fi
done < <(omawsl_item_slugs "$category")
```

The `continue` guard is gone. Now every registered slug in the category gets
checked against real, on-disk state (`$check_fn`) *first*, regardless of
selection — `[OK]` if it's actually there. Only if it's *not* actually there
does selection matter at all: `[PENDING]` if it was selected but is
missing, otherwise silent. An item that's neither installed nor selected
stays silent either way — matching the "don't nag about things nobody
asked for" principle from earlier in this lesson; the fix widens what
counts as "installed," it doesn't start reporting on things the user never
touched. The general shape worth remembering: a report that cross-checks
two independent sources of truth (what was chosen, vs. what's really there)
has to check the *real* one as its primary signal and treat the *intent*
list as a fallback for the "still pending" case — not the other way
around, and not exclusively one or the other.

## 3. Exercise

Close this lesson and rebuild this phase's opt-in/persist/alias/uninstall
pattern from scratch, blind, in `practice/18-copilot-autopilot-mode/`.

You're given `practice/18-copilot-autopilot-mode/choices.sh` — a
trimmed copy of lesson 1's `omawsl_save_choice`/`omawsl_load_choice` (plus
`omawsl_choices_dir`, honoring `OMAWSL_STATE_DIR`). Don't change it; source
it from your own file.

Build `practice/18-copilot-autopilot-mode/autopilot.sh`. It must be
runnable as a real command-line entry point (not just a library to be
sourced), dispatching on its first argument:

```
bash autopilot.sh install yes
bash autopilot.sh install no
bash autopilot.sh uninstall
```

This lesson trims away the real project's full `gum`-choose label strings
("Yes - autopilot + allow-all", etc.) — your persisted value is exactly the
literal string `"yes"` or `"no"`, under the same key the real project uses:
`OMAWSL_COPILOT_AUTOPILOT`. The alias line, when it exists, must match the
real project exactly: `alias copilot="copilot --autopilot --allow-all"`.

Implement two functions and wire them into the dispatch:

- **`omawsl_autopilot_install <yes|no>`** — persist the answer as
  `OMAWSL_COPILOT_AUTOPILOT` via `omawsl_save_choice`. If the answer is
  `"yes"`, the alias line must end up present in `$HOME/.bashrc`, exactly
  once, even if this is called with `"yes"` more than once in a row. If the
  answer is `"no"`, the alias line must **not** be present in
  `$HOME/.bashrc` afterward — including the case where a prior call already
  added it and this call is flipping the answer back off. Every other line
  already present in `$HOME/.bashrc` must be left exactly as it was; this
  function only ever adds or removes its own one line, never rewrites the
  whole file.
- **`omawsl_autopilot_uninstall`** — clear the persisted choice (an empty
  value, via `omawsl_save_choice`, same as a never-answered state) and
  remove the alias line from `$HOME/.bashrc` if it's there. Calling this
  when nothing was ever installed must not error.

One implementation detail worth knowing before you start, not after
debugging it: `grep -v PATTERN file`, when every single line in `file`
matches `PATTERN` (so the inverted output is empty), exits with status `1`
— "no lines selected" is treated as failure, not success. Under
`set -euo pipefail`, that will abort your script the moment you try to
remove the one and only line in a fresh `.bashrc` unless you guard it.

Don't look back at this lesson's code while you write it. Get something you
believe is correct, then move to the Check step.

## 4. Check

Run:

```bash
practice/18-copilot-autopilot-mode/check.sh
```

It never touches your real `$HOME` — every invocation of your
`autopilot.sh` runs with both `HOME` and the working directory redirected
to a throwaway scratch directory, created fresh and deleted when the check
finishes. Within that sandbox, it drives your script through its real
`install`/`uninstall` entry points (never by sourcing it and poking at
internal functions directly) and checks the same things a real user's shell
and `choices.env` would show afterward: whether the alias line is present
or absent in `~/.bashrc`, whether it appears exactly once even after
running `install yes` twice, whether flipping from `yes` to `no` cleans up
a previously-added alias, whether unrelated lines already in `~/.bashrc`
survive untouched, and whether `uninstall` both removes the alias and
clears the persisted choice back to empty.

Every assertion prints its own `PASS:`/`FAIL:` line, and the check keeps
going through all of them even after an early failure, so one run shows you
everything that's wrong rather than just the first thing. Read a `FAIL:`
line as a description of *behavior* that didn't match — e.g. "the alias
line was still present in `~/.bashrc` after 'uninstall'" tells you your
uninstall path isn't removing the line, not which line number to fix. A
passing check means your `autopilot.sh` is behaviorally correct even if it
doesn't look anything like the original — different function bodies,
different intermediate variables, `sed` instead of `grep -v`/temp-file, all
fine. If you want to compare approaches purely as a study aid afterward,
you can look at the real project's `install/lib.sh`
(`omawsl_prompt_copilot_autopilot_if_needed`), `configs/bashrc`, and
`uninstall/app-gh-copilot.sh` — but only after your check passes, and only
for style, never as the grade.
