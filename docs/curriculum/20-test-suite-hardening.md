# Lesson 20: Test Suite Hardening

## 1. Concept

Every earlier lesson was about a bug in the *product* — the installer did
the wrong thing, or the doctor command missed a real problem. This phase
is about a different, easy-to-underrate category: bugs in the things that
are supposed to be *checking* the product.

A quick vocabulary grounding, since this whole phase is about naming this
category precisely:

- A **false positive** is a warning or test failure that fires when
  nothing is actually wrong. It's the "boy who cried wolf" problem applied
  to tooling: the first few times a check cries wolf, people investigate.
  After enough false alarms, people start ignoring the check entirely —
  including the one time it's right. A false positive is just as much a
  bug as a **false negative** (a check that stays silent when something
  *is* wrong) — both mean the check's output no longer matches reality.
- **Flakiness** means a test's pass/fail result isn't determined purely by
  whether the code is correct — it depends on something incidental, like
  which order things happen to run in, or how much of some shared resource
  happens to be free at the moment. A flaky test erodes trust the same way
  a false positive does: eventually someone just re-runs the suite until
  it's green and stops reading the failure.
- A **leak**, in the resource sense (not the "secrets" sense), means
  something gets allocated — memory, a file, a directory, a network
  connection — and never gets freed, even after the code that needed it is
  done. One leak is nothing. A leak that happens once per test, in a suite
  with hundreds of tests, run over and over in CI, becomes a slow-motion
  crash.
- **Test drift** is what happens when a test hardcodes a scripted sequence
  of inputs against a piece of interactive code, and *that code* later
  changes shape — gains a new prompt, drops one, reorders two — without
  the test's scripted sequence being updated to match. The test doesn't
  necessarily fail loudly. It can just quietly start feeding the wrong
  answer to the wrong question.

This phase walks through one real bug from each category, all found and
fixed in quick succession right after the Copilot-autopilot and
starship-default-prompt features landed (Lessons 18 and 19 territory):

1. **A false positive that only makes sense under the old prompt.**
   `zoxide` (the `cd` replacement this project installs) ships its own
   internal self-check — confusingly, zoxide's own docs and error text
   also call it a "doctor" check, unrelated to this project's own
   `bin/omawsl doctor` subcommand. That self-check starts false-triggering
   the moment `starship` (this project's prompt) is also installed, not
   because anything is actually broken.
2. **A leak inside the test harness itself.** Three helper functions used
   by (almost) every one of this project's hundreds of test files were
   each allocating a temp directory in the wrong place — invisible in any
   single test run, catastrophic in aggregate.
3. **Drift between a scripted end-to-end test and the real prompts it's
   driving.** An earlier phase added one new interactive prompt to the
   install flow. The end-to-end test that scripts every prompt's answer,
   in order, wasn't updated — so every answer after that point silently
   landed on the wrong question.

None of these are "the installer is broken." All three are "the thing
that's supposed to tell you whether the installer is broken was itself
wrong" — which is a more insidious failure mode, because a broken *check*
doesn't announce itself the way a broken *feature* does. It just quietly
stops being trustworthy.

## 2. Walkthrough

### 2a. The zoxide doctor false positive, and why the first fix was too broad

Two commits, back to back, tell this story. The first (`4eb9813`, just
before this phase's range starts, for context) diagnosed a real bug:
`starship` takes over `$PROMPT_COMMAND` — the shell variable bash
re-evaluates before printing every prompt — as documented upstream
(`starship/starship#6093`), and it has to be sourced *after* zoxide's own
init for the handoff to work. Starship's init doesn't discard whatever was
already in `$PROMPT_COMMAND` — it stashes it into a different variable,
`STARSHIP_PROMPT_COMMAND`, which its own `starship_precmd` function still
runs every prompt. So zoxide's hook (`__zoxide_hook;`) keeps firing
correctly either way. But zoxide *also* ships a self-check that runs
inside its `z`/`zi` wrapper functions on every `cd`, and that self-check
does something cruder than actually testing whether the hook fires — it
does a literal substring search for `__zoxide_hook` inside
`$PROMPT_COMMAND`. Once starship has rewritten that variable down to the
literal string `"starship_precmd"`, the substring is gone, and zoxide
prints `zoxide: detected a possible configuration issue` — a false
positive, confirmed against the real binaries (`bash -i -c 'cd /tmp'`),
not a documentation guess.

`4eb9813`'s fix used zoxide's own documented opt-out: setting
`_ZO_DOCTOR=0` disables that self-check without touching hook
installation (which is a separate, unconditional code path in zoxide's
init script — this opt-out can't accidentally break the hook itself). But
it set that variable **unconditionally**, for every zoxide user:

```bash
if command -v zoxide &>/dev/null; then
  export _ZO_DOCTOR=0
  eval "$(zoxide init bash)"
  alias cd='z'
fi
```

This is where "fixing a false positive" itself introduced a new bug — a
**false negative** this time. `_ZO_DOCTOR=0` doesn't say "suppress the
specific starship interaction issue" — it says "never run this self-check
again, for any reason." On a machine with zoxide but *no* starship,
`$PROMPT_COMMAND` is never rewritten, the substring check would have
worked correctly, and a real configuration problem (say, a mangled shell
init file that actually did break the hook) would now be silently
swallowed. A code reviewer caught this before it shipped as the final
answer (PR #21), and `e87e573` narrowed the fix to exactly the condition
that causes the false positive:

```bash
if command -v zoxide &>/dev/null; then
  if command -v starship &>/dev/null; then
    # ... (full rationale in the comment, unchanged from above) ...
    _ZO_DOCTOR=0
  fi
  eval "$(zoxide init bash)"
  alias cd='z'
fi
```

Two changes worth noticing individually:

- The suppression is now nested inside a second `command -v starship`
  check, so it only fires on exactly the hosts where the substring check
  is known to be wrong. A zoxide-only host still gets the real diagnostic.
  This is the general lesson under "false positive" as its own bug class:
  **the fix for a false positive should be as narrow as the condition
  that causes it — never broader**, because a fix broader than the actual
  cause doesn't just suppress the noise, it suppresses the *signal* too,
  on inputs the bug report never covered.
- The commit also corrects a factual error in the surrounding comment:
  the original comment claimed `_ZO_DOCTOR` had to be `export`ed because
  "the check runs later, inside the `z`/`zi` wrapper functions... not at
  init-script-generation time" — reasoning that sounds plausible but
  doesn't actually require `export`. `export` matters when a variable
  needs to be visible to a *child process* (a separate `bash` invocation).
  zoxide's `__zoxide_doctor` check is a plain bash function, defined and
  called inside the *same* interactive shell — no process boundary is
  ever crossed, so a bare assignment (`_ZO_DOCTOR=0`, no `export`) is
  every bit as visible to it as an exported one. This is worth sitting
  with even though it's a one-word diff: a comment that gives a plausible
  but wrong *reason* for correct code is its own quiet hazard — the next
  person to touch this file has no way to tell, from the comment alone,
  that the reasoning was never actually load-bearing.

The regression test for this lives in `tests/a_shell_test.bats` and is
worth reading for a different reason: it's explicitly *not* stubbed.

```bash
@test "cd does not trigger zoxide's doctor false positive when starship is also installed" {
  command -v zoxide &>/dev/null || skip "zoxide not installed on this test host"
  command -v starship &>/dev/null || skip "starship not installed on this test host"
  export HOME="$BATS_TEST_TMPDIR/home_zoxide_doctor"
  mkdir -p "$HOME"
  bash "$REPO_ROOT/install/terminal/a-shell.sh"
  run bash -i -c 'cd /tmp'
  [ "$status" -eq 0 ]
  [[ "$output" != *"zoxide: detected a possible configuration issue"* ]]
}
```

Every other test in this project stubs dangerous or slow commands (Lesson
1's `stub_command`/`export -f` trick). This test can't: the bug lives in
the *interaction* between two real init scripts' real behavior, not in
any decision this project's own code makes. A stubbed `zoxide` or
`starship` wouldn't reproduce starship's actual `$PROMPT_COMMAND`
rewriting, so there'd be nothing left to catch a regression. `skip`
(a bats builtin) lets the test degrade gracefully to "not run" on a
machine that doesn't happen to have both real binaries installed, rather
than failing for an unrelated reason. This is a second general lesson:
**not every behavior can be tested behind a stub** — when the bug is
specifically about how two real, external programs interact, the test has
to use the real programs, and everything else (isolated `$HOME`, `skip`
when the precondition isn't met) is built around making that safe and
optional rather than trying to fake the interaction away.

### 2b. The stub-command test harness's own temp-directory leak

`tests/helpers/stubs.bash` (introduced in Lesson 1) is loaded by nearly
every `.bats` file in this project. Three of its functions each need a
scratch directory of their own:

- `stub_init` — a log file every stubbed command appends its invocation
  to, plus a directory backing `stub_command_output_for`'s per-command
  response registry.
- `gum_stub_init` — a directory holding the queued canned answers for the
  `gum` stub (this is the mechanism the next section is about).
- `stub_hide_command` — builds a directory of symlinks to (almost) every
  real binary on the system, to make a specific command look "not
  installed" without touching the real `$PATH` directories.

Before this phase, all three called `mktemp` or `mktemp -d` bare, with no
argument telling it where to put the new file or directory:

```bash
stub_init() {
  STUB_LOG="$(mktemp)"
  STUB_OUTPUT_REGISTRY_ROOT="$(mktemp -d)"
}
```

Called with no arguments, `mktemp` creates its file or directory inside
the system's general-purpose temp directory (`/tmp` on Linux, or wherever
`$TMPDIR` points) — a location nothing in this project owns or manages.
Contrast that with `bats` (the test framework this project's suite runs
under), which allocates its **own** scoped temp directories per test run
and per test, and registers a cleanup (an `EXIT` trap — code that runs
when the process exits, success, failure, or signal) that `rm -rf`s the
whole thing in one shot once the run finishes. `$BATS_TEST_TMPDIR` is the
one scoped to a single test; it exists precisely so a test can write
scratch files without polluting anything outside bats' own bookkeeping.

A bare `mktemp` sidesteps all of that. Every directory it creates lands
outside `$BATS_TEST_TMPDIR`, so bats' cleanup never finds it, has no way
to know it exists, and never removes it — even when the whole suite
finishes cleanly, and even if a test run is interrupted with `Ctrl-C`
(`SIGINT`) partway through, which is exactly when bats' own `EXIT` trap
still fires but has no idea these directories are there to clean up
either. Each one of these leftover directories is small on its own. The
commit message names the actual severity multiplier: `stub_hide_command`
alone symlinks essentially every binary under `/usr/local/sbin`,
`/usr/local/bin`, `/usr/sbin`, `/usr/bin`, `/sbin`, `/bin`, and a few
more — **over 1,000 inodes** per call — and it's called from `setup()` in
roughly 90+ test files across the suite. An **inode** is the filesystem's
bookkeeping record for one file or directory — every filesystem has a
finite pool of them, separate from raw disk space, and running out of
free inodes fails new file creation with "no space left on device" even
when there's plenty of actual disk space free. Ninety-some leaked
1,000-inode directories, accumulated across every CI run and every local
`bats` invocation a developer ever ran, is exactly the shape of leak that
eventually exhausts that pool (tracked as issue #13) — invisible in any
one test, inevitable in aggregate.

The fix (`f60a3f3`) is one word's worth of change per call site — passing
a template argument that anchors the new file or directory under
`$BATS_TEST_TMPDIR` instead of letting `mktemp` pick its own default
location:

```bash
stub_init() {
  STUB_LOG="$(mktemp "$BATS_TEST_TMPDIR/stub_log.XXXXXX")"
  STUB_OUTPUT_REGISTRY_ROOT="$(mktemp -d "$BATS_TEST_TMPDIR/stub_output_registry.XXXXXX")"
}
```

`mktemp`'s template argument works the same way with or without a
directory prefix: the trailing run of `X` characters gets replaced with
random characters to guarantee a unique name, and giving it a full path
(rather than a bare template) tells `mktemp` to create the file at that
path instead of inside its own default temp directory.
`stub_hide_command` and `gum_stub_init` get the identical one-line
treatment. Nothing about *what* these functions do changes — same log
file, same registry, same symlink shadow directory — only *where* they're
allowed to put it. That's the whole fix, and it's worth noticing how
small it is relative to the blast radius of the bug: the leak wasn't a
design flaw in the stubbing approach, it was one missing argument,
repeated three times, that happened to sidestep the cleanup mechanism
this project already had.

The commit also adds regression coverage directly in
`tests/stubs_test.bats` — testing the test helpers themselves:

```bash
@test "stub_init scopes its temp files under BATS_TEST_TMPDIR instead of leaking to system tmp" {
  stub_init
  [[ "$STUB_LOG" == "$BATS_TEST_TMPDIR"/* ]]
  [[ "$STUB_OUTPUT_REGISTRY_ROOT" == "$BATS_TEST_TMPDIR"/* ]]
}
```

The assertion isn't "the file exists" or "the file is writable" — a
leaking version of `stub_init` would pass both of those just fine. The
assertion is specifically about *location*: does the path bash actually
got back start with `$BATS_TEST_TMPDIR`, or did it land somewhere else.
That's the general shape of a regression test for a leak: assert on
*where the resource was allocated*, not merely that allocation succeeded.

### 2c. Prompt drift in the install end-to-end test

`tests/install_test.bats` runs the entire `install.sh` in one shot,
against the stubbed `gum` from Lesson 1's `tests/helpers/stubs.bash`. The
`gum` stub is a small FIFO (first-in, first-out) queue: `gum_stub_respond
"answer"` appends one canned answer to the queue, and every time the code
under test calls the real `gum choose` (intercepted by the stub, via the
same `export -f` mechanism covered in Lesson 1), the stub pops the *next*
queued answer off the front, regardless of which specific prompt is
asking. The queue has no idea what question it's answering — it just
hands back whatever's next in line.

That means the test's block of `gum_stub_respond` calls is really a
script of assumed prompt order — "the first prompt asked will be network
mode, so queue that answer first; the second will be Docker mode, queue
that answer second" — and so on. It only stays correct as long as the
*real* sequence of prompts the installer fires matches, one-for-one, the
order this list assumes.

An earlier phase (Copilot autopilot support, `install/lib.sh`'s
`omawsl_prompt_copilot_autopilot_if_needed`) added exactly the kind of
change that breaks that assumption without touching this test file at
all:

```bash
omawsl_prompt_copilot_autopilot_if_needed() {
  local picked="$1" existing="$2"
  omawsl_list_has "$picked" "GitHub Copilot CLI" || return 0
  omawsl_list_has "$existing" "GitHub Copilot CLI" && return 0
  [[ -z "$(omawsl_load_choice OMAWSL_COPILOT_AUTOPILOT)" ]] || return 0

  local answer
  answer="$(gum choose --header "GitHub Copilot CLI: always start in autopilot mode..." \
    "No - interactive by default (recommended)" "Yes - autopilot + allow-all")" || return 0
  omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT "$answer"
}
```

`install/first-run-choices.sh` calls this immediately after the editors
prompt. It's conditional — it only fires a *new* `gum choose` prompt when
"GitHub Copilot CLI" was just picked among the editors, and hasn't been
answered before. `tests/install_test.bats`'s one end-to-end test picks
`GitHub Copilot CLI` among its editors (to exercise that install path at
all) — which means, on the real installer, this extra prompt genuinely
fires. But the test's response queue was never updated to include an
answer for it:

```bash
gum_stub_respond "Personal / unrestricted"
gum_stub_respond "Docker Engine only, inside WSL (recommended)"
gum_stub_respond $'VS Code\nNeovim\nGitHub Copilot CLI'
gum_stub_respond $'Go\nTerraform'      # <- this was meant for languages...
gum_stub_respond ""                     # <- ...but the queue is short one slot,
gum_stub_respond ""                     #    so everything from here down silently
gum_stub_respond "Nerd Font (enhanced)" #    answers the WRONG prompt
gum_stub_respond "Ada Lovelace"
gum_stub_respond "ada@example.com"
```

Nothing here crashes. `set -euo pipefail` catches commands that fail;
it can't catch a command that *succeeds* with an answer meant for a
different question. The queue happily pops `"Go\nTerraform"` — intended
as the languages answer — and hands it back as the answer to the new
Copilot autopilot prompt instead. Every subsequent `gum_stub_respond`
call shifts down one slot the same way: `OMAWSL_LANGUAGES` ends up empty
(its real prompt got the storage-mode answer instead), `OMAWSL_STORAGE`
gets the font-mode answer, and so on down the list. The commit message is
specific that this was "100% reproducible, not flaky" — every single run
hit exactly this, because the extra prompt fires unconditionally whenever
Copilot CLI is selected; there's no timing or ordering randomness
involved, just a queue that's permanently one item short of what the real
code now asks for.

The fix (`f3cc453`) inserts exactly one queued answer, in the right
position, with a comment explaining *why* it has to go there:

```bash
gum_stub_respond $'VS Code\nNeovim\nGitHub Copilot CLI'
# GitHub Copilot CLI was just picked above, so
# omawsl_prompt_copilot_autopilot_if_needed (install/lib.sh) fires its own
# gum choose right after the editors prompt, before languages - answer it
# here or every response below silently shifts down one slot.
gum_stub_respond "No - interactive by default (recommended)"
gum_stub_respond $'Go\nTerraform'
```

This is the general shape of test drift, and why it's dangerous in a way
a crash isn't: the *production* code was correct — the new prompt firing
exactly when it should is the feature working as designed. The *test*
was the thing that fell behind, and because a FIFO queue has no concept
of "which question is this," a stale queue doesn't fail loudly at the
point of drift — it fails much later, and confusingly, as an assertion
mismatch on a completely unrelated field (`OMAWSL_LANGUAGES` came up
empty) that gives no direct hint the real problem is an extra untracked
prompt three lines earlier. The fix for this class of bug is never in the
production code — it's re-reading every place that scripts a fixed
sequence of interactions against code that can grow new interaction
points, every time that code changes.

## 3. Exercise

Close this lesson and rebuild two of this phase's fixes from scratch,
blind, in `practice/20-test-suite-hardening/lib.sh`. (The end-to-end
prompt-drift fix from section 2c is real and worth understanding, but it
isn't graded here — there's no clean way to check "did you notice a
queue is one item short" without either the real installer or a
prohibitively large fixture, so this lesson's check focuses on the two
pieces that reduce to small, pure functions.)

Your file must define these two functions, matching these exact names and
argument orders (the check calls them directly):

- **`omawsl_zoxide_doctor_should_suppress <starship_present>`** — the pure
  decision half of the zoxide-doctor fix from section 2a, split out the
  same way Lesson 1's `omawsl_is_wsl2_kernel` was split from
  `omawsl_is_wsl2`: this function takes the *already-determined* fact
  ("is starship present on this host") as its one argument, rather than
  calling `command -v starship` itself, so it can be tested without
  depending on what's actually installed on the machine running the
  check. `<starship_present>` is the string `"1"` when starship is
  present, anything else (including empty/absent) when it's not.
  - Exit `0` (true, "yes, suppress zoxide's self-check by setting
    `_ZO_DOCTOR=0`") when `<starship_present>` is `"1"`.
  - Exit `1` (false, "no, leave the self-check alone") for every other
    input — this is the part the original, overly-broad fix in `4eb9813`
    got wrong, so make sure your version actually branches on the
    argument instead of always suppressing.
- **`omawsl_scoped_mktemp_dir <base_dir> <label>`** — a stand-in for what
  `stub_init`/`gum_stub_init`/`stub_hide_command` should have been doing
  from the start: create a **new, unique** directory nested under
  `<base_dir>` (never anywhere else — never falling back to the system
  temp directory), print its path to stdout, and exit `0`. `<label>` is a
  short string (e.g. `"stub_log"`, `"gum_response"`) that should appear
  somewhere in the created directory's name, the same way the real fix's
  `mktemp` templates each carried their own label
  (`stub_log.XXXXXX`, `gum_response.XXXXXX`, ...) so a leftover directory
  from a failed cleanup would at least be identifiable by which helper
  created it. Two calls with the same `<base_dir>` and `<label>` must
  return two different, non-colliding paths — mirroring the real
  `mktemp -d`'s guarantee.

Don't look back at this lesson's code while you write it. Get something
you believe is correct, then move to the Check step.

## 4. Check

Run:

```bash
practice/20-test-suite-hardening/check.sh
```

It sources your `practice/20-test-suite-hardening/lib.sh` and calls both
functions directly with a range of inputs, printing one `PASS:`/`FAIL:`
line per assertion and continuing through all of them even if an early
one fails.

Read a `FAIL:` line as a description of *behavior* that didn't match, not
a pointer at a specific line of your code — e.g. "`
omawsl_zoxide_doctor_should_suppress 0` returned true" tells you the
function is still suppressing unconditionally (the exact mistake the
original, too-broad fix made), not which `if` to change. "`
omawsl_scoped_mktemp_dir` returned a path outside the given base
directory" tells you the function fell back to some default temp location
instead of nesting under the directory it was actually given — the exact
mistake `stub_init`'s bare `mktemp` made. A passing check means your
`lib.sh` is behaviorally correct for everything it exercises, even if it
looks nothing like the original — different variable names, `case`
instead of `if`, whatever. If you want to compare approaches purely as a
study aid afterward, you can look at the real fixes with `git show
e87e573` (the zoxide scoping) and `git show f60a3f3` (the temp-dir
scoping) in this repo — but only after your check passes, and only for
style, never as the grade.
