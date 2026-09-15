# Lesson 1: Core Skeleton

## 1. Concept

omawsl's whole job is to take a bare, freshly-installed WSL2 Ubuntu machine
and turn it into a configured developer environment — Docker, languages,
editors, themes, all of it — by running one command. That command has to
work for a stranger on their own machine, which creates a cluster of
problems that have nothing to do with "what packages do I install" and
everything to do with "how do I run untrusted-by-default code, on someone
else's computer, reliably, and prove it works before they ever run it for
real":

- **Nobody has cloned the repo yet.** The very first thing that runs can't
  assume its own source code exists on disk. Something has to fetch the
  code before any of the code can run.
- **The installer does a lot of unrelated things** — check the OS version,
  install a TUI tool, ask the user five questions, install fonts, install
  packages, edit config files. If all of that is one giant script, one bug
  anywhere breaks everything, and you can't test the OS-version check
  without also being ready to test the font installer.
- **People re-run installers.** They hit an error, fix something, and run
  it again. A script that blows up or double-installs things on a second
  run is broken, even if it worked the first time.
- **You cannot test "installs a package" by actually installing a
  package.** Not in a CI-style feedback loop, not without root, not
  without an internet connection every time you save a file. You need a
  way to check "did my script *decide* to install `gum`" without it
  *actually* shelling out to `apt-get`.

This phase builds the skeleton that solves all four problems at once, and
every later phase in this project reuses the same shape without
rethinking it:

- a tiny **entry point** (`boot.sh`) whose only job is "get the real code
  onto disk, then hand off to it" — solving problem 1;
- an **orchestrator** (`install.sh`) that does nothing itself except call,
  in order, a list of small scripts that each do one thing — solving
  problem 2;
- every one of those small scripts writing its real logic as a **plain
  bash function**, with a two-line guard at the bottom that only calls the
  function when the file is run directly, not when it's *sourced* into
  another script — which is what makes problem 4 possible, and what
  "idempotent" (problem 3) actually gets tested against;
- one shared **`lib.sh`** of small, pure helper functions (version
  comparison, WSL2 detection, saving/loading a user's choices) that every
  other script sources instead of re-implementing;
- a **bats-core test suite** that never runs a real `apt-get install`,
  never edits your real `~/.bashrc`, and never touches your real git
  config — it replaces (**stubs**) those dangerous commands with fake
  ones that just *record* what they were asked to do, so the tests can
  assert "this script would have installed `gum`" without installing
  anything.

If any of the vocabulary above is new — shell script, sourcing, exit
codes, `set -euo pipefail`, idempotency — that's expected. It's explained
inline as it comes up below, because you'll be reaching for all of it in
every later phase.

## 2. Walkthrough

### What a shell script actually is

A shell script is just a text file containing the same commands you'd
type at a terminal prompt, run in order, top to bottom, by a program
called a *shell* (here, `bash`). The first line of almost every script in
this project is:

```bash
#!/usr/bin/env bash
```

This is called a **shebang**. On Linux, when you try to *execute* a file
directly (`./install.sh`), the kernel reads this first line to figure out
which program should interpret the rest of the file. `#!/usr/bin/env bash`
means "find `bash` on this machine's `PATH` and hand it this file" — more
portable than hardcoding `#!/bin/bash`, since it doesn't assume bash lives
at that exact path.

### `set -euo pipefail`

The second line of almost every script in this project is:

```bash
set -euo pipefail
```

This is three separate safety switches, combined into one flag string:

- **`-e`** ("errexit"): if any command in the script fails (returns a
  non-zero **exit code** — every command finishes by reporting a number,
  `0` for "succeeded," anything else for "some kind of failure" — the
  exact non-zero value is command-specific), the whole script stops
  immediately instead of plowing on with the next line as if nothing
  happened. Without `-e`, a failed `apt-get install` would still let the
  script reach the "install complete!" message.
- **`-u`** ("nounset"): referencing a variable that was never set is
  itself treated as an error, instead of silently substituting an empty
  string. This catches typos like `$OMAWSL_HOEM` before they cause a
  confusing downstream failure.
- **`-o pipefail`**: normally, a pipeline like `cmd1 | cmd2`'s exit code
  is just `cmd2`'s exit code — if `cmd1` fails but `cmd2` still runs and
  succeeds, `-e` alone wouldn't notice `cmd1` failed. `pipefail` makes the
  whole pipeline's exit code be the *worst* failure of any command in it.

Every script in this project starts this way. It's what turns "my script
happened to work in my one test run" into "my script stops loudly, on the
first sign of trouble, every time."

### Functions, and the "sourced vs. executed" guard

Every real script in this project puts its logic inside a bash
**function** — a named, reusable block of code — rather than as bare
top-level commands:

```bash
omawsl_install_gum() {
  sudo apt-get update -qq
  sudo apt-get install -y gum
}
```

And at the very bottom of the same file:

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_install_gum
fi
```

This is the single most important pattern in this phase, so it's worth
understanding precisely. A bash file can be brought into a running shell
two different ways:

- **Executed** — `bash app-gum.sh`, or `./app-gum.sh` if it's marked
  executable. This starts a *new* process just to run that file.
- **Sourced** — `source app-gum.sh` (or the shorthand `. app-gum.sh`).
  This runs the file's contents *inside the current shell*, as if you'd
  typed those lines yourself. Any function or variable the file defines
  becomes available in the calling shell too.

`BASH_SOURCE[0]` is always the path of the file currently being read,
regardless of how it got there. `$0` is the path of the script that was
*originally* invoked to start this process. When a file is executed
directly, those are the same path — `$0` and `BASH_SOURCE[0]` both point
at it. When a file is *sourced* from inside another script, `$0` still
points at the original outer script, while `BASH_SOURCE[0]` points at the
file being sourced — so they differ.

That difference is the whole trick: `install.sh` sources every one of
these small scripts to pull their functions into its own shell, then
calls each function explicitly, in the order it chooses. Because sourcing
doesn't make the two paths equal, the guard's `if` is false during
sourcing, so nothing runs automatically — `install.sh` stays in full
control of *when* `omawsl_install_gum` actually executes. But a test file
(or a developer debugging just this one piece) can also run
`bash app-gum.sh` directly, which *does* auto-run the function — letting
every script be exercised in isolation, exactly as the plan's Global
Constraints require ("every install script must be runnable in isolation
… for fast iteration").

### `install/lib.sh` — shared helpers

`install/lib.sh` is sourced by nearly every other script in this phase.
It's kept dependency-free — pure bash, no calls to external programs like
`bc` — because some of it (`check-version.sh`) has to run *before*
anything has been `apt install`ed, so it can't assume any tool beyond
bash itself exists yet.

**`omawsl_version_ge`** — compares two `MAJOR.MINOR` version strings
without using `bc` (a calculator program not guaranteed to be present on
a fresh image):

```bash
omawsl_version_ge() {
  local version="$1" minimum="$2"
  local v_major="${version%%.*}" m_major="${minimum%%.*}"
  local v_minor="${version#*.}" m_minor="${minimum#*.}"
  v_minor="${v_minor%%.*}" m_minor="${m_minor%%.*}"
  if (( 10#$v_major > 10#$m_major )); then
    return 0
  elif (( 10#$v_major < 10#$m_major )); then
    return 1
  else
    (( 10#$v_minor >= 10#$m_minor ))
  fi
}
```

Two new pieces of syntax:

- `local` declares a variable scoped to just this function, instead of
  leaking into whatever called it — important discipline once dozens of
  small functions all get sourced into one shell.
- `${version%%.*}` and `${version#*.}` are **parameter expansion**
  operators that trim a string without calling out to `sed` or `cut`:
  `%%.*` strips the *longest* match of `.` followed by anything, from the
  *end*, leaving what's before the first `.` (the major version); `#*.`
  strips the *shortest* match of anything followed by `.`, from the
  *start*, leaving what's after the first `.` (the minor version, still
  possibly with more dots after it — hence the second `%%.*` pass to trim
  those off too).
- `10#$v_major` forces base-10 interpretation. Without it, bash's `((...))`
  arithmetic treats a number with a leading `0` (like a version segment
  `04`) as **octal** — and `08`/`09` aren't even valid octal digits, so
  `((08 > 04))` would throw a runtime error instead of just comparing
  wrong. `10#` heads that off entirely.

An alternative would have been shelling out to `sort -V` or `dpkg
--compare-versions`, both of which exist on Ubuntu. Pure bash arithmetic
was chosen instead specifically because this function is called from
`check-version.sh`, which runs at the very start of `install.sh`, before
even `apt-get update` has happened — depending on any external command
here would be depending on something not yet guaranteed to exist.

**`omawsl_list_has`** — checks whether an item is present in a
comma-delimited list:

```bash
omawsl_list_has() {
  local list="$1" item="$2"
  [[ ",$list," == *",$item,"* ]]
}
```

Why not a plain substring check, `[[ "$list" == *"$item"* ]]`? Because
that would wrongly match `"Go"` against a list containing `"GoLang"` —
`"Go"` is a substring of `"GoLang"`, but it isn't a *member* of the list.
Wrapping both the haystack and the needle in commas first turns "is `Go`
a substring of `GoLang,Python`" (true, wrong answer) into "is `,Go,` a
substring of `,GoLang,Python,`" (false, right answer) — because the
commas force the match to land on whole tokens, not partial ones.

This function exists at all because of a constraint worth calling out
explicitly: `OMAWSL_LANGUAGES`, `OMAWSL_EDITORS`, and the rest of the
first-run picks are **comma-delimited strings, never bash arrays**. Bash
arrays cannot be exported across a process boundary — if `install.sh`
exported an array and then a later script ran in a *new* process, the
array wouldn't survive the trip. These values also get written to disk
(`choices.env`) and re-read by a completely separate invocation days
later. A comma-delimited string survives both of those trips intact; a
bash array does not.

**`omawsl_is_wsl2_kernel`** — separated from the real `uname -r` call
specifically so it can be unit-tested against fixture strings instead of
only ever being testable on a real WSL2 machine:

```bash
omawsl_is_wsl2_kernel() {
  local kernel="$1"
  [[ "$kernel" == *microsoft-standard-WSL2* ]]
}

omawsl_is_wsl2() {
  omawsl_is_wsl2_kernel "$(uname -r)"
}
```

This split — one function that's pure string logic, one thin wrapper that
supplies the real system call — is a pattern you'll see again: anywhere a
function's *decision* depends on something environmental (the real
kernel version, the real date, the real network), that decision gets
pulled into its own pure function so tests can feed it canned input
instead of needing the real environment to be in a particular state.

**`omawsl_save_choice` / `omawsl_load_choice`** — persist and retrieve a
`KEY="value"` line in `~/.local/state/omawsl/choices.env` (overridable via
`OMAWSL_STATE_DIR`, which is how tests avoid ever touching a real home
directory):

```bash
omawsl_save_choice() {
  local key="$1" value="$2"
  local dir; dir="$(omawsl_choices_dir)"
  mkdir -p "$dir"
  local file="$dir/choices.env"
  touch "$file"
  local tmp; tmp="$(mktemp)"
  grep -v "^${key}=" "$file" > "$tmp" 2>/dev/null || true
  local escaped="${value//\\/\\\\}"
  escaped="${escaped//\"/\\\"}"
  printf '%s="%s"\n' "$key" "$escaped" >> "$tmp"
  mv "$tmp" "$file"
}
```

This is **idempotent**: idempotent means "doing it twice has the same
effect as doing it once." Calling `omawsl_save_choice OMAWSL_LANGUAGES
Go` and then `omawsl_save_choice OMAWSL_LANGUAGES Rust` leaves exactly
one `OMAWSL_LANGUAGES=` line in the file (holding `Rust`), not two — the
`grep -v "^${key}="` line filters out any *existing* line for that key
before the new one gets appended, so re-running the installer (or
answering a prompt differently on a second run) overwrites cleanly
instead of accumulating duplicate, contradictory lines. The same
discipline applies everywhere in this phase: `a-shell.sh` overwrites
`~/.bashrc` from scratch rather than appending to it; `omawsl_install_gum`
calls `apt-get install`, which itself no-ops if the package is already at
the right version. An installer a user might run five times needs every
step to converge to the same end state, not pile up side effects.

The escaping (`\` before `\\`, then `"` before `\"`) matters for a
concrete reason: `omawsl_load_choice` deliberately does **not** `source`
`choices.env` to read it back:

```bash
omawsl_load_choice() {
  local key="$1"
  local file; file="$(omawsl_choices_dir)/choices.env"
  [[ -f "$file" ]] || { echo ""; return 0; }
  local line
  line="$(grep "^${key}=" "$file" | tail -n1)"
  [[ -z "$line" ]] && { echo ""; return 0; }
  line="${line#*=\"}"
  line="${line%\"}"
  line="${line//\\\"/\"}"
  line="${line//\\\\/\\}"
  echo "$line"
}
```

Sourcing a `KEY="value"` file would be the "obvious" way to load it back
— but `choices.env` holds a user's own free-text name and email, entered
in `identification.sh`. If someone's git-config name is, say,
`O"Brien $(rm -rf ~)`, and you *sourced* that file, bash would try to
literally execute the `$(...)` inside it. `grep` + string-editing instead
of `source`/`eval` is the difference between "read this file as data" and
"read this file as code" — the second one is a command-injection
vulnerability. This is a genuinely general lesson, not an omawsl-specific
one: **never `source` or `eval` a file built from user-controlled
input.**

### `install/check-version.sh`

```bash
omawsl_check_version() {
  local os_release_file="${1:-/etc/os-release}"
  local arch="${2:-$(uname -m)}"
  local kernel="${3:-$(uname -r)}"
  ...
}
```

`${1:-/etc/os-release}` is another parameter-expansion form: "use `$1` if
it was passed, otherwise fall back to this default." All three arguments
default to the real system files/commands, and are only ever overridden
in tests — the same "pure decision, real value supplied by a thin
default" split as `omawsl_is_wsl2_kernel` above. The function checks, in
order: the OS-release file exists; `ID` is `ubuntu` (not Debian, not
anything else); the version is `>= 24.04` via `omawsl_version_ge` (a
**floor-only** check — no upper bound, so Ubuntu 26.04, 28.04, and beyond
all pass without a code change); the architecture is one of a small
allowed set (`case` statement — a cleaner way to match one value against
several literal alternatives than a chain of `if`/`elif`/`[[ ]]`
comparisons); and finally, that the kernel string looks like WSL2
specifically, not WSL1 or bare Linux, via `omawsl_is_wsl2_kernel`.

### `install/terminal/required/app-gum.sh` — bootstrapping `gum`

```bash
omawsl_install_gum() {
  sudo apt-get update -qq
  sudo apt-get install -y gum
}
```

`gum` is a small TUI (text user interface) tool that renders the
selection menus and text prompts the rest of this phase uses —
`first-run-choices.sh` and `identification.sh` both just shell out to the
`gum` command. It has to be installed **before** `first-run-choices.sh`
runs (not later, as part of `terminal.sh`'s general pass) — an ordering
requirement the design spec calls out explicitly, because a prompt
function that calls `gum choose` when `gum` isn't installed yet would
just fail.

### `install/first-run-choices.sh`

```bash
omawsl_prompt_multi() {
  local header="$1"; shift
  gum choose --no-limit --header "$header" "$@" | paste -sd, -
}
```

`shift` drops `$1` and renumbers the rest, so `"$@"` (all remaining
arguments) becomes just the list of options to offer, without the header
text mixed in. `gum choose --no-limit` prints one chosen line per
selection; `paste -sd, -` joins those lines into a single comma-delimited
string with `,` as the delimiter — turning `gum`'s multi-line output into
exactly the comma-list format `omawsl_list_has` expects. Nothing is
pre-selected by default in any of these pickers, and selecting nothing is
a valid, expected answer (an empty string), not an error — a public
installer shouldn't surprise-install something nobody explicitly chose.

### `install/terminal.sh` — sourced, not sub-shelled

```bash
OMAWSL_TERMINAL_SCRIPTS=(
  "terminal/required/app-gum.sh"
  "terminal/identification.sh"
  "terminal/a-shell.sh"
  "terminal/apps-terminal.sh"
  "terminal/libraries.sh"
)

omawsl_run_terminal_scripts() {
  local script
  for script in "${OMAWSL_TERMINAL_SCRIPTS[@]}"; do
    echo "omawsl: running $script"
    source "$SCRIPT_DIR/$script"
  done
}
```

This is a real bash **array** (`(...)`, indexed with `[@]`) — safe to use
here, unlike `OMAWSL_LANGUAGES`, because it never needs to leave this one
process. The loop `source`s each script rather than running it in a
sub-shell (e.g. `bash "$script"`). The difference matters under `set -e`:
sourcing runs the script's commands *inside this same process*, so if one
fails, this process's own `set -e` stops everything immediately —
matching the design spec's requirement that a single script's failure
stop the whole run right there, rather than letting the loop silently
move on to the next script.

A subtle bug the plan's own notes flag: several of these sourced scripts
declare a top-level variable named `SCRIPT_DIR` for their own use. Since
`source` shares the calling shell's variables, if the orchestrator
*itself* had also used the name `SCRIPT_DIR`, the last sourced child
script would silently overwrite it out from under the orchestrator. The
fix was simply never reusing that name at the orchestrator level —
`terminal.sh` uses `OMAWSL_INSTALL_DIR`, and `install.sh` one level above
it uses `OMAWSL_ROOT_DIR`. It's a small, easy-to-miss trap that comes
directly from how sourcing shares namespace, and a good reason to give a
sourcing script's own bookkeeping variables distinctive names.

### `install.sh` and `boot.sh` — the two-stage handoff

`install.sh` sources every piece (`lib.sh`, `check-version.sh`,
`app-gum.sh`, `first-run-choices.sh`, `windows-prereq-checklist.sh`,
`terminal.sh`) and calls each function explicitly, in a fixed order, from
inside `omawsl_install`. It is the orchestrator: it contains almost no
logic of its own beyond "call these, in this order," which is exactly
why each piece could be built and tested independently before this file
ever existed.

`boot.sh` is the *actual* one-liner entry point — the thing a brand-new
user runs before any of this repo exists on their disk. Its job is
narrow: show a banner, ask for confirmation (skippable via
`OMAWSL_ASSUME_YES=1`, which is how the test suite drives it
non-interactively), `apt-get install git curl`, then clone the repo if
`$OMAWSL_HOME` doesn't already look like a git checkout, or `git pull` if
it does, and finally hand off:

```bash
exec bash "$OMAWSL_HOME/install.sh"
```

Two details worth noticing. First, `exec` replaces the current process
with the new one instead of starting a child and waiting for it — there's
no reason for `boot.sh`'s process to stick around once `install.sh` has
taken over. Second, `bash "$OMAWSL_HOME/install.sh"` is invoked
explicitly through `bash`, rather than relying on `install.sh`'s own
executable bit (`./install.sh`) — because this repo is authored on
Windows, where git does not reliably preserve the executable bit when
checked out into WSL2's filesystem. That's a real bug a later manual
end-to-end test caught: every automated test up to that point fabricated
its own already-executable stand-in `install.sh`, so nothing exercised
the real committed file's permissions until a human actually ran the real
thing — which is exactly why this plan ends every phase with a manual
verification step, not just green automated tests.

### Testing with bats-core and command stubs

`tests/helpers/stubs.bash` provides `stub_command <name> [exit_code]`:

```bash
stub_command() {
  local name="$1" exit_code="${2:-0}"
  eval "
${name}() {
  echo \"${name} \$*\" >> \"\$STUB_LOG\"
  return ${exit_code}
}
export -f ${name}
"
}
```

This defines a bash **function** with the same name as a dangerous real
command (`sudo`, `git`, `apt-get`) — a function that just logs what it
was called with, instead of doing the real thing. `export -f` is the
piece that makes this actually work for these tests: normally, a function
defined in one shell process is invisible to a *different* process, but a
lot of these tests run the script under test as a genuine child process
(`run bash "$REPO_ROOT/install/terminal/required/app-gum.sh"`, via bats'
`run` helper). `export -f` exports the function's *code itself* into the
environment, so that child `bash` process resolves `sudo` to the stub
instead of walking `$PATH` to find the real `/usr/bin/sudo`. A test can
then assert against the stub's log file (`stub_calls`) that the script
*would have* run `sudo apt-get install -y gum`, without ever installing
anything.

`gum` gets a slightly richer stub — `gum_stub_respond` queues canned
answers, and each call to the stubbed `gum` pops the next one off the
queue, letting a test drive a multi-prompt script (five `gum choose`
calls in a row, in `first-run-choices.sh`) exactly as if a human were
answering each prompt.

This is a general testing principle worth naming: **replace what's
dangerous or slow at the boundary, and test the real decision logic on
either side of it.** The `omawsl_install_gum` function itself is 100%
real, unmodified code under test; only the `sudo`/`apt-get` it calls out
to is fake.

## 3. Exercise

Close this lesson and rebuild `install/lib.sh` from scratch, blind, in
`practice/01-core-skeleton/lib.sh`. This is the one piece of this phase's
skeleton that's pure, dependency-free logic — no `apt-get`, no `gum`, no
git config — so it's what this lesson's check can verify directly and
safely. (The rest of this phase — `boot.sh`, `install.sh`,
`check-version.sh`, the `terminal/*.sh` scripts, the `configs/` files —
is real and worth rebuilding for your own practice too, since you now
have the whole shape in your head, but only `lib.sh` is graded here.)

Your file must define these six functions, matching these exact names
and argument orders (the check calls them by name):

- **`omawsl_version_ge <version> <minimum>`** — exit `0` if `version` is
  greater than or equal to `minimum` (both `"MAJOR.MINOR"` strings),
  exit `1` otherwise. No `bc`, no external commands — pure bash
  arithmetic only.
- **`omawsl_list_has <comma_delimited_list> <item>`** — exit `0` if
  `item` is present in `comma_delimited_list` as a whole token, exit `1`
  otherwise. Must not match a bare substring (an item that's a substring
  of a *different*, longer item in the list must not count as present).
  An empty list must never match anything.
- **`omawsl_is_wsl2_kernel <kernel_release_string>`** — exit `0` if the
  given kernel-release string looks like WSL2 specifically, exit `1`
  otherwise (a WSL1-style string and a bare-Linux string must both fail).
- **`omawsl_is_wsl2`** — exit `0`/`1` using the real `uname -r`, by
  delegating to `omawsl_is_wsl2_kernel`. (Not directly exercised by the
  check, for the obvious reason that the check might not run on WSL2 —
  but it should exist and delegate correctly.)
- **`omawsl_choices_dir`** — print a directory path. Honor an
  `OMAWSL_STATE_DIR` override if that environment variable is set;
  otherwise default to `$HOME/.local/state/omawsl`.
- **`omawsl_save_choice <key> <value>`** and **`omawsl_load_choice
  <key>`** — persist and retrieve a value by key in
  `$(omawsl_choices_dir)/choices.env`. Saving the same key twice must
  overwrite, not duplicate. Loading a key that was never saved must print
  an empty string (and exit `0`, not fail). Round-tripping a value that
  contains double quotes, backslashes, `$(...)`, and backticks must
  produce back the *exact original string* — and must **never** execute
  any of it as a command in the process.

Don't look back at this lesson's code while you write it. Get something
you believe is correct, then move to the Check step.

## 4. Check

Run:

```bash
practice/01-core-skeleton/check.sh
```

It sources your `practice/01-core-skeleton/lib.sh` and calls each
function directly with a range of inputs — including some deliberately
awkward ones (a version with a leading zero, a list item that's a
substring of another, a value containing `"`, `\`, `$(...)`, and
backticks). Every check prints its own `PASS:`/`FAIL:` line, and the
script keeps going through all of them even if an early one fails, so a
single run shows you everything that's wrong, not just the first thing.

Read a `FAIL:` line as a description of *behavior* that didn't match —
e.g. "`omawsl_list_has` matched `Go` against `GoLang,Python`" tells you
the membership check is doing a bare substring match instead of wrapping
both sides in delimiters. It is not telling you which line of your code
to change. A passing check means your `lib.sh` is behaviorally correct
for everything it exercises, even if your implementation looks nothing
like the original — different variable names, a different parameter-
expansion trick, `case` instead of `if`, all fine. If you want to compare
approaches purely as a study aid afterward, you can look at the real
`install/lib.sh` in this repo (or `git show a2054b2:install/lib.sh` for
the exact commit this phase produced it in) — but only after your check
passes, and only for style, never as the grade.
