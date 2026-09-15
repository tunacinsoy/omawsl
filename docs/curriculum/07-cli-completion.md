# Lesson 7: CLI Completion — `install`, `uninstall`, `update`, `migrate`, `doctor`

## 1. Concept

Every phase up to now has been building one thing: a script you run *once*,
on a fresh machine, to turn it into a configured dev environment. Phases
1-6 are all `boot.sh` → `install.sh` → a chain of `install/terminal/*.sh`
scripts. Run it, answer some prompts, walk away with a working box. Done.

Except it isn't done, because a real tool doesn't get used once. Weeks
later the person who ran it wants to add a language they skipped. Months
later they want to rip out a tool they no longer use. Every time they hear
about a new feature, they want to know if their two-month-old install
already has it, or is still missing it. None of that is "run the installer
again" — the installer only knows how to *add* things, and it doesn't
track what it already added versus what a person only asked for once and
never went back to. Phase 7 is where `bin/omawsl` grows from a one-shot
installer into a small, permanent piece of software the person keeps
using. That's a different design problem than "chain some install steps,"
and it's worth slowing down on the four ideas that make it work.

**Idea 1: a registry, so nothing has to agree with itself by coincidence.**
Once you have `install`, `uninstall`, *and* `doctor` all needing to talk
about "the same thing" — say, Go — you have a drift risk. If `install.sh`
stores it in a comma-list as `"Go"`, `uninstall.sh` expects to be handed
`"Go"` too, and `doctor.sh` prints `"Go"` in its report, that's three
independent places that each hard-code the string `"Go"`. Nothing stops
one of them from drifting to `"GoLang"` or `"golang"` during some future
edit — and the moment one does, list-membership checks silently break:
`doctor` calls something "not installed" that actually is, or `uninstall`
can't find the very thing `install` just added. A **registry** is the fix:
one file that is the single source of truth for "what does this short name
mean," and every other file *asks* the registry instead of hard-coding the
answer itself. It's the same reason a codebase defines a constant once
instead of typing the same magic number in five files — except here the
"constant" is a mapping (short slug → exact display string), not a single
value, so the registry is implemented as a small lookup function instead
of a `readonly` variable.

**Idea 2: a comma-separated list is your persistence format, and that's a
deliberate, not lazy, choice.** omawsl already persists user choices to a
file (`choices.env`, going back to Phase 1) as plain `KEY="value"` lines —
this is the same idea as a `.env` file you've probably seen in other
projects: one key-value pair per line, meant to be read by a program, not
executed as a full script. When the *value* itself needs to be a list —
"which languages did this person pick" — the simplest format bash can
split apart with zero extra dependencies is **CSV**: comma-separated
values, e.g. `OMAWSL_LANGUAGES="Go,Node.js"`. JSON would need a JSON
parser (`jq`) that isn't guaranteed to exist yet on a machine `omawsl`
hasn't finished setting up. A comma-list splits with bash's own
`IFS=',' read -ra` — no dependency. The tradeoff is real: CSV can't
represent a value that itself contains a comma. omawsl accepts that
tradeoff because every value it stores here is a fixed label from its own
registry, never arbitrary user text.

**Idea 3: `update`/`migrate` as a pull-then-run-pending-migrations pair.**
"Migration" is a general term (most familiar from databases): a small,
numbered, one-way script that moves *persisted state* from one shape to
the next, and is meant to run *exactly once* per machine, ever. The
mechanism needs to know which migrations already ran, so it keeps its own
version marker on disk and only runs migrations numbered after it —
running each one is what advances that marker. `omawsl migrate` is that
mechanism, standalone. `omawsl update` is `git pull` (get the newest
scripts) immediately followed by `omawsl migrate` (bring old persisted
state up to date with what those new scripts now expect) — because
pulling new code without also running its migrations would leave a
machine on new code with stale state.

**Idea 4: `doctor` is read-only, on purpose.** Every other command in this
phase *changes* something — installs a package, removes one, migrates a
file. `doctor` is the one command whose entire job is to look and report,
never to write. That's a useful category of command in any long-lived
tool: something safe to run at any time, as often as you want, that can
never make things worse. The design payoff shows up immediately: `doctor`
can be run before *and* after any other command, as a way to confirm what
that command actually did.

**Idea 5: `uninstall` is `install` in reverse, one script per installed
thing.** Phase 1-4 built `install/terminal/app-vscode.sh`,
`install/terminal/dev-language.sh`-style scripts, one per installable
thing. Phase 7 adds `uninstall/app-vscode.sh`, `uninstall/dev-language.sh`
— one *removal* script per *same* thing, same idempotent conventions.
`uninstall.sh`'s job is just to look up which removal script matches a
given name (via the registry) and run it.

**The closing lesson.** All five ideas above shipped, tests passed, and
the phase was marked done — for one release. Then the person who *built*
omawsl actually used `omawsl uninstall` on their own machine, months
later, and noticed: the tool they removed was gone, but `omawsl doctor`
still listed it as selected, and the interactive `omawsl install` picker
still showed it pre-checked. `uninstall` deleted the software but never
told `choices.env` the choice had changed. That's the subject of the last
part of the Walkthrough below, and it's the reason this lesson's Exercise
makes you build the add/remove/doctor interaction directly, not just the
individual pieces in isolation: a test suite that checks `install`,
`uninstall`, and `doctor` *separately* can all pass while this exact bug
sits in the seam between them. "Done" meant "used for real," not "tests
are green."

## 2. Walkthrough

### The registry: `bin/omawsl-sub/items.sh`

```bash
# omawsl_item_category <slug>
omawsl_item_category() {
  case "$1" in
    ruby|node|go|php|python|elixir|rust|java|terraform) echo "language" ;;
    azure|aws|gcp) echo "cloud" ;;
    vscode|neovim|opencode|cursor|claude|codex|gh-copilot|antigravity) echo "editor" ;;
    mysql|redis|postgresql) echo "storage" ;;
    docker) echo "docker" ;;
    *) return 1 ;;
  esac
}

# omawsl_item_label <slug>
omawsl_item_label() {
  case "$1" in
    ruby) echo "Ruby on Rails" ;;
    node) echo "Node.js" ;;
    go) echo "Go" ;;
    # ...
    *) return 1 ;;
  esac
}

# omawsl_item_slugs <category>
omawsl_item_slugs() {
  case "$1" in
    language) printf '%s\n' ruby node go php python elixir rust java terraform ;;
    cloud) printf '%s\n' azure aws gcp ;;
    editor) printf '%s\n' vscode neovim opencode cursor claude codex gh-copilot antigravity ;;
    storage) printf '%s\n' mysql redis postgresql ;;
    *) return 1 ;;
  esac
}
```

Three lookup functions, all `case` statements keyed on the same short
slug: which **category** does this slug belong to, what **label** does it
render as (the exact string stored in `choices.env` and shown in
`doctor`'s report and the interactive picker), and — going the other
direction — what are **all** the slugs in one category, in a fixed order.
`bash` has associative arrays (`declare -A`) that could hold slug→label
directly; a `case` statement was used instead because every other
dispatch-on-name spot in this codebase (`bin/omawsl`'s own command
dispatch, `uninstall.sh`'s dispatch below) already reads as a `case`
statement — matching that convention means a reader who's seen one dispatch
in this project already knows how to read all of them, at the cost of one
line of boilerplate (`echo`/`return 1`) an associative array wouldn't need.

Notice `omawsl_item_slugs` doesn't take a `category` and print labels — it
prints **slugs**, and callers convert each one to a label via
`omawsl_item_label` as needed. That indirection is what lets
`omawsl_doctor_report_category` (below) iterate in the registry's own
fixed order rather than whatever order a `choices.env` list happens to be
in.

### `uninstall.sh`: dispatch to a removal script, by slug

```bash
omawsl_uninstall_dispatch() {
  local slug="$1"
  local label
  case "$slug" in
    ruby|node|go|php|python|elixir|rust|java|terraform)
      label="$(omawsl_item_label "$slug")"
      source "$OMAWSL_ROOT_DIR/uninstall/dev-language.sh"
      omawsl_uninstall_language "$label"
      ;;
    mysql|redis|postgresql)
      label="$(omawsl_item_label "$slug")"
      source "$OMAWSL_ROOT_DIR/uninstall/storage.sh"
      omawsl_uninstall_storage "$label"
      ;;
    docker)
      source "$OMAWSL_ROOT_DIR/uninstall/docker.sh"
      omawsl_uninstall_docker
      ;;
    vscode)
      source "$OMAWSL_ROOT_DIR/uninstall/app-vscode.sh"
      omawsl_uninstall_vscode
      ;;
    # ... one case per remaining slug ...
    *)
      echo "omawsl: unknown item '$slug'" >&2
      return 1
      ;;
  esac
}
```

Every branch does the same two things: `source` the one `uninstall/*.sh`
file that knows how to remove *this specific thing*, then call its
function. That's the "installers run in reverse" idea made literal —
`uninstall/dev-language.sh` exists specifically because
`install/terminal/select-dev-language.sh` exists, and knows how to undo
exactly what that file does (for a mise-managed language, that's
`mise unuse --global <tool>@latest`, which both un-pins and prunes the
installed version — verified live against a real WSL2 instance, per the
plan doc). Multiple slugs sharing one `uninstall/*.sh` file (all nine
languages route through `dev-language.sh`) is the same "one script per
*kind* of thing, not per individual item" shape `install/terminal/*.sh`
already used in Phase 1-4.

### `doctor.sh`: report, never write

```bash
omawsl_doctor_report_category() {
  local category="$1" check_fn="$2" choices_key="$3"
  local selected; selected="$(omawsl_load_choice "$choices_key")"

  if [[ -z "$selected" ]]; then
    echo "  (none selected)"
    return 0
  fi

  local slug label
  while IFS= read -r slug; do
    label="$(omawsl_item_label "$slug")"
    omawsl_list_has "$selected" "$label" || continue
    if "$check_fn" "$slug"; then
      echo "  [OK]      $label"
    else
      echo "  [PENDING] $label - run: omawsl install $category $slug"
    fi
  done < <(omawsl_item_slugs "$category")
}
```

`check_fn` is passed in as a **function name** (`omawsl_doctor_language_installed`,
`omawsl_doctor_editor_installed`, ...) and called indirectly via
`"$check_fn" "$slug"` — one report-printing loop, reused across every
category by handing it a different "is this one actually there" function
each time, rather than writing the same loop four times with a different
`if` body pasted into each copy. The loop walks the **registry's** slugs
(`omawsl_item_slugs "$category"`), not the raw comma-list from
`choices.env` — that's what guarantees `doctor`'s output is always in the
same order regardless of what order things were added in, and it's why
`omawsl_list_has` (whole-token comma-list membership, from `install/lib.sh`)
gets used here instead of a plain substring check: a naive
`[[ "$selected" == *"$label"* ]]` would treat `"Go"` as present inside a
list that only actually contains `"GoLang"`.

Every branch of `omawsl_doctor` in the finished file only ever calls
`echo` or a `check_fn` that itself only reads (`command -v`, `mise ls
--current`, `docker ps`). Nothing in `doctor.sh` ever calls
`omawsl_save_choice`, writes a file, or shells out to anything that
installs or removes. That's not incidental — it's the property that makes
`doctor` safe to run as often as you like, including as a way to confirm
what a different command just did.

### `migrate.sh` and `update.sh`: pull, then run what's pending

```bash
# omawsl_pending_migrations
omawsl_pending_migrations() {
  local last; last="$(omawsl_last_migrated_timestamp)"
  local ts
  omawsl_migration_timestamps | while IFS= read -r ts; do
    if [[ "$ts" -gt "$last" ]]; then
      echo "$ts"
    fi
  done
}

omawsl_migrate() {
  local pending; pending="$(omawsl_pending_migrations)"
  # ...
  if [[ -z "$pending" ]]; then
    echo "omawsl: no pending migrations - up to date."
  else
    mkdir -p "$state_dir"
    local ts
    while IFS= read -r ts; do
      echo "omawsl: running migration $ts..."
      bash "$dir/$ts.sh"
      echo "$ts" > "$state_dir/version"
    done <<< "$pending"
  fi
}
```

Migrations live in `migrations/<timestamp>.sh`, one file per migration,
named by when it was written — so sorting filenames numerically sorts
them into run order. `omawsl_last_migrated_timestamp` reads a plain
`version` file next to `choices.env`; anything with a higher timestamp
than that hasn't run yet. Notice the version file is updated **inside**
the loop, right after each individual migration runs (`echo "$ts" >
"$state_dir/version"`) — not once at the end after the whole batch
finishes. If migration 3 of 5 fails partway through, migrations 1 and 2
are still recorded as done; re-running `migrate` picks up at 3 instead of
re-running 1 and 2 too. That's a small but real design decision: it would
have been simpler to write the final timestamp once after the `while`
loop, but that version would silently re-run already-successful migrations
on any retry after a partial failure.

```bash
omawsl_update() {
  local home_dir="${OMAWSL_HOME:-$HOME/.local/share/omawsl}"
  if [[ -n "$(git -C "$home_dir" status --porcelain)" ]]; then
    echo "omawsl: $home_dir has local changes - refusing to 'git pull' over them." >&2
    return 1
  fi
  git -C "$home_dir" pull
  omawsl_migrate
}
```

`update` is deliberately thin: check the checkout is clean (refuse to
`git pull` over local edits, rather than letting `git pull` fail
confusingly or silently overwrite someone's own change), pull, then just
call `omawsl_migrate` — reusing the exact same function `bin/omawsl
migrate` calls standalone, rather than duplicating its logic.

### The closing bug: commit `821743c`

Phase 7 shipped, all five commands worked, tests were green. Then, using
the tool for real, its own author ran `omawsl uninstall go` and then
`omawsl doctor` — and `doctor` still reported Go as selected. The picker
in `omawsl install` still showed it pre-checked too. `omawsl_uninstall_command`,
as originally shipped, was exactly this:

```bash
omawsl_uninstall_command() {
  local slug="${1:-}"
  if [[ -z "$slug" ]]; then
    echo "Usage: omawsl uninstall <name>" >&2
    return 1
  fi
  omawsl_uninstall_dispatch "$slug"
}
```

It called `omawsl_uninstall_dispatch` — which runs the real removal
(`mise unuse --global go@latest`, in this example) — and then just
*stopped*. Nothing told `choices.env` that `OMAWSL_LANGUAGES` should no
longer include `"Go"`. The software was gone; the *record* of the choice
wasn't. The fix added the missing half, symmetric with `install`'s own
`omawsl_merge_csv`:

```bash
# omawsl_remove_from_csv <csv> <item>
# Inverse of omawsl_merge_csv.
omawsl_remove_from_csv() {
  local csv="$1" item="$2"
  local result="" tok
  IFS=',' read -ra items <<< "$csv"
  for tok in "${items[@]}"; do
    [[ -z "$tok" ]] && continue
    [[ "$tok" == "$item" ]] && continue
    result="${result:+$result,}$tok"
  done
  echo "$result"
}

omawsl_uninstall_deselect() {
  local slug="$1"
  local category
  category="$(omawsl_item_category "$slug")" || return 0
  local key
  case "$category" in
    language) key=OMAWSL_LANGUAGES ;;
    editor)   key=OMAWSL_EDITORS ;;
    storage)  key=OMAWSL_STORAGE ;;
    *) return 0 ;;
  esac
  local label; label="$(omawsl_item_label "$slug")"
  local existing; existing="$(omawsl_load_choice "$key")"
  omawsl_save_choice "$key" "$(omawsl_remove_from_csv "$existing" "$label")"
}

omawsl_uninstall_command() {
  local slug="${1:-}"
  # ...
  omawsl_uninstall_dispatch "$slug"
  omawsl_uninstall_deselect "$slug"
}
```

Two things worth noticing beyond "it now removes the label." First,
`omawsl_uninstall_deselect` is called **after** `omawsl_uninstall_dispatch`,
not before or in parallel — and the file is under `set -euo pipefail`.
If `omawsl_uninstall_dispatch` fails (unknown slug, the removal script
itself errors), `set -e` aborts `omawsl_uninstall_command` right there;
`omawsl_uninstall_deselect` never runs, and `choices.env` is correctly
left untouched, because the uninstall didn't actually happen. Ordering
here isn't cosmetic — swap the two calls and a failed uninstall would
still deselect the item, telling `choices.env` a removal succeeded that
never did. Second, `docker` is deliberately excluded (`omawsl_item_category
docker` maps to `"docker"`, which the `case` above falls through to `*)
return 0 ;;` on): `OMAWSL_DOCKER_MODE` is a single mode choice — "Engine"
or "Docker Desktop" — not a multi-select list, so there's nothing for
`omawsl_remove_from_csv` to remove it from. Getting this file right meant
noticing which of the four categories didn't fit the pattern, not applying
it uniformly everywhere.

## 3. Exercise

Close this lesson and, in `practice/07-cli-completion/`, build
`cli.sh` — a small standalone stand-in for the choices.env-and-doctor slice
of `bin/omawsl`. It won't install or remove any real software (that part
of the lesson is `bin/omawsl-sub/uninstall.sh`'s job, and it's covered
above, not in what you're implementing) — everything here is scoped to
reading and writing a persisted choice list and reporting on it, the exact
seam commit `821743c` broke.

`practice/07-cli-completion/registry.sh` is already there for you (open it
— you don't need to change it): a 3-item slug→label registry (`go` → `Go`,
`node` → `Node.js`, `vscode` → `VS Code`) via `omawsl_item_label <slug>`
and `omawsl_item_slugs` (all three slugs, one per line, in that fixed
order — `go`, `node`, `vscode`).

Build `practice/07-cli-completion/cli.sh` implementing:

- `omawsl_choices_dir` — no arguments, prints `"$HOME/.local/state/omawsl-practice"`.
- `omawsl_load_choice <key>` — prints the persisted value of `<key>` from
  `$(omawsl_choices_dir)/choices.env` (format: one `KEY="value"` line per
  key), or an empty string if the file or the key doesn't exist yet.
- `omawsl_save_choice <key> <value>` — writes (creating the directory and
  file if needed) or replaces the `KEY="value"` line for `<key>` in that
  same file, leaving any other key's line untouched.
- `omawsl_list_has <csv> <item>` — true (exit 0) if `<item>` is present in
  comma-delimited `<csv>` as a whole token (not a substring of some other
  entry).
- `omawsl_merge_csv <a> <b>` — the union of two comma-lists, de-duplicated,
  order-preserving: `a`'s items first, then any of `b`'s items not already
  in `a`.
- `omawsl_remove_from_csv <csv> <item>` — the inverse: `<csv>` with one
  `<item>` removed (whole-token match), order-preserving for whatever's
  left, a no-op if `<item>` isn't present.
- `omawsl_doctor_report <choices_key>` — walks `omawsl_item_slugs` in
  registry order; for each slug whose label is present (via
  `omawsl_list_has`) in the CSV loaded from `<choices_key>`, prints a line
  `"  [SELECTED] <label>"`. If nothing is selected, prints exactly one
  line: `"  (none selected)"`.

Wire these into a command dispatcher, `omawsl_cli_main`, called
unconditionally at the bottom of the file behind the usual guard —
`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then omawsl_cli_main "$@"; fi` —
so the three subcommands are reachable as real CLI invocations:

- `bash cli.sh add <slug>` — merge that slug's label into the `OMAWSL_ITEMS`
  choice and persist it.
- `bash cli.sh remove <slug>` — remove that slug's label from the
  `OMAWSL_ITEMS` choice and persist it (this is the half `821743c` was
  missing — make sure `remove` actually updates the persisted list, not
  just prints something).
- `bash cli.sh doctor` — print `omawsl_doctor_report OMAWSL_ITEMS`.

Resolve `registry.sh` relative to `cli.sh`'s own location (the
`SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` pattern used
throughout `bin/omawsl-sub/`), so it works regardless of the caller's
current directory. Don't hard-code your own machine's home directory
anywhere — everything should resolve through `$HOME`.

## 4. Check

Run:

```bash
bash practice/07-cli-completion/check.sh
```

It never touches your real `$HOME` — every invocation of your `cli.sh`
runs with `HOME` (and the working directory) redirected to a throwaway
scratch directory the check creates and deletes when it's done, so
`choices.env` is written and read entirely inside that fake home.

Each line is a separate `PASS`/`FAIL` assertion; a failure names the
*behavior* that didn't match (e.g. "after 'remove go', doctor should
report Node.js but not Go") rather than pointing at a line of code — that
failing behavior is what to go fix, regardless of how you structured the
implementation that produced it. Passing means your solution is
behaviorally correct even if it doesn't look anything like the version in
the Walkthrough — comparing against the real project's files afterward
(`bin/omawsl-sub/items.sh`, `install/lib.sh`, `bin/omawsl-sub/uninstall.sh`,
`bin/omawsl-sub/doctor.sh`) is worth doing purely as a style comparison,
never as part of the grade.
