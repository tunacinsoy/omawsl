# Lesson 3: Languages & Cloud Tools

## 1. Concept

Phase 1 gave omawsl a shape (orchestrator, small sourced scripts, stubbed
tests) and Phase 2 used that shape to install Docker. This phase reuses the
exact same shape for a much harder category of thing to install: developer
language runtimes (Node.js, Go, Python, Ruby on Rails, and five more) and
two cloud CLIs (Terraform, Azure CLI) — each of which needs its own,
different, non-Ubuntu-archive install path. That difference is what this
phase is really about.

**Why not just `apt-get install nodejs golang python3 ...`?** Ubuntu's own
package archive ships language runtimes, but usually old, fixed versions —
whatever shipped with that Ubuntu release, not whatever a developer's
project actually needs. A real developer machine needs to pick *and later
change* a Node/Ruby/Go version per-project. That's the job of a **version
manager**: a tool that installs multiple versions of many languages
side-by-side, outside the system package manager, and lets you select which
one is "active." This project uses [`mise`](https://mise.jdx.dev) for that.
Once `mise` itself is bootstrapped, every language becomes one line —
`mise use --global <tool>@latest` — instead of eight different bespoke
install recipes.

**Why do Terraform and Azure CLI need something different again?**
Neither is a "language" mise manages, and neither has a stable Ubuntu
archive package either — HashiCorp and Microsoft each publish their own
**apt repository** (a separate download location `apt` can pull packages
from, beyond Ubuntu's own mirrors) and require adding their **GPG signing
key** first, so `apt` can verify packages actually came from them and
weren't tampered with in transit. That's two entirely new third-party apt
repos being added to a stranger's machine, non-interactively, in a script
that also has to keep working the tenth time someone re-runs it.

That combination — non-interactive, safe-to-add third-party trust, and
re-runnable — is where this phase's real difficulty sits, and it's why the
outline promises "three more real-world bugs" on top of the two Phase 2
already surfaced. All three trace back to the same root cause: **a script
that's correct when run once, fresh, is not automatically correct when run
twice, or when the network hiccups halfway through.** Concretely, this
phase's real commit history hit:

1. A tool that was just installed under `$HOME/.local/bin` wasn't
   *reachable* by name in the very next shell — because the check for
   "is it already installed" ran **before** the line that puts
   `$HOME/.local/bin` on `PATH`, not after. `PATH` is just a
   colon-separated list of directories bash searches, in order, whenever
   you type a bare command name — and a directory not yet *on* that list
   might as well not exist as far as the shell is concerned, no matter
   what's actually sitting inside it.
2. A **failed** repo-add left a *broken* apt source file behind — and the
   next, completely unrelated `apt-get update` anywhere later in the run
   (or in a future run) failed too, because `apt-get update` checks *every
   configured* repository, and one broken one poisons the whole command.
3. `gpg --dearmor` (the command that converts a plain-text/"ASCII-armored"
   GPG key into the binary keyring format `apt` expects) *interactively*
   asks "File exists. Overwrite? (y/N)" if its output file is already
   there from an earlier attempt — which hangs forever with no human
   present to answer it.

None of these are exotic. They're the ordinary cost of writing a script
that has to survive being interrupted, re-run, and pointed at a flaky
network — which is every real installer, eventually.

## 2. Walkthrough

### `mise.sh` — bootstrapping the version manager

```bash
omawsl_install_mise() {
  export PATH="$HOME/.local/bin:$PATH"

  if command -v mise &>/dev/null; then
    return 0
  fi

  curl -fsSL https://mise.run | sh
}
```

Two things worth noticing, in order, because the order is the whole point:

- The `export PATH=...` line runs **first, unconditionally** — before
  anything checks whether `mise` is already installed. `mise`'s official
  installer (`curl -fsSL https://mise.run | sh` — download the installer
  script and pipe it straight into `sh` to run it) drops the `mise` binary
  into `$HOME/.local/bin`, a directory that is *not* on a fresh shell's
  `PATH` by default. If this script checked `command -v mise` **before**
  exporting that directory onto `PATH`, the check would say "not found"
  even on the *second* run, after `mise` had already been installed —
  because the shell still wouldn't know to look in `$HOME/.local/bin`.
  Exporting first means the presence check that follows is actually
  checking the right thing.
- `command -v mise &>/dev/null` is the idiomatic bash way to ask "is there
  a command named `mise` I could run?" without printing anything —
  `&>/dev/null` throws away both stdout and stderr. If it succeeds, the
  function returns `0` (success) immediately: **idempotent** by
  construction, no separate "already installed" flag file needed.
- This function's own `export` only changes `PATH` for *this process and
  anything it starts from here on* — not for some future, brand-new
  terminal. That's deliberate and necessary here: `install/terminal.sh`
  **sources** every script in its dispatch list rather than running each
  one as a separate sub-process (`bash script.sh`) — a design decision
  from Phase 1. Sourcing means `mise.sh`, `select-dev-language.sh`, and
  `cloud-tools.sh` all run *inside the same shell process*, one after
  another, in the same `install.sh` invocation. `select-dev-language.sh`
  runs mere moments after `mise.sh`, in that same process — so it needs
  `mise` reachable *right now*, not "after the user opens a new terminal."
  Exporting `PATH` here is what makes that possible. (Making `mise`
  reachable in a genuinely *new*, later shell — like the terminal a user
  opens tomorrow — is a separate job, handled by `configs/bashrc`, and
  that file hit the exact same ordering bug; see "Bug 1" below.)

### `select-dev-language.sh` — one line per language, one exception

```bash
omawsl_select_dev_language() {
  local languages="${OMAWSL_LANGUAGES:-}"

  if omawsl_list_has "$languages" "Ruby on Rails"; then
    omawsl_install_language ruby
    mise exec ruby@latest -- gem install rails --no-document
  fi

  if omawsl_list_has "$languages" "Node.js"; then
    omawsl_install_language node
  fi

  # ... Go, PHP, Python, Elixir, Rust, Java, each the same shape ...
}
```

`omawsl_install_language` is a one-line helper: `mise use --global
"${mise_tool}@latest"`. `mise use --global` pins a tool's version in
mise's own global config — and it's idempotent by construction, the same
way `apt-get install` on an already-installed package is: re-running it
with the same arguments just re-affirms the same state, no special
"already set?" check needed (a convention this whole project leans on
rather than hand-rolling idempotency checks everywhere).

Seven of the eight languages are exactly that one line, repeated with a
different tool name. Ruby on Rails is the deliberate exception, and it's
worth understanding *why* it needs two lines instead of one:

- `mise use --global ruby@latest` only **pins the version** in mise's
  config file. It does not add Ruby's `gem` binary to *this shell's*
  `PATH` — that only happens via `mise activate`, a hook meant for
  long-lived interactive shells (see Bug 1 below), not a one-shot install
  script.
- A bare `gem install rails` right after that would resolve `gem` against
  whatever's *already* on `PATH` — quite possibly nothing at all, since
  this is a one-shot script, not an activated shell — and abort the whole
  install under `set -e`.
- `mise exec <tool>@<version> -- <command>` is mise's answer to exactly
  this problem: run one command with that tool's shims added to `PATH`
  *just for the duration of that one call*, without needing a persistent
  shell activation. `mise exec ruby@latest -- gem install rails
  --no-document` runs `gem install rails` with mise's Ruby actually
  reachable, `--no-document` skipping the (slow, and here pointless) local
  documentation build.

Two design choices worth naming because they're easy to get wrong the
other way:

- **Selecting nothing is valid, not an error.** `"${OMAWSL_LANGUAGES:-}"`
  falls back to an empty string if the variable is entirely unset (not
  just empty) — so this function never crashes just because a caller ran
  it without setting `OMAWSL_LANGUAGES` at all, and eight `if`s that all
  evaluate false is simply "installed nothing," not a bug.
- **Terraform and Azure CLI share the same picker `OMAWSL_LANGUAGES`, but
  are deliberately *not* handled here.** They're not languages `mise`
  manages, so routing them through `cloud-tools.sh` instead keeps this
  function's job narrow: "map a language label to a `mise` call," nothing
  else. `omawsl_list_has` (from Phase 1's `lib.sh`) is what makes the
  membership check safe either way — it wraps both the list and the item
  in commas before comparing, so `"Go"` never accidentally matches inside
  a longer, unrelated label.

### `cloud-tools.sh` — third-party apt repos, safely

This is the file where the phase's hardest problem lives, so it's worth
reading slowly. Here's the final version, incorporating the fixes covered
below:

```bash
omawsl_install_terraform() {
  local apt_sources_file="${1:-${OMAWSL_TERRAFORM_APT_SOURCES_FILE:-/etc/apt/sources.list.d/hashicorp.list}}"
  local keyrings_dir="${2:-${OMAWSL_TERRAFORM_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if command -v terraform &>/dev/null; then
    return 0
  fi

  local ok=1
  {
    if [[ ! -f "$apt_sources_file" ]]; then
      sudo install -m 0755 -d "$keyrings_dir" &&
      curl -fsSL https://apt.releases.hashicorp.com/gpg | sudo gpg --yes --dearmor -o "$keyrings_dir/hashicorp.gpg" &&
      sudo tee "$apt_sources_file" >/dev/null <<< "deb [arch=$(dpkg --print-architecture) signed-by=$keyrings_dir/hashicorp.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" &&
      sudo apt-get update -qq
    fi &&
    sudo apt-get install -y terraform
  } || ok=0

  if [[ "$ok" -eq 0 ]]; then
    sudo rm -f "$apt_sources_file"
    echo "omawsl: Terraform install failed (repo unreachable?) - skipping, continuing with the rest of the run."
  fi
}
```

`omawsl_install_azure_cli` is the same shape end to end, against
Microsoft's key (`https://packages.microsoft.com/keys/microsoft.asc`) and
repo (`https://packages.microsoft.com/repos/azure-cli/`), installing the
`azure-cli` package instead of `terraform`. The plan's own notes
explicitly consider — and reject — sharing one parameterized helper
between the two: they're *almost* identical, but a shared helper would
need nearly as many parameters (key URL, repo URL, package name, keyring
filename, ...) as the duplication it would save. Two similar, complete,
independently-readable functions beat one function that's a maze of
parameters standing in for what's really "Terraform" vs. "Azure CLI."

Piece by piece:

- **Idempotent path resolution.** `"${1:-${OMAWSL_TERRAFORM_APT_SOURCES_FILE:-/etc/apt/sources.list.d/hashicorp.list}}"`
  nests two parameter-expansion fallbacks: use the first positional
  argument if one was passed; otherwise use the
  `OMAWSL_TERRAFORM_APT_SOURCES_FILE` environment variable if *that's*
  set; otherwise fall back to the real system path. This mirrors a
  convention already established by `lib.sh`'s `OMAWSL_STATE_DIR` and
  Phase 2's `docker.sh`: **any filesystem path a script would otherwise
  hardcode gets an env-var override**, specifically so tests (and this
  lesson's check) can point it at a scratch directory instead of the real
  `/etc/apt/...`, without needing to change the function's own code.
- **`if command -v terraform &>/dev/null; then return 0; fi`** — the same
  "already there, do nothing" idempotency check `mise.sh` uses, at the top
  of the function, before anything else runs.
- **`if [[ ! -f "$apt_sources_file" ]]`** — the repo-add steps
  (installing the keyring, fetching+dearmoring the key, writing the source
  line, `apt-get update`) only run the *first* time; once the sources file
  exists, a re-run skips straight to `apt-get install`, which itself
  no-ops on an already-installed package.
- **The `{ ... } || ok=0` block** is the failure-isolation mechanism the
  outline calls out. Every script in this project runs under
  `set -euo pipefail`, which means *any* single failing command normally
  aborts the whole script immediately. That's the right default almost
  everywhere — but not here: HashiCorp's or Microsoft's repo being
  unreachable for one user, on one run, must report *that one tool* as
  failed and let the rest of the install (the *other* cloud tool, and
  everything scheduled after `cloud-tools.sh`) keep going. Wrapping the
  whole attempt in `{ ... } || ok=0` catches any failure inside the braces
  without killing the script — `ok` starts at `1`, and only gets set to
  `0` if something inside the block returned non-zero.
- **`&&`, not `;`, chains every step inside the braces** — and this is a
  genuinely subtle bash behavior worth knowing on its own, independent of
  this project: bash disables `-e` checking for *every* command inside a
  compound command that sits on the left-hand side of `||` — not just the
  last one. A block written as `{ cmd1; cmd2; cmd3; } || ok=0` would keep
  running `cmd2` and `cmd3` even after `cmd1` failed, silently, because
  `-e` isn't watching inside there at all. Chaining with `&&` instead
  (`cmd1 && cmd2 && cmd3`) makes the *chain itself* stop at the first
  failure, using ordinary short-circuit evaluation — nothing to do with
  `-e` — so a failed key fetch correctly means the source file never gets
  written and `apt-get update` never runs against a half-configured repo.
- **On failure, `sudo rm -f "$apt_sources_file"`** before printing the
  message — this is Bug 2's fix, covered below.
- **The final `sudo apt-get install -y terraform`** runs whether or not
  the repo-add branch just ran (it's chained after the `if` with its own
  `&&`, still inside the same `{ }` block) — so both "first run, just
  added the repo" and "later run, repo already configured" end at the
  same install attempt.

`omawsl_cloud_tools` itself is almost trivial by comparison — exactly the
same shape as `omawsl_select_dev_language`, reading the same
`OMAWSL_LANGUAGES` picker for the `"Terraform"`/`"Azure CLI"` labels:

```bash
omawsl_cloud_tools() {
  local languages="${OMAWSL_LANGUAGES:-}"

  if omawsl_list_has "$languages" "Terraform"; then
    omawsl_install_terraform
  fi

  if omawsl_list_has "$languages" "Azure CLI"; then
    omawsl_install_azure_cli
  fi
}
```

Its comment in the real source is worth repeating verbatim, because it
states the isolation guarantee at the level that actually matters to a
caller: "Each install function already swallows its own failure internally
and always returns 0, so no extra isolation logic is needed here — a
failed Terraform install simply doesn't stop Azure CLI from still being
tried." The isolation lives entirely inside each tool's own function; the
dispatcher above doesn't need to know anything about it.

### Bug 1 — PATH export ordering (`configs/bashrc`, commit `7e9b10b`)

`mise.sh` itself gets the ordering right, as shown above. But making
`mise` reachable in a brand-new, *later* interactive shell — the one a
user opens tomorrow morning — is a separate job, done in `configs/bashrc`
(the file `a-shell.sh`, from Phase 1, installs to `~/.bashrc`). The
original version of that file had:

```bash
if command -v mise &>/dev/null; then
  eval "$(mise activate bash)"
fi

if [ -d "$HOME/.local/bin" ]; then
  export PATH="$HOME/.local/bin:$PATH"
fi
```

— the exact same mistake `mise.sh` avoided, in the opposite file: the
presence check runs **before** the `PATH` export that would make it
findable. A real, manual end-to-end run on a real machine confirmed the
symptom precisely: `mise --version` worked (because `mise`'s installer
also happens to be found some other way at that point), but `go`,
`ruby`, `gem`, and `rails` did **not** — even though `mise ls` correctly
showed them installed. `mise activate bash` (the line that actually wires
mise's shims onto `PATH` for an interactive shell) had simply never run,
in *any* shell, ever, because its own gate always failed. The fix was
exactly reordering the two blocks — export first, then check-and-activate
— restoring the same ordering `mise.sh` already had right.

The general lesson: **whenever code both "installs something under a
non-default `PATH` entry" and "checks whether that thing is already
installed," the `PATH` export has to run first, deterministically, every
time** — not "usually," not "in the case I tested." A test that only
exercises a completely fresh install (nothing under `$HOME/.local/bin`
yet) can pass with either ordering; only a *second* run, or a run against
a machine with the tool already there, exposes the bug.

### Bug 2 — a broken apt source poisons a later, unrelated `apt-get update` (commit `18134f5`)

The most severe of the three, found during the same manual verification
pass. Terraform installed and worked. Azure CLI did not: Microsoft's
`azure-cli` apt repo didn't yet have a Release file published for that
Ubuntu release's codename — a real, current limitation on Microsoft's
end, correctly caught and reported by the failure-isolation block covered
above.

But the *cleanup* was missing. The failed attempt still left a
half-configured `/etc/apt/sources.list.d/azure-cli.list` sitting on disk.
Later in that same run, `libraries.sh` — a completely unrelated script,
several steps later, sharing no code with `cloud-tools.sh` at all — called
its own `apt-get update`, which failed too, because `apt-get update`
checks *every* configured repository in `/etc/apt/sources.list.d/`, not
just the ones a particular command cares about. One broken listing fails
the whole command. And because `libraries.sh` runs under the same
`set -euo pipefail` as everything else, *that* failure — in a script that
had nothing to do with cloud tools — silently aborted the entire
`install.sh` run, before `"install complete"` ever printed.

The per-tool failure isolation from Bug 2's neighbor only protected each
function's own return code; it did nothing about the *filesystem state*
that failure left behind for every later step (this run, or a future
re-run) to trip over. The fix is the `sudo rm -f "$apt_sources_file"` line
shown in the walkthrough above — added to the failure branch of both
`omawsl_install_terraform` and `omawsl_install_azure_cli`: on any failure,
remove the sources file, so neither a later step in the same run nor a
future re-run of this same function ever sees a broken repo listing.

The general lesson: **"isolate the failure" and "clean up after the
failure" are two different obligations.** Catching a failure so it
doesn't crash the caller is necessary but not sufficient if the failed
attempt also left behind state that something else — possibly something
that shares no code with the function that failed — will later depend on
being correct.

### Bug 3 — `gpg --dearmor` hangs without `--yes` (commit `7105055`)

Found on a *third* manual run, confirming the Bug 2 fix. Azure CLI's
**key fetch** had actually succeeded on the earlier, pre-fix failed run
(only the later `apt-get update` step had failed), leaving
`/etc/apt/keyrings/microsoft.gpg` already in place. Re-running
`install.sh` hit `gpg --dearmor -o <file>`'s own idempotency gap: when its
output file already exists, `gpg` interactively prompts `File exists.
Overwrite? (y/N)` — and a non-interactive script has no human standing by
to answer that prompt, so it hangs forever.

The fix is the `--yes` flag already visible in this lesson's code above:
`sudo gpg --yes --dearmor -o "$keyrings_dir/hashicorp.gpg"` — `--yes`
tells `gpg` to assume "yes" for any confirmation it would otherwise ask
interactively, making the overwrite deterministic instead of blocking.
The commit applied this identically to *three* call sites at once — both
functions in `cloud-tools.sh`, plus the structurally identical `gpg
--dearmor` call already present in Phase 2's `docker.sh` — because all
three share the exact same latent risk, even though only Azure CLI's had
actually been triggered by a real run yet.

The general lesson, and the throughline for all three of this phase's
bugs: **"idempotent" isn't one property a function either has or doesn't
— it's a claim you have to check against *every* external command inside
it, including ones (like an interactive confirmation prompt) whose
non-idempotent behavior only shows up on a second run against
partially-completed state from the first.** A test suite built entirely
around fresh, first-time runs — which is what stubbed, from-scratch bats
tests naturally are — will never surface this class of bug on its own.
That's exactly why this plan's Task 6 ends every phase with a mandatory,
real, unstubbed, **repeated** manual run: the first run proves the happy
path; a second (and here, third) run against the state the first one left
behind is what actually proves idempotency.

## 3. Exercise

Close this lesson and rebuild it from scratch, blind, in
`practice/03-languages-and-cloud-tools/dev-environment.sh`. Unlike the
real project (three separate files), this exercise asks for one combined
script — read the detailed spec comment already sitting at the top of the
stub file in that directory before you start; it lays out exactly what
`dev-environment.sh` must do when run as `bash dev-environment.sh`:

- Bootstrap `mise` (export `$HOME/.local/bin` onto `PATH` **before**
  checking whether `mise` is already reachable, then install it via `curl
  -fsSL https://mise.run | sh` only if it still isn't).
- Read `OMAWSL_LANGUAGES` (comma-delimited, possibly unset) and, for each
  of the eight language labels present, run the matching `mise use
  --global <tool>@latest` — with `"Ruby on Rails"` additionally running
  `mise exec ruby@latest -- gem install rails --no-document` on top of
  `ruby`'s own `mise use --global`.
- Read the same `OMAWSL_LANGUAGES` variable for `"Terraform"` and `"Azure
  CLI"` and, for each selected, install it from its own third-party apt
  repo (exact key URLs, repo URLs, package names, and env-var path
  overrides are all specified in the stub file) — idempotent (skip the
  repo-add once its sources file already exists), with `gpg --dearmor`
  passed `--yes`, and with the whole repo-add + install wrapped so a
  failure for one tool prints a message naming the tool and the word
  "failed," removes that tool's own (possibly now-broken) sources file,
  and lets the script continue — including still attempting the *other*
  cloud tool, if it was also selected.

The stub file's spec comment gives you the exact external command shapes
(`curl`, `gpg`, `sudo <subcommand>`, `mise`) the check below is going to
observe — read it closely, it's the actual grading contract. What you name
your own internal functions and variables is entirely up to you.

Don't look back at this lesson's code while you write it. Get something
you believe is correct, then move to the Check step.

## 4. Check

Run:

```bash
practice/03-languages-and-cloud-tools/check.sh
```

This never touches a real network, a real `/etc/apt`, or your real
`$HOME` — every scenario it runs invokes your `dev-environment.sh` as a
real, separate process, with `HOME`, the working directory, and `PATH` all
redirected into a throwaway scratch directory, and with `curl`, `gpg`, and
`sudo` replaced by fake versions that just record what they were asked to
do instead of actually running. A couple of scenarios also drop a tiny
fake `mise` executable into the scratch `$HOME/.local/bin`, to check that
your script finds it (or correctly doesn't) at the right moment. Real
`terraform`/`az` binaries, if you happen to have either installed on the
machine running this check, are also excluded from every scenario's
`PATH` on purpose — same reasoning as Phase 2's own manual-testing notes
about a "safe" PATH list not staying safe forever once real tools get
installed.

Every scenario prints its own `PASS:`/`FAIL:` line, and the check keeps
running every scenario even after an early one fails, so one run shows you
everything that's wrong, not just the first thing.

Read a `FAIL:` line as a description of *behavior* that didn't match —
e.g. "curl was called even though the sources file already existed" tells
you the idempotency check for the repo-add step is missing or checking the
wrong thing; "the script exited non-zero after Terraform's install failed"
tells you the `{ ... } || ok=0`-style failure isolation isn't actually
catching the failure (or isn't using `&&` to stop the chain, and a later
step in the chain is what's really failing). None of the `FAIL:` lines
tell you which line of your code to change. A passing check means your
`dev-environment.sh` is behaviorally correct for everything it exercises,
even if it looks nothing like the original — different variable names, a
`case` statement instead of a run of `if`s, a different order of the
per-language checks, all fine, as long as the external commands and their
arguments come out the same. If you want to compare approaches purely as
a study aid afterward, you can look at the real `install/terminal/mise.sh`,
`install/terminal/select-dev-language.sh`, and
`install/terminal/cloud-tools.sh` in this repo (or `git show
4d8c0da:install/terminal/cloud-tools.sh` for the exact commit this phase
ended on) — but only after your check passes, and only for style, never as
the grade.
