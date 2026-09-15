# Lesson 8: Self-Update Mechanism

## 1. Concept

Phase 7 gave `bin/omawsl` an `update` subcommand, but look at what it actually
updates: `git pull` inside `$OMAWSL_HOME`, plus pending migrations. That's
omawsl updating *itself*. It never touches anything omawsl installed onto the
machine.

That's fine for most of what omawsl installs, because most of it already has
an update mechanism that belongs to someone else:

- Language runtimes (Go, Node, Ruby, ...) → `mise upgrade`.
- System packages (fzf, eza, bat, Neovim, LazyGit, Docker Engine, ...) →
  `sudo apt upgrade`.

Wrapping those would mean re-implementing logic `mise` and `apt` already do
correctly, and keeping that copy from drifting out of sync forever. Not worth
it — a later doc (`docs/updating.md` in the full project) just points users
at the right one.

But seven tools fall through every one of those cracks. `zellij` and
`lazydocker` are downloaded straight from a GitHub release. `opencode` and
Claude Code CLI are installed via `curl ... | bash`. Codex CLI and Gemini CLI
are `npm install -g` packages pulled in through a private `mise`-managed
Node. GitHub Copilot CLI is a `gh` extension. None of these tools ships its
own "check for updates" command, and omawsl's own install functions for all
seven start with a guard like:

```bash
command -v zellij &>/dev/null && return 0
```

Re-running `install` on a machine that already has these tools is
deliberately a no-op — that guard is what makes `install.sh` idempotent. So
"just re-run install" can't be the update story for these seven; the guard
that makes install *safe* is exactly what makes update *impossible* through
the same door. The full project's answer (not something you'll rebuild in
this exercise — see the Exercise section for why) is to split each of those
seven install functions into a guarded `_ensure_installed` entry point
(unchanged, still what `install.sh` calls) and an unguarded `_install_steps`
function containing just the actual curl/npm/binary-download commands, which
a new update path can call directly, guard bypassed.

This phase calls these seven tools the **orphan tools** — orphaned in the
sense that no other mechanism already owns updating them — and builds three
pieces of new machinery to handle them, all grounded in
`docs/superpowers/specs/2026-07-13-omawsl-update-mechanism-design.md`:

1. **A registry.** One small table (slug → display label → "is this
   installed right now" check) so the rest of the code never hardcodes "here
   are the seven tools" more than once.
2. **A version-check adapter per tool.** Something that can answer "what
   version is installed?" and "what's the latest version available?" for
   each of the seven — even though the seven don't share a single API. Two
   of them (Codex CLI, Gemini CLI) are npm packages, so "latest" comes from
   the npm registry. The other five are GitHub-released binaries or curl
   scripts, so "latest" comes from GitHub's Releases API.
3. **A bounded-wait, parallel runner**, because step 2 means making up to
   seven network requests, and two new problems show up the moment you do
   that for real:

   - **What if one of them just hangs?** A network call has no inherent time
     limit — if `api.github.com` or the npm registry is unreachable (offline
     machine, corporate proxy blocking it), a plain `curl` can sit there
     for a very long time with no error, just... nothing. "Bounded wait"
     means: launch the check, but also start a clock, and if the clock
     runs out before the check finishes, stop waiting on it and treat the
     answer as "unknown" instead of hanging the whole `omawsl update`
     command indefinitely. This is the same idea as a browser giving up on
     a slow page load — the timeout, not the page, decides when to move on.
   - **What if we check all seven, one after another?** If each network
     call takes ~1 second and you check zellij, then wait for it to finish,
     then check lazydocker, then wait for *that* to finish, and so on, the
     whole phase takes ~7 seconds even though none of the individual checks
     is slow. In bash, "running things in parallel" means starting several
     commands as **background jobs** — appending `&` to a command hands it
     off to run concurrently instead of blocking the shell until it
     finishes — and then collecting all their results afterward, rather
     than waiting on each one before starting the next. Seven background
     jobs that each take ~1 second finish in ~1 second total, not ~7,
     because they're all running at the same time instead of taking turns.

Put together, this is the piece that lets `omawsl update` show the user a
"Zellij — current: 0.41.2, latest: 0.44.3 (update available)" style status
line for every orphan tool, fast, without ever hanging on a dead network
path — and then let them pick which ones to actually update via a `gum
choose` picker (the full picker/apply flow is described at the end of this
lesson's Walkthrough, but — see the Exercise section — isn't part of what
you'll rebuild here).

## 2. Walkthrough

All of the following is real code from `bin/omawsl-sub/orphan-tools.sh` as of
commit `b97d712` (the end of this phase's commit range, `8ffa70f..b97d712`).

### The registry

```bash
# omawsl_orphan_tool_slugs
# All 7 orphan-tool slugs, in a fixed display order.
omawsl_orphan_tool_slugs() {
  printf '%s\n' zellij lazydocker opencode claude codex gemini gh-copilot
}

omawsl_orphan_tool_label() {
  case "$1" in
    zellij) echo "Zellij" ;;
    lazydocker) echo "LazyDocker" ;;
    opencode|claude|codex|gemini|gh-copilot) omawsl_item_label "$1" ;;
    *) return 1 ;;
  esac
}

omawsl_orphan_tool_installed() {
  local slug="$1"
  case "$slug" in
    zellij) command -v zellij &>/dev/null ;;
    lazydocker) command -v lazydocker &>/dev/null ;;
    opencode) command -v opencode &>/dev/null ;;
    claude) command -v claude &>/dev/null ;;
    codex) command -v codex &>/dev/null ;;
    gemini) command -v gemini &>/dev/null ;;
    gh-copilot) gh extension list 2>/dev/null | grep -q 'github/gh-copilot' ;;
    *) return 1 ;;
  esac
}
```

Three things worth naming here as syntax, since this pattern repeats through
the whole file:

- `printf '%s\n' a b c` prints each argument on its own line. It's used
  instead of `echo "a b c"` (all on one line) because callers loop over this
  output one tool at a time with `while IFS= read -r slug; do ... done`, and
  reading line-by-line is much less fragile than splitting a
  space-separated string (which breaks the moment a label ever contains a
  space, which several of these do — "GitHub Copilot CLI").
- `case "$1" in pattern) command ;; *) fallback ;; esac` is bash's
  multi-way branch — like a `switch` in other languages. `*)` is the
  catch-all arm, matching anything not matched above it. `opencode|claude|
  codex|gemini|gh-copilot)` matches any *one* of five patterns with a
  single arm — `|` inside a case pattern means "or."
- `omawsl_orphan_tool_label` and `omawsl_orphan_tool_installed` both
  `return 1` for an unrecognized slug. In bash, a function's exit status is
  what its `return` sets (or the exit status of its last command, if
  `return` is never called) — 0 means success, anything else means
  failure, the same convention every external program uses. Callers check
  it with `if omawsl_orphan_tool_installed zellij; then ...`.

**Why a `case` table and not a bash associative array
(`declare -A LABELS=(...)`)?** Both would work. This file sticks with
`case` because that's the dispatch style every other file in this project
already uses for "given a slug, do the slug-specific thing" (the install
scripts, `items.sh`, `doctor.sh`) — consistency with the rest of the
codebase wins over the marginal conciseness an associative array would buy
here.

Notice `zellij`/`lazydocker` get their own labels, but the other five
delegate to `omawsl_item_label` — a function that already exists in
`bin/omawsl-sub/items.sh` from Phase 7, because those five are also
regular install/uninstall picker targets. `zellij` and `lazydocker` are
**always-on** installs (`apps-terminal.sh` installs them unconditionally,
no picker), so they were never registered in `items.sh` in the first place
— this file adds just enough of a home for them, rather than pulling them
into `items.sh`, which the design spec deliberately keeps scoped to
install/uninstall/doctor's picker categories.

### The version-check adapters, and a real pipefail bug

```bash
omawsl_orphan_extract_semver() {
  grep -oE '[0-9]+\.[0-9]+\.[0-9]+' <<< "$1" | head -n1 || true
}
```

`grep -oE PATTERN` prints only the matched text (`-o`), using extended
regex syntax (`-E`) so `+` means "one or more" without needing a backslash.
`<<< "$1"` is a **here-string** — it feeds the string on its right as
`grep`'s stdin, equivalent to `echo "$1" | grep ...` but without spawning
an extra `echo` process. `| head -n1` keeps just the first match, in case
a tool's `--version` output happens to contain more than one number that
looks like a version.

The `|| true` at the end isn't decoration — it was a real bug, fixed in
commit `fc6eb85`. Every script in this project starts with
`set -euo pipefail`. The `-e` means "exit immediately if any command
fails"; the `pipefail` means "and in a pipeline, count the *whole
pipeline* as failed if *any* stage of it fails, not just the last one."
`grep` exits `1` when it finds no match at all — which is exactly what
happens when you call this function on a tool that isn't installed (empty
`--version` output). Without `|| true`, that `1` exit status from `grep`
propagates through the `| head -n1` pipe and aborts the entire calling
function under `set -e`, even though the caller was fully prepared to
treat "no version found" as an empty string, not a crash. The design
spec's own invariant is explicit about this: *"A version-check lookup
failing → resolves to `unknown`, never blocks."* `|| true` is what makes
that true here — it converts `grep`'s "nothing matched" into a clean exit
0 with empty output, instead of an aborted function.

```bash
omawsl_orphan_latest_from_github() {
  local repo="$1"
  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null)" || tag=""
  echo "${tag#v}"
}

omawsl_orphan_latest_from_npm() {
  local package="$1"
  mise exec node@lts -- npm view "$package" version 2>/dev/null || echo ""
}
```

`curl -fsSL URL` fetches a URL: `-f` fails silently (no HTML error page on
stdout) on a bad HTTP status, `-s` silences the progress meter, `-S` shows
an error message anyway if `-s` would have hidden it, `-L` follows
redirects. The result — GitHub's JSON release metadata — gets piped into
`jq -r '.tag_name // empty'`, which pulls out the `tag_name` field as raw
text (`-r`, not JSON-quoted) or an empty string if the field's missing
(`// empty` is jq's own "or this default" operator). `${tag#v}` is bash
parameter expansion: `#pattern` strips the shortest match of `pattern` from
the *front* of the variable's value — here, a single leading `v`, because
GitHub tags this project cares about look like `v0.44.3` but the version
this code compares against everywhere else is bare `0.44.3`.

Both functions end every failure path in an empty string rather than an
error — `tag=""` on a failed `curl`/`jq`, `echo ""` on a failed `mise`. This
is the same "never blocks" contract as `omawsl_orphan_extract_semver`
above, just written slightly differently per function rather than through
one shared helper — a deliberate, explicit repetition rather than a
"clever" one-liner, since each of these three functions fails in a
different shape (`grep`'s pipefail interaction, a subshell command
substitution's own exit status, a plain command's exit status) and forcing
them through one abstraction would have hidden that.

`omawsl_orphan_latest_from_npm` never calls a bare `npm` — it goes through
`mise exec node@lts -- npm view ...`, the exact same private, mise-managed
Node runtime `app-codex-cli.sh`/`app-gemini-cli.sh` already use to
*install* these two tools. A bare `npm` isn't guaranteed to be on `PATH` at
all on a machine that only has Node through `mise`.

```bash
omawsl_orphan_tool_version_installed() {
  local slug="$1"
  case "$slug" in
    zellij) omawsl_orphan_extract_semver "$(zellij --version 2>/dev/null || true)" ;;
    ...
    gh-copilot) omawsl_orphan_extract_semver "$(gh extension list 2>/dev/null | grep 'github/gh-copilot' || true)" ;;
    *) return 1 ;;
  esac
}

omawsl_orphan_tool_version_latest() {
  local slug="$1"
  case "$slug" in
    zellij) omawsl_orphan_latest_from_github zellij-org/zellij ;;
    lazydocker) omawsl_orphan_latest_from_github jesseduffield/lazydocker ;;
    opencode) omawsl_orphan_latest_from_github anomalyco/opencode ;;
    claude) omawsl_orphan_latest_from_github anthropics/claude-code ;;
    codex) omawsl_orphan_latest_from_npm "@openai/codex" ;;
    gemini) omawsl_orphan_latest_from_npm "@google/gemini-cli" ;;
    gh-copilot) omawsl_orphan_latest_from_github github/gh-copilot ;;
    *) return 1 ;;
  esac
}
```

This is the adapter layer doing its actual job: two generic primitives
(`_from_github`, `_from_npm`) get wired to seven specific tools through one
more `case` dispatch, each arm just naming which primitive and which
repo/package applies. Adding an eighth orphan tool later means adding one
line here, one line to the registry, and (if it's yet another GitHub- or
npm-sourced tool) nothing new to the primitives at all.

### The bounded-wait timeout, and a real `set -e` arithmetic bug

```bash
omawsl_orphan_wait_with_timeout() {
  local pid="$1" limit="$2"
  local waited=0 max_iterations=$((limit * 10))
  while kill -0 "$pid" 2>/dev/null; do
    if (( waited >= max_iterations )); then
      kill "$pid" 2>/dev/null || true
      wait "$pid" 2>/dev/null || true
      return 1
    fi
    sleep 0.1
    waited=$((waited + 1))
  done
  wait "$pid" 2>/dev/null || true
  return 0
}
```

A few pieces of bash process control, from scratch:

- When you run `some_command &`, bash doesn't wait for it — it starts the
  command running in the background and immediately continues to the next
  line. The special variable `$!` holds the **process ID (PID)** of the
  most recently backgrounded job — a number the OS assigns to identify that
  running process, which you need if you want to check on it or kill it
  later.
- `kill -0 "$pid"` doesn't actually kill anything — signal `0` is a no-op
  signal that only checks whether a process with that PID still exists.
  It's the standard bash idiom for "is this still running?", and it's what
  drives the `while` loop here: keep looping *while* the process is still
  alive.
- `sleep 0.1` pauses for a tenth of a second. This function polls — wakes
  up ten times a second, checks if the job finished yet, and if a fixed
  number of checks (`max_iterations = limit * 10`) goes by with the job
  still running, it gives up and calls `kill "$pid"` for real (no `-0`) to
  actually terminate it.
- `wait "$pid"` blocks until that specific PID actually exits, and clears
  it out of bash's internal job table. It's called on both exit paths —
  after `kill`, and after the loop ends because the job finished on its
  own — so a caller never has to worry about a lingering zombie/background
  job.

Why a poll loop instead of the external `timeout` command (`timeout 5
some_command`)? Because `timeout` execs the command it's given directly,
as a real, separate program lookup — bypassing bash's own function table
entirely. This project's whole test suite stubs dangerous commands (like
`curl`) by defining a same-named bash *function* and `export -f`-ing it
(see `tests/helpers/stubs.bash`); a real `timeout` process would never see
that function, only the real `curl` on `PATH`. Bounding the wait at the
`&`/`wait`/`kill` level, inside the same shell, keeps every stub visible.

The comment in the real file calls out a second real bug, fixed in commit
`e94c59d`:

> `((waited++))` evaluates to the pre-increment value, which is 0 on the
> loop's first pass, so under `set -e` the arithmetic command's exit status
> is treated as a failure and aborts the function before it can ever return
> 0.

This is subtle enough to spell out fully. `((expression))` in bash is
itself a *command* — like any command, it has an exit status. Its exit
status is 0 (success) if the arithmetic expression evaluates to a nonzero
number, and 1 (failure) if it evaluates to zero. `waited++` is
post-increment: the *expression's value* is `waited`'s value **before**
incrementing, even though the variable itself does get incremented as a
side effect. On the very first iteration, `waited` is `0`, so
`((waited++))` evaluates to `0` — which `((...))` reports as exit status 1
— which `set -e` treats as "this command failed" and aborts the function
right there, on the very first pass through the loop, every single time.
The fix, `waited=$((waited + 1))`, is a plain variable assignment (not a
bare arithmetic *command*) — assignment's own exit status doesn't depend
on the value being assigned, so it can never trip this trap.

### The parallel runner, and a real "restarts the clock per job" bug

```bash
omawsl_orphan_tools_check_versions() {
  local tmp_dir="$1" timeout_seconds="$2"; shift 2
  local slugs=("$@")
  local pids=()
  for slug in "${slugs[@]}"; do
    (
      local installed latest
      installed="$(omawsl_orphan_tool_version_installed "$slug" 2>/dev/null || true)"
      latest="$(omawsl_orphan_tool_version_latest "$slug" 2>/dev/null || true)"
      printf '%s\t%s\n' "$installed" "$latest" > "$tmp_dir/$slug.result"
    ) &
    pids+=("$!")
  done
  local deadline=$(( $(date +%s) + timeout_seconds ))
  local i now remaining
  for i in "${!pids[@]}"; do
    now="$(date +%s)"
    remaining=$(( deadline - now ))
    (( remaining < 0 )) && remaining=0
    omawsl_orphan_wait_with_timeout "${pids[$i]}" "$remaining" || true
    [[ -f "$tmp_dir/${slugs[$i]}.result" ]] || printf '\t\n' > "$tmp_dir/${slugs[$i]}.result"
  done
}
```

The first loop is the "parallel" half: `( ... ) &` wraps the body in a
**subshell** (parentheses run their contents in a nested shell) and
backgrounds it. Because this happens inside a `for` loop with no `wait` in
between, all seven subshells start running *concurrently* — the loop
doesn't pause after starting zellij's check to wait for it before starting
lazydocker's. Each subshell writes its own result to its own file
(`$tmp_dir/$slug.result`, tab-separated `installed<TAB>latest`) rather than
returning a value directly, because a background job's stdout/variables
aren't directly visible to the parent shell after it exits — a shared file
per job is the simplest way for each background job to hand its result
back.

The second loop is the "bounded" half, and it's where commit `a50272a`
fixed a real bug. The naive version of this loop would call
`omawsl_orphan_wait_with_timeout "${pids[$i]}" "$timeout_seconds"` — the
*same, full* timeout for every job. That looks reasonable until you
picture two jobs hanging at once: waiting on job 1 burns the whole
`timeout_seconds` before it gets killed, then waiting on job 2 burns
*another* full `timeout_seconds` before it gets killed — total wait time
`N × timeout_seconds` for `N` simultaneously-hung jobs, which is exactly
the pile-up this whole bounded-wait mechanism exists to prevent. The fix
computes one shared `deadline` (`now + timeout_seconds`) **before** the
wait loop starts, and each call to `omawsl_orphan_wait_with_timeout`
passes whatever time is left until that same deadline (`remaining`,
clamped to `>= 0`) — so the total wall-clock time across the whole loop
converges to `timeout_seconds`, no matter how many jobs are hanging at
once.

The final line of the loop — `[[ -f "$tmp_dir/${slugs[$i]}.result" ]] ||
printf '\t\n' > ...` — backfills an empty `installed<TAB>latest` (both
sides blank, meaning "unknown") for any job that got killed before it
could write its own result file.

### `omawsl_orphan_tools_format_line`, and what this all feeds into

```bash
omawsl_orphan_tools_format_line() {
  local slug="$1" installed="$2" latest="$3"
  local label; label="$(omawsl_orphan_tool_label "$slug")"
  local status
  if [[ -z "$latest" ]]; then
    status="unknown"
  elif [[ "$installed" == "$latest" ]]; then
    status="up to date"
  else
    status="update available"
  fi
  printf '%-22s current: %-10s latest: %-10s (%s)' \
    "$label" "${installed:-unknown}" "${latest:-unknown}" "$status"
}
```

`[[ -z "$latest" ]]` tests whether the string is empty — the signal that
the version-check for this tool timed out or failed, which this function
deliberately treats as its own status ("unknown"), distinct from "checked
successfully and it's current" (`up to date`) or "checked successfully and
it's behind" (`update available`). `%-22s`/`%-10s` in the `printf` format
left-pad each field to a fixed width so every row in the eventual picker
lines up in neat columns.

This function is the last piece you'll rebuild in this lesson's exercise —
everything past this point (real code, not part of what you're asked to
reproduce) is what the full project builds *on top of* these building
blocks, so you can see where this was headed:

- `omawsl_orphan_tools_live_check` — a TTY-only wrapper that prints
  "checking..." placeholder lines immediately, runs
  `omawsl_orphan_tools_check_versions` in the background, and redraws the
  whole block in place every 0.2 seconds using `tput cuu`/`tput el`
  (cursor-up, erase-line) until every result file exists — so a real
  terminal session sees each row flip live from "checking..." to its
  resolved current/latest/status.
- `omawsl_orphan_tool_apply_update` — re-runs a tool's `_install_steps`
  function (the unguarded half of the `_ensure_installed`/`_install_steps`
  split mentioned in the Concept section), isolated with the same
  `{ ... } || ok=0` failure-isolation idiom used elsewhere in this project
  (`cloud-tools.sh`), so one tool's failed update can't abort the rest.
- `omawsl_orphan_tools_update` — the real entry point, wired into
  `bin/omawsl-sub/update.sh` right after the existing self-update +
  migrate steps. It builds the list of installed orphan tools, runs the
  live check, and — only if at least one tool needs attention — launches
  a `gum choose --no-limit --selected "..."` picker (the same "two-phase"
  UX pattern the design spec calls for: `gum choose` renders its options
  once and can't live-update rows mid-prompt, which is exactly why the
  status-line phase has to finish *before* the picker ever opens, not
  arrive as part of it) pre-selecting exactly the rows that resolved to
  "update available." Whatever the user leaves checked gets passed to
  `omawsl_orphan_tool_apply_update`, one tool at a time.

## 3. Exercise

Close this lesson and, in `practice/08-self-update-mechanism/orphan-tools.sh`
(the stub is already there — a single file, no starter functions, just a
header comment), rebuild the registry, the version-check adapters, and the
bounded-wait parallel runner from scratch. Implement exactly these function
names and signatures — the check script in the next section calls them by
name, so the interface has to match even though your internals don't have to
look anything like the original:

**Registry**
- `omawsl_orphan_tool_slugs` — no arguments; prints all 7 slugs, one per
  line, in any order you like: `zellij`, `lazydocker`, `opencode`, `claude`,
  `codex`, `gemini`, `gh-copilot`.
- `omawsl_orphan_tool_label <slug>` — prints a human-readable label for a
  known slug; returns a nonzero exit status for an unrecognized slug. (You
  don't have `items.sh` available in this practice directory — just give
  all seven tools their own label directly, e.g. `"Codex CLI"`.)
- `omawsl_orphan_tool_installed <slug>` — returns 0 if the tool is present,
  nonzero if not. For `zellij`, `lazydocker`, `opencode`, `claude`, `codex`,
  `gemini`: check with `command -v <tool> &>/dev/null`. For `gh-copilot`:
  check with `gh extension list 2>/dev/null | grep -q 'github/gh-copilot'`.

**Version-check adapters**
- `omawsl_orphan_extract_semver <text>` — prints the first `X.Y.Z`-shaped
  token found anywhere in `<text>`; prints nothing (empty string) and
  **exits 0** — not an error — if there's no match. (This is the pipefail
  trap from the Walkthrough — make sure your version doesn't fall into it.)
- `omawsl_orphan_latest_from_github <owner/repo>` — fetches
  `https://api.github.com/repos/<owner/repo>/releases/latest` with `curl`,
  pulls out `.tag_name` with `jq`, strips a leading `v` if present. Prints
  an empty string (never errors) if the request or parse fails.
- `omawsl_orphan_latest_from_npm <package>` — runs
  `mise exec node@lts -- npm view <package> version`. Prints an empty
  string (never errors) if it fails.
- `omawsl_orphan_tool_version_installed <slug>` — dispatches per slug to
  that tool's own `--version` (or, for `gh-copilot`, `gh extension list`),
  through `omawsl_orphan_extract_semver`. Must print an empty string, not
  error, for a tool that isn't actually installed.
- `omawsl_orphan_tool_version_latest <slug>` — dispatches per slug to
  `omawsl_orphan_latest_from_github` or `omawsl_orphan_latest_from_npm`
  with the right repo/package:
  - GitHub-sourced: `zellij` → `zellij-org/zellij`, `lazydocker` →
    `jesseduffield/lazydocker`, `opencode` → `anomalyco/opencode`, `claude`
    → `anthropics/claude-code`, `gh-copilot` → `github/gh-copilot`.
  - npm-sourced: `codex` → `@openai/codex`, `gemini` → `@google/gemini-cli`.

**Display**
- `omawsl_orphan_tools_format_line <slug> <installed> <latest>` — prints a
  status line for one tool. Must contain the tool's label, both version
  strings (or something recognizable as "unknown" when a version is
  empty), and one of three status words: `unknown` (when `<latest>` is
  empty), `up to date` (when `<installed>` equals `<latest>`), or `update
  available` (otherwise). The exact formatting/column widths are up to
  you — the check only looks for these substrings.

**Bounded-wait parallel runner**
- `omawsl_orphan_wait_with_timeout <pid> <limit_seconds>` — polls whether
  `<pid>` is still running; returns 0 if it exits on its own before
  `<limit_seconds>` elapses, or forcibly kills it and returns 1 if not. The
  process must actually be dead by the time this returns 1 — a caller
  checking `kill -0 <pid>` afterward should find nothing.
- `omawsl_orphan_tools_check_versions <tmp_dir> <timeout_seconds>
  <slug...>` — for every given slug, resolves both
  `omawsl_orphan_tool_version_installed` and `omawsl_orphan_tool_version_latest`
  **concurrently** (as background jobs, not one after another), and writes
  `<tmp_dir>/<slug>.result` containing `<installed><TAB><latest>` for each.
  A job that has to be killed for outliving the deadline still gets a
  result file, with both sides empty. Every slug's wait must share **one**
  overall deadline (`timeout_seconds` from when the function was called) —
  not a fresh `timeout_seconds` restarted for each slug in turn.

Two things this exercise deliberately does **not** ask you to build, because
they either need a real terminal to observe (the `tput`-based live redraw)
or would need to make a real network call / really install something on
your machine to exercise for real (the `gum choose` picker and applying an
update) — both are shown as real code in the Walkthrough above, just not
part of what you reproduce here:

- The live "checking..." → resolved-line terminal redraw
  (`omawsl_orphan_tools_live_check`).
- The `gum choose` picker and the actual update-application step
  (`omawsl_orphan_tools_update`, `omawsl_orphan_tool_apply_update`).

Your file should just be function definitions — no `main "$@"` or any other
code that runs unconditionally at the bottom. `check.sh` sources your file
directly and calls these functions itself.

## 4. Check

Run it with:

```bash
bash practice/08-self-update-mechanism/check.sh
```

The check never makes a real network request and never installs or updates
anything on your machine — every place your code would call `curl` or
`mise` is replaced with a fake version for the duration of the check that
returns made-up, canned data instead. That's what lets it safely exercise
your GitHub/npm lookup logic, including the failure paths (a fake `curl`
that fails, or returns garbage instead of JSON), without ever touching the
real network.

Read a `FAIL:` line for what it says, not as a hint to go compare against
the original file. Each one names the specific behavior that didn't match
— e.g. "`omawsl_orphan_wait_with_timeout` did not actually kill the
process after its timeout" or "`omawsl_orphan_tools_check_versions` took
too long to finish — jobs don't appear to be running in parallel." A
passing check means your implementation is behaviorally correct even if it
doesn't look anything like the Walkthrough's code — different variable
names, a different loop structure, `case` swapped for a lookup table,
whatever you chose. Only after it passes, if you want to compare style
choices (never to grade correctness), you can look at the real file with:

```bash
git show b97d712:bin/omawsl-sub/orphan-tools.sh
```
