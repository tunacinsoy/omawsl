# Lesson 14: Ubuntu 24.04 and editor-picker fixes

## 1. Concept

Every previous phase built something new. This phase builds nothing new —
it's the first lesson in a different, equally real kind of work: running
software you already wrote against reality, and fixing what reality finds
that your tests didn't. Four unrelated small bugs/decisions surfaced this
way, each teaching a distinct idea:

1. **A PATH-timing false negative in the opencode install guard.** The
   installer's "is this already installed?" check can be technically
   correct and still lie, because of *when* it runs relative to how shells
   load their `$PATH`.
2. **GitHub Copilot CLI's real binary name changing out from under an
   idempotency check.** An "already installed?" guard encodes an assumption
   about *what installed looks like*. When the vendor changes that shape,
   the guard doesn't get an error — it just quietly starts giving the wrong
   answer.
3. **Swapping Gemini CLI for Antigravity CLI in the editor picker.** Not a
   bug — a product decision (a vendor retired the old option) — but one
   that ripples through every place in the codebase a picker option's
   identity is threaded, which is itself worth seeing once.
4. **Installing `gum` from its own apt repository** instead of assuming
   Ubuntu's built-in "universe" repo carries it on every supported release.

Two vocabulary items worth having precisely, since the rest of this lesson
leans on them:

**Idempotency guard.** "Idempotent" means running an operation twice has
the same effect as running it once. The installer scripts in this project
achieve that with a guard: `if <already installed?>; then return 0; fi`,
followed by the real install command. The guard is a *separate* piece of
logic from the install itself, and it encodes its own belief about what
"already installed" looks like — usually "is some command resolvable on
`$PATH`?" That belief can go stale independently of the install command
still working correctly: if the *shape* of "installed" changes (a
different binary name, a path that needs an extra step to reach `$PATH`),
the guard can start giving wrong answers even though nothing about the
install step itself broke. That's the throughline for fixes #1 and #2
below — two different ways an idempotency guard's assumption drifted from
reality.

**PATH-timing race.** `$PATH` is the shell's list of directories it
searches, in order, when you type a bare command name — `command -v
opencode` walks that list looking for a file named `opencode`. Nothing
about `$PATH` updates automatically when a new directory gets created on
disk; a running shell process has whatever `$PATH` value it started with
(or has since explicitly changed), and picks up no new entries just
because `~/.bashrc` describes a different one. `~/.bashrc` only *runs*
when a new shell starts. So if an install step adds a new directory to
`$PATH` via a line in `~/.bashrc`, a fresh shell opened afterward sees it
— but the *very same shell* that's still mid-way through running the
installer does not, because it already loaded its `$PATH` before that
line was ever added and isn't going to re-source `~/.bashrc` on its own.
Checking `command -v` for that tool, in that same shell, right after
installing it, can therefore report "not found" even though the file
exists right there on disk. That's not a bug in `command -v` — it's doing
exactly what it's supposed to do, searching the `$PATH` it actually has.
It's a timing mismatch between "when does the file exist" and "when does
this process's `$PATH` know to look for it," not two processes racing each
other in the classic sense, but the same shape of bug: correctness depends
on an ordering the code didn't actually guarantee.

## 2. Walkthrough

### Fix 1 — opencode's PATH-timing false negative

Before (`install/terminal/app-opencode.sh`, simplified):

```bash
omawsl_install_opencode() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "opencode"; then
    return 0
  fi

  if command -v opencode &>/dev/null; then
    return 0
  fi

  omawsl_opencode_install_steps
}
```

opencode's own installer (`curl -fsSL https://opencode.ai/install | bash`)
places the binary at `$HOME/.opencode/bin/opencode`. This project's
`configs/bashrc` is what adds `$HOME/.opencode/bin` to `$PATH` — but that
line only takes effect for a shell that starts *after* it's been sourced.
Compare that to `$HOME/.local/bin`, which several other tools in this
project also install into: Ubuntu's own default `~/.profile` (present on
every fresh account, not something this project wrote) already puts
`~/.local/bin` on `$PATH` before omawsl's own `~/.bashrc` logic ever runs.
opencode's install directory has no such head start — it depends entirely
on this project's own config, sourced once, at shell startup.

The practical consequence: run `install.sh` once, and it installs
opencode. Run it again *in that same shell* — to pick up a later editor
selection, or just because the user re-ran it — and `command -v opencode`
reports "not found," even though `$HOME/.opencode/bin/opencode` is sitting
right there on disk, because this shell's `$PATH` hasn't been refreshed.
The guard's answer is wrong, so it reinstalls unnecessarily: wasted
network time at best, and the sort of bug that's very easy to write and
very easy for a test suite to miss (a fresh bats-core process for every
test naturally starts with a `$PATH` that reflects wherever the stub
binary landed, so this exact staleness never occurs in an artificial test
shell the way it does across two real, sequential runs of the same
long-lived shell).

The fix, from commit `1f9b6d8`:

```bash
if command -v opencode &>/dev/null || [[ -x "$HOME/.opencode/bin/opencode" ]]; then
  return 0
fi
```

Two independent checks, either one sufficient: the normal `$PATH` lookup
(covers a fresh shell, or any other tool that happens to already be on
`$PATH`), *or* a direct check of the one specific path this project's own
installer is known to write to. This isn't "make the guard smarter in
general" — it's "this guard already knows exactly where its own installer
puts the binary, so also just look there directly," which sidesteps the
`$PATH` staleness question entirely for the one case this project
actually controls. A more general fix — re-sourcing `~/.bashrc` mid-script
to refresh `$PATH` — would also work, but would affect every other
variable and alias `~/.bashrc` sets, not just the one directory this guard
cares about; checking one known path is a narrower, more predictable fix
for a narrow problem.

### Fix 2 — GitHub Copilot CLI's idempotency check outliving its own binary shape

Before (`install/terminal/app-gh-copilot.sh`, prior to commit `eeb1a67`):
GitHub Copilot CLI used to be installed as a `gh` extension —
`gh extension install github/gh-copilot` — invoked afterward as `gh
copilot ...`. The idempotency guard matched that shape:

```bash
if gh extension list 2>/dev/null | grep -q 'github/gh-copilot'; then
  return 0
fi
```

GitHub retired that distribution path. Copilot CLI is now a standalone npm
package, `@github/copilot`, installed the same way this project already
installs Codex CLI (a private mise-managed Node runtime plus a
`$HOME/.local/bin/copilot` wrapper script — see `omawsl_install_npm_cli_wrapper`
in `install/lib.sh`), and invoked as a bare `copilot` command — not `gh
copilot`. The old guard's whole premise — "installed" means "shows up in
`gh extension list`" — stopped describing reality the moment the
distribution channel changed, even though the *guard's own code* never
changed and never threw an error. It would have kept confidently reporting
"not installed" forever, since the new `copilot` binary was never going to
show up in `gh extension list` output, triggering a full reinstall on
every single run.

The fix updates the guard to match the binary's actual current shape:

```bash
omawsl_install_gh_copilot() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "GitHub Copilot CLI"; then
    return 0
  fi

  omawsl_gh_copilot_remove_old_extension

  if command -v copilot &>/dev/null; then
    return 0
  fi

  omawsl_gh_copilot_install_steps
}
```

`command -v copilot` — the same plain `$PATH` lookup every other CLI in
this project's guards uses — because that's what "installed" now actually
means. Notice this commit also added
`omawsl_gh_copilot_remove_old_extension`, called unconditionally before
the guard check, even on a machine where `copilot` is already installed.
That's a **migration**: a one-time cleanup step for state left behind by
the *old* code, for anyone who picked "GitHub Copilot CLI" before this
fix shipped and now has the retired `gh` extension sitting around
alongside the new binary. A migration function's defining trait is that
it's safe to keep running forever — on a machine that never had the old
extension, `gh extension list` just won't match anything, and the function
quietly no-ops. It doesn't get removed once "everyone's migrated," because
there's no reliable way to know that; it just becomes free of any real
work to do.

### Fix 3 — Gemini CLI to Antigravity CLI: a product decision, and its fan-out

Google retired Gemini CLI's individual-account sign-in in favor of a
different suite, Antigravity, which ships its own CLI (`agy`) via a native
curl installer rather than Gemini CLI's old npm/mise path — so the
replacement follows Claude Code CLI's install shape instead (see
`install/terminal/app-antigravity-cli.sh`, structurally identical to
`app-claude-cli.sh`, guarded by `command -v agy`). This isn't a bug fix;
it's swapping which vendor tool occupies one slot in the editor/AI-tooling
picker, in response to a fact about the outside world changing (a vendor
discontinued a product), the same category of decision as Fix 2's "GitHub
retired an install path," just one level up — a whole product being
retired instead of one install mechanism.

The one-line change a learner might expect —
`install/first-run-choices.sh`'s option list, `"Gemini CLI"` becoming
`"Antigravity CLI"` — is real, but it's not the whole story. This project
has no single lookup table mapping a picker option's display string to
everywhere that string's *identity* matters; each picker option is a
literal string threaded, by hand, through several independent places:

- `install/first-run-choices.sh` — the string shown in the picker itself
- `install/terminal.sh` — which install script and function run for it
- `bin/omawsl-sub/items.sh` — the option's category, its display label, and
  its slug (a short internal identifier used everywhere below)
- `bin/omawsl-sub/orphan-tools.sh` — how `bin/omawsl update` detects
  whether it's installed and what "the latest version" means for it
- `bin/omawsl-sub/doctor.sh`, `bin/omawsl-sub/uninstall.sh` — the same
  "is it installed" and "how do I remove it" questions, asked again
- `uninstall/app-antigravity-cli.sh` (new file, replacing
  `uninstall/app-gemini-cli.sh`)
- the bats-core tests for every one of the above, plus a few docs

That's a real architectural tradeoff worth noticing, not a mistake: a
lookup-table-driven design (one canonical place mapping slug → label →
install function → uninstall function → ...) would make a swap like this
touch one place instead of eight, at the cost of an extra layer of
indirection everywhere else reads that mapping. This project chose the
directness of a literal string/case-statement per file instead — cheaper
to read any single file in isolation, more places to touch when one option
changes identity. Neither choice is simply "correct"; it's the same kind
of tradeoff as a lookup table vs. a case statement inside one file, just
at a larger scale.

### Fix 4 — installing `gum` from Charm's own apt repository

`gum` is the TUI tool every prompt in this installer runs on — including
the very first one, `omawsl_first_run_choices`. The original install
(Phase 1) was a plain `sudo apt-get install -y gum`, verified against a
real Ubuntu 26.04 machine, where `gum` happens to already be present in
Ubuntu's own built-in "universe" repository (the second-tier collection of
community-maintained packages Ubuntu ships alongside its core "main"
repository). But this project's actual supported floor is Ubuntu 24.04,
and `gum` didn't land in the universe repo until 26.04 — so on 24.04 or
25.x, that same `apt-get install gum` line 404s with "Unable to locate
package gum," aborting the installer before it can prompt for anything at
all, since the tool that renders every later prompt never installed.

The fix (`install/terminal/required/app-gum.sh`, commit `a90b88d`) adds
Charm's own apt repository — the maintainer of `gum` publishes one
directly — instead of trying to branch behavior on the Ubuntu version
number:

```bash
omawsl_install_gum() {
  local apt_sources_file="${1:-/etc/apt/sources.list.d/charm.list}"
  local keyrings_dir="${2:-/etc/apt/keyrings}"

  if [[ ! -f "$apt_sources_file" ]]; then
    sudo install -m 0755 -d "$keyrings_dir"
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --yes --dearmor -o "$keyrings_dir/charm.gpg"
    echo "deb [signed-by=$keyrings_dir/charm.gpg] https://repo.charm.sh/apt/ * *" \
      | sudo tee "$apt_sources_file" >/dev/null
  fi

  sudo apt-get update -qq
  sudo apt-get install -y gum
}
```

A few things worth understanding piece by piece, true beginner level:

- **Why a GPG key at all?** `apt` refuses to install from a repository it
  can't verify came from who it claims to — otherwise anyone who could get
  a URL in front of your machine could serve malicious packages disguised
  as `gum`. The repository maintainer signs their package index with a
  private key; apt needs the matching *public* key to check that
  signature before it'll trust anything from that source.
- **"Dearmor."** GPG keys are normally distributed as ASCII text (an
  "armored" format — safe to email, paste, or serve over plain HTTP)
  but apt's keyring format wants raw binary. `gpg --dearmor` converts one
  to the other; the `-o` flag says where to write the binary result.
- **Why `sudo tee` instead of a redirect?** `echo "..." > "$apt_sources_file"`
  would try to open `/etc/apt/sources.list.d/charm.list` for writing as
  the *current* (non-root) user, and fail — redirection happens in the
  calling shell, before `sudo` (which only applies to the command on its
  left) ever gets involved. Piping into `sudo tee <file>` instead runs
  `tee` itself as root, so the write happens with root's permissions;
  `tee` echoes its input back to stdout too, which is why the real code
  redirects that to `/dev/null` — here, only the file write is wanted.
- **Idempotency, again, but a different shape than fixes 1-2.** `apt-get
  install` is already idempotent on its own — installing an
  already-current package is a safe no-op — so no extra guard is needed
  around that part. What *does* need guarding is the repository-add
  itself: re-running `sudo tee` and re-fetching the GPG key every single
  time this function runs would be wasteful (and, depending on apt's
  mood about a key changing out from under an existing file, possibly
  disruptive). The guard here is `[[ ! -f "$apt_sources_file" ]]` — "has
  this repo already been added?" — a file-existence check, not a
  `command -v` check, because what's being made idempotent is "adding a
  repository," not "installing a binary."
- **Why parameters instead of hardcoded paths?** `apt_sources_file` and
  `keyrings_dir` default to the real system locations
  (`/etc/apt/sources.list.d/charm.list`, `/etc/apt/keyrings`) but can be
  overridden by whoever calls the function. This is a small instance of
  **dependency injection** — instead of a function reaching out and
  grabbing a fixed, global resource (here, a hardcoded absolute path) by
  itself, the caller hands it in as an argument. The function's own logic
  doesn't change either way; what changes is that a test can now point it
  at a scratch directory instead of the real `/etc/apt`, without needing
  to fake out the filesystem itself.

## 3. Exercise

Close this lesson and rebuild it from scratch, blind, in
`practice/14-ubuntu-24-04-and-editor-picker-fixes/`. Four files are
already there with a `TODO` comment each describing exactly what to
implement — read each file's comment for the full spec before writing
code. In short:

- **`app-opencode.sh`** — implement `omawsl_install_opencode`. A stub
  `omawsl_opencode_install_steps` is already provided (don't change it —
  it stands in for the real network install and just logs that it ran).
  Your guard must treat opencode as "already installed" if *either*
  `command -v opencode` succeeds *or* an executable file exists at
  `$HOME/.opencode/bin/opencode` — and only call
  `omawsl_opencode_install_steps` when neither is true.
- **`app-gh-copilot.sh`** — implement `omawsl_install_gh_copilot`. Same
  shape: a provided `omawsl_gh_copilot_install_steps` stub, and your job
  is the guard, which must check for the binary's *current* real name —
  think about what that name actually is, from the walkthrough above,
  not what it used to be.
- **`app-gum.sh`** — implement `omawsl_install_gum`, taking two optional
  arguments (`apt_sources_file`, `keyrings_dir`) with the same real-path
  defaults as the original. This one really does call `sudo`, `curl`,
  and `apt-get` — that's fine and expected; the check script contains
  those calls safely (see below), you don't need to do anything special
  in your implementation to make that safe.
- **`editor-options.sh`** — implement `omawsl_editor_picker_options`,
  printing the picker's option list, one per line, in order, with
  `"Antigravity CLI"` in the slot `"Gemini CLI"` used to occupy.

## 4. Check

Run:

```bash
bash practice/14-ubuntu-24-04-and-editor-picker-fixes/check.sh
```

It prints one `PASS:`/`FAIL:` line per behavior it checks — nine in
total, covering all four fixes — and exits non-zero if anything failed.
A `FAIL:` line describes the *behavior* that didn't match (e.g. "opencode
installed at `$HOME/.opencode/bin/opencode` but not on PATH -> install
steps ran anyway" means your guard is still only checking `command -v`
and missing the direct-path check), not which lines of your code differ
from the original — a passing check means your solution is behaviorally
correct, even if it's structured completely differently from the
original. Once it passes, you're welcome to look at the real source
(`install/terminal/app-opencode.sh`, `install/terminal/app-gh-copilot.sh`,
`install/terminal/required/app-gum.sh`, `install/first-run-choices.sh` in
the target repo) purely to compare style — never as the grade.
