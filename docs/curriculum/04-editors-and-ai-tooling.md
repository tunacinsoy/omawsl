# Lesson 4: Editors & AI Tooling

## 1. Concept

By the end of Phase 3, `first-run-choices.sh` already asks the user to pick
their editors and AI CLIs — `OMAWSL_EDITORS` is a comma-delimited string
like `"VS Code,Neovim,Codex CLI"`, built the exact same way
`OMAWSL_LANGUAGES` was (Lesson 1's `omawsl_prompt_multi` +
`omawsl_list_has`). Nothing has actually installed any of them yet. This
phase closes that gap for eight tools at once: VS Code, Cursor, Neovim,
opencode, Claude Code CLI, Codex CLI, GitHub Copilot CLI, and (originally)
Gemini CLI.

Three design questions have to be answered before writing any of the eight
scripts, and the answer to each one is a piece of vocabulary you'll reuse
for the rest of this project:

**How do eight independent, optional installs plug into one orchestrator
without becoming one giant script?** Lesson 1 already built the mechanism
— `terminal.sh`'s `OMAWSL_TERMINAL_SCRIPTS` array plus a loop that
`source`s each one and calls its main function. Phase 4 doesn't invent
anything new here; it just adds eight more entries. Each new script is
called an `app-*.sh` script, and each one independently checks whether
*its own* tool was selected and no-ops (does nothing, successfully) if
not. This "fan out to many same-shaped scripts, each self-gating" pattern
is worth naming precisely: it's a **dispatch table** — a lookup structure
(here, an array plus an associative array of script-path → function-name
pairs) that replaces what would otherwise be a giant hand-written
`if/elif/elif/.../elif` chain. A dispatch table wins here for the same
reason a phone book beats a chain of "is your name Alice? Is it Bob? Is
it Carol?" questions: adding a ninth tool later means adding one line to
a list, not editing a growing conditional.

**What happens when two of the eight tools are basically the same
thing?** VS Code and Cursor are different applications, but Cursor is a
fork of VS Code and reads the exact same settings-file format. Writing
two nearly-identical JSON files (one for each) would mean every future
settings tweak has to be made twice, correctly, forever — a classic
violation of a principle worth naming explicitly: **DRY, "don't repeat
yourself."** Phase 4's answer is one shared file, `configs/vscode.json`,
copied to two different destinations by two different scripts.

**How should each tool actually get installed, given they don't all
distribute themselves the same way?** Some tools ship an official
native-binary installer (`curl | bash`) — use that directly, it's the
simplest and most trustworthy path. Two tools (Codex CLI, Gemini CLI)
have *no* distribution channel except npm. Phase 3 already hit a real bug
in the naive approach to "install something through `mise`, then just
assume it's reachable": `mise use --global ruby@latest` only *pins* a
version in `mise`'s own config — it does not put that Ruby's shims on the
current shell's `PATH` (that's `mise activate`'s job, and it's meant for
*interactive* shells, not a one-shot install script). A bare `gem
install rails` after that pin hit nothing on `PATH` and aborted the whole
run under `set -e`. Phase 3's fix was `mise exec ruby@latest -- gem
install rails` — resolve the tool's shims onto `PATH` explicitly, for
just that one command. Phase 4 applies the identical fix pre-emptively:
install the npm package via `mise exec node@lts -- npm install -g ...`,
then write a **wrapper script** into `$HOME/.local/bin` that re-resolves
through `mise exec` on *every* invocation, forever — rather than trusting
`mise`'s shim mechanism to expose a binary from an ad-hoc npm install
automatically. Explicit and repeated beats implicit and assumed.

Finally, this phase is the origin of a bug severe enough to be this
lesson's centerpiece: one unisolated command failure, in a script that's
`source`d rather than run as a separate process, silently killed every
script scheduled to run after it — with no error message pointing at what
happened. Understanding exactly why requires understanding, precisely,
what `set -e` promises and where that promise has built-in exceptions.
That's the second half of the Walkthrough below.

## 2. Walkthrough

### The dispatch table, extended

Lesson 1 left `install/terminal.sh` with an array and a matching
associative array (`declare -A`, a **dictionary** — keys mapped to
values, unlike a plain array which is just values in order):

```bash
OMAWSL_TERMINAL_SCRIPTS=(
  "terminal/required/app-gum.sh"
  "terminal/identification.sh"
  ...
)

declare -A SCRIPT_FUNCTIONS=(
  ["terminal/required/app-gum.sh"]="omawsl_install_gum"
  ...
)

for script in "${OMAWSL_TERMINAL_SCRIPTS[@]}"; do
  source "$OMAWSL_INSTALL_DIR/$script"
  "${SCRIPT_FUNCTIONS[$script]}"
done
```

Phase 4's commit `07ceb9c` ("wire all 8 editor/AI-tool scripts into
terminal.sh's dispatch table") just appends eight more lines to each
array/dictionary:

```bash
OMAWSL_TERMINAL_SCRIPTS=(
  ...
  "terminal/select-dev-storage.sh"
  "terminal/app-vscode.sh"
  "terminal/app-neovim.sh"
  "terminal/app-opencode.sh"
  "terminal/app-cursor.sh"
  "terminal/app-claude-cli.sh"
  "terminal/app-codex-cli.sh"
  "terminal/app-gh-copilot.sh"
  "terminal/app-antigravity-cli.sh"
)
```

Nothing about the loop itself changes. That's the entire point of having
built a dispatch table in Lesson 1: extending "the set of things this
orchestrator does" is a data change (add a line to a list), not a code
change (write a new branch of logic). Every one of the eight new scripts
has the exact same shape as `app-gum.sh` from Lesson 1 — a function, and
a guard at the bottom (`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
... fi`) so it's independently runnable, per the plan's Global
Constraint "every install script must be runnable in isolation."

### Gating on user selection: `omawsl_list_has`, called by every script

Each `app-*.sh` script's function starts with the exact same shape —
check whether *this tool specifically* is in `OMAWSL_EDITORS`, and return
immediately (successfully — exit `0`) if not:

```bash
omawsl_install_codex_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Codex CLI"; then
    return 0
  fi
  ...
}
```

This is `omawsl_list_has` from Lesson 1's `lib.sh`, unchanged. Worth
noting *where* the gate lives: it's inside each tool's own function, not
in `terminal.sh`'s loop. `terminal.sh` doesn't know or care which tools
were picked — it unconditionally sources and calls all eight scripts,
every run, and trusts each one to decide for itself whether it has
anything to do. That design choice — the dispatcher stays dumb, each
dispatched piece is responsible for its own gating — turns out to matter
a great deal later in this lesson.

### Sharing one config: `app-vscode.sh` and `app-cursor.sh`

`configs/vscode.json` (Task 3, commit `dd3db32`) is a small, ordinary
settings file:

```json
{
  "terminal.integrated.defaultProfile.linux": "bash",
  "editor.fontFamily": "'CaskaydiaCove Nerd Font', 'Cascadia Code', monospace",
  "editor.fontLigatures": true,
  "editor.formatOnSave": true,
  "files.trimTrailingWhitespace": true,
  "workbench.colorTheme": "Default Dark Modern"
}
```

VS Code's and Cursor's WSL integrations each look for a *machine-level*
settings file at a fixed path under `$HOME` — `.vscode-server/.../Machine/settings.json`
for VS Code, `.cursor-server/.../Machine/settings.json` for Cursor — that
doesn't exist until the editor has connected to this WSL distro at least
once. Pre-creating it means the settings apply automatically the moment
it does, with no live `code`/`cursor` binary needed at install time.
`app-vscode.sh`'s deploy step is just a `cp`:

```bash
omawsl_install_vscode_settings() {
  local settings_file="${1:-$HOME/.vscode-server/data/Machine/settings.json}"
  mkdir -p "$(dirname "$settings_file")"
  cp "$SCRIPT_DIR/../../configs/vscode.json" "$settings_file"
}
```

`app-cursor.sh` (commit `dbe7536`) does the *same* `cp`, from the *same*
source file, to Cursor's own destination path:

```bash
local settings_file="$HOME/.cursor-server/data/Machine/settings.json"
mkdir -p "$(dirname "$settings_file")"
cp "$SCRIPT_DIR/../../configs/vscode.json" "$settings_file"
```

One file, two consumers — not two files that happen to start out
identical and will inevitably drift apart the first time someone edits
one and forgets the other. Notice, too, what Cursor's script *doesn't*
do: VS Code's script also runs `code --install-extension
ms-vscode-remote.remote-wsl` when `code` is reachable. Cursor's script
never attempts an equivalent `cursor --install-extension` call at all —
not because it was forgotten, but a deliberate scope decision recorded
right in the script's comments: Cursor has its own extension
distribution, and Microsoft's marketplace commonly blocks non-VS-Code
products from installing Microsoft-published extensions. Sharing a
*config* file doesn't force every step of the two scripts to be
identical.

Both scripts also follow the same **detect-and-defer** shape Phase 2
established for Docker Desktop: VS Code and Cursor are Windows-side GUI
apps this WSL installer never auto-installs. If `code`/`cursor` isn't
reachable yet (checked via `omawsl_code_reachable`/`omawsl_cursor_reachable`,
two one-line `command -v` wrappers added to `lib.sh` in this phase), that
isn't treated as an error — the settings file still gets deployed
(useless yet, but ready), a message points at `docs/windows-setup.md`,
and the run continues.

### Picking the right install strategy per tool

`app-claude-cli.sh` (commit `51ebc17`) is the simple case — an official
native-binary installer exists, so use it directly:

```bash
omawsl_install_claude_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Claude Code CLI"; then
    return 0
  fi
  if command -v claude &>/dev/null; then
    return 0
  fi
  curl -fsSL https://claude.ai/install.sh | bash
}
```

Idempotent via a plain `command -v` guard — same as `omawsl_install_lazydocker`
from `apps-terminal.sh` earlier in this phase: the underlying installer
always re-runs unconditionally, so it's this `if`, not the installer
itself, doing the "don't redo work that's already done" job.

`app-codex-cli.sh` (commit `ab068d4`) is the harder case: `@openai/codex`
distributes *only* through npm. This is exactly the class of problem
Phase 3's `gem install rails` bug was:

```bash
omawsl_install_codex_cli() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "Codex CLI"; then
    return 0
  fi
  if command -v codex &>/dev/null; then
    return 0
  fi

  mise exec node@lts -- npm install -g @openai/codex

  mkdir -p "$HOME/.local/bin"
  cat > "$HOME/.local/bin/codex" <<'WRAPPER'
#!/usr/bin/env bash
exec mise exec node@lts -- codex "$@"
WRAPPER
  chmod +x "$HOME/.local/bin/codex"
}
```

Two deliberate choices here, both direct descendants of the Phase 3
lesson:

1. **The install itself goes through `mise exec node@lts --`**, not a
   bare `npm install -g` — this provisions a *private* Node runtime just
   for this call, independent of whatever the user separately picked (or
   didn't pick) in the language picker. That picker is about the user's
   own project runtime; it has nothing to do with what Node version some
   unrelated AI CLI's installer happens to need.
2. **The wrapper script re-resolves through `mise exec` on *every*
   future invocation**, not just the install step. A tempting
   alternative would be relying on `mise`'s own shim mechanism — the
   same mechanism that, left to run non-interactively, was exactly what
   silently failed to put Ruby's `gem` on `PATH` in Phase 3. Rather than
   trust that mechanism again for an ad-hoc npm-driven install, the
   wrapper makes the resolution explicit and repeated: `$HOME/.local/bin/codex`
   (already on `PATH` from Lesson 1's `configs/bashrc`) is a two-line
   script whose only job is to hand off to `mise exec` every time it
   runs. Slightly more verbose than trusting a shim; considerably harder
   to get subtly wrong in a way that only shows up in a *later* shell
   session.

### The case study: isolating a failure that's expected, not exceptional

Recall from Lesson 1 exactly what `set -e` promises: *if any command
fails, the whole script stops immediately.* `terminal.sh` relies on that
promise on purpose — its own comment says so: "sourced (not sub-shelled)
so a failure stops the whole run immediately." **Sourcing** (`source
file.sh`) runs a file's commands inside the *current* process, sharing
that process's variables, functions, and — critically — its `set -e`
state. **Sub-shelling** (running `bash file.sh` as a separate child
process, or wrapping a command in `( ... )`) starts a *new* process; a
failure in a sub-shell doesn't automatically propagate back to the
parent's own `set -e` unless the parent explicitly checks the child's
exit status and reacts to it. `terminal.sh` chose sourcing specifically
so that one script's catastrophic failure — e.g., a genuinely broken
`apt-get` — halts the entire installer right there, rather than limping
on to install more things on top of a broken foundation.

That's the right default. But `app-gh-copilot.sh`'s first version
(commit `46f2668`) applied it to a command that fails for an *ordinary*,
*expected* reason on a huge fraction of installs:

```bash
omawsl_install_gh_copilot() {
  if ! omawsl_list_has "${OMAWSL_EDITORS:-}" "GitHub Copilot CLI"; then
    return 0
  fi
  gh extension install github/gh-copilot
}
```

`gh extension install` requires an authenticated `gh` session. Nobody
has run `gh auth login` before their *first ever* `install.sh` run — that
is the default case, not some rare edge case. On a real WSL2 test
machine, this was confirmed directly: Codex CLI (positioned right before
this script in the dispatch order) installed successfully, and then
Gemini CLI — the very next script in the array — never ran at all. No
error pointed at *why*. `gh extension install` failed, that failure
propagated straight through this sourced script's `set -e`, and
`terminal.sh`'s `for` loop simply never reached its next iteration.

The fix (commit `d3df812`) does two things. First, an idempotency guard,
the same shape as `command -v` elsewhere in this phase but checking a
`gh`-specific state instead:

```bash
if gh extension list 2>/dev/null | grep -q '^gh-copilot'; then
  return 0
fi
```

Second — the actual case-study fix — wrapping the risky call in an `if`:

```bash
if ! gh extension install github/gh-copilot; then
  echo "omawsl: GitHub Copilot CLI install failed (gh not authenticated yet?) - skipping, continuing with the rest of the run."
  echo "Run 'gh auth login', then 'gh extension install github/gh-copilot' yourself, or re-run install.sh."
fi
```

Here's the mechanism, precisely, because it's easy to misremember as "if
statements turn off `set -e`" — they don't, not globally. `set -e`'s
actual rule has a specific, narrow carve-out: a command's exit status
does *not* trigger `-e` when that command is being used as a *test* —
the condition of an `if`, `while`, or `until`, or the left/right side of
`&&`/`||`, or immediately preceded by `!`. In every one of those
positions, bash assumes you're deliberately checking the result, so a
non-zero exit is treated as useful information ("the condition was
false"), not as an uncaught error. `gh extension install github/gh-copilot`
as a bare statement is fatal under `-e`; the *exact same command*, as the
condition of an `if`, is not — its exit status is simply data the `if`
branches on.

This is the general, reusable lesson the phase's outline names directly:
**isolate every external command that can fail, even if the one before
it worked.** `terminal.sh`'s sourcing discipline is correct for failures
that mean something is fundamentally broken. But *inside* any one
script, a specific call that can fail for an ordinary, recoverable
reason — no network, no auth, a tool that's simply not installed yet —
needs its own local `if ! cmd; then ...; fi` guard, right at the call
site, rather than relying on the orchestrator's blunt all-or-nothing
`set -e` to make the right call on its behalf. Note, too, exactly *where*
this fix lives: inside `omawsl_install_gh_copilot` itself, not in
`terminal.sh`'s loop. The dispatcher never grew a safety net — it still
trusts every function it calls to protect itself. That's not an
oversight; go back and look at `terminal.sh`'s loop above, and you'll see
it's completely unchanged by this fix.

(One more ordering note while you're looking at dispatch tables: commit
`ae6d5e7`, folded into this phase, moved `terminal/libraries.sh` earlier
in `OMAWSL_TERMINAL_SCRIPTS` — before `mise.sh`/`select-dev-language.sh`
— because `mise`'s Ruby backend compiles Ruby from source unless a
precompiled binary is available, which needs a C toolchain that only
`libraries.sh` installs. A fixed-order array is still just a list of
steps with implicit dependencies between them; getting the order wrong
is a real, easy-to-make bug class of its own, distinct from the failure-
isolation bug above.)

## 3. Exercise

Close this lesson and build a small dispatcher, blind, in
`practice/04-editors-and-ai-tooling/editors.sh`. This isn't all eight
real scripts — it's a scaled-down version that exercises the same three
ideas: gating on selection, sharing one config between two tools, and
isolating a failure so it doesn't take down tools scheduled after it.

Your file must, when run directly (`bash editors.sh`, guarded the same
way every `app-*.sh` script in this project is — nothing should run on a
plain `source`), dispatch to four tools **in this fixed order**:

1. `vscode`
2. `gh-copilot`
3. `cursor`
4. `neovim`

(This order is deliberate and the check depends on it: `gh-copilot` sits
*between* two tools that must still run after it, mirroring the real bug
— Codex CLI ran, the next script didn't.)

The dispatcher reads `OMAWSL_EDITORS`, a comma-delimited string that may
contain any subset (in any order) of these four exact labels: `VS Code`,
`GitHub Copilot CLI`, `Cursor`, `Neovim`. Each tool's own logic — not the
dispatcher's — must check for its own label (whole-token match, not a
bare substring check) and do nothing if it isn't present.

Behavior required per tool, when selected:

- **`vscode`**: copy the file `baseline-settings.json` (sitting next to
  `editors.sh` in this same directory) to
  `$HOME/.vscode-server/data/Machine/settings.json`, creating any missing
  parent directories.
- **`cursor`**: copy the exact same `baseline-settings.json` file — not a
  separate Cursor-specific copy you maintain yourself — to
  `$HOME/.cursor-server/data/Machine/settings.json`.
- **`neovim`**: if `$HOME/.config/nvim` does **not** already exist, call
  the external command `neovim_installer` (a stand-in for the real
  project's `git clone` step — don't invoke `git` yourself, just call
  `neovim_installer` with no arguments). If `$HOME/.config/nvim` already
  exists, do not call `neovim_installer` at all — an existing config must
  never be touched.
- **`gh-copilot`**: call the external command `gh_copilot_installer` (a
  stand-in for `gh extension install`, with no arguments). This command
  can fail — that's realistic, not a bug in your code, exactly like the
  real `gh extension install` failing because `gh auth login` hasn't run
  yet. **Your job is to isolate that failure** so it does not stop
  `cursor` and `neovim` — the two tools scheduled after it — from still
  running. Go back and re-read the case-study fix above if you're not
  sure how.

The whole file runs under `set -euo pipefail`, same as every script in
this project.

Don't look back at this lesson's code while you write it. Get something
you believe is correct, then move to the Check step.

## 4. Check

Run:

```bash
practice/04-editors-and-ai-tooling/check.sh
```

It runs your `editors.sh` several times, each time in an isolated scratch
`$HOME` (so it never touches your real home directory) and with fake
stand-ins for `neovim_installer`/`gh_copilot_installer` that just record
whether they were called, instead of doing anything real. One scenario
deliberately makes `gh_copilot_installer` fail, exactly like a real
unauthenticated `gh` session would, and checks what happens next. Every
check prints its own `PASS:`/`FAIL:` line, and the script keeps going
through all of them even if an early one fails, so a single run shows you
everything that's wrong, not just the first thing.

Read a `FAIL:` line as a description of *behavior* that didn't match —
e.g. "cursor's settings were not deployed after gh-copilot's installer
failed" tells you the failure from `gh_copilot_installer` propagated past
where you tried to contain it and killed the rest of the dispatch,
exactly like the real bug this lesson is about. It is not telling you
which line to change. A passing check means your dispatcher is
behaviorally correct for everything it exercises, even if it looks
nothing like the original — different variable names, a `case` statement
instead of an associative array for the dispatch table, all fine. If you
want to compare approaches purely as a study aid afterward, you can look
at the real `install/terminal.sh`, `install/terminal/app-gh-copilot.sh`,
and `install/terminal/app-vscode.sh`/`app-cursor.sh` in this repo (or
`git show d3df812` for the exact commit that fixed the case-study bug) —
but only after your check passes, and only for style, never as the
grade.
