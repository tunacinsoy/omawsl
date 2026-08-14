# AI CLI autopilot mode — design

**Date:** 2026-08-14
**Status:** approved
**Scope:** all five AI CLI tools offered in the editors/AI-tooling picker (Claude Code CLI, Codex
CLI, GitHub Copilot CLI, Antigravity CLI, opencode) start in autopilot mode by default, no opt-in
required - closes issue #25. Retires the GitHub Copilot CLI opt-in prompt
(`docs/superpowers/specs/2026-08-09-copilot-autopilot-mode-design.md`, issue #2) entirely.

## Why

Issue #25 asks that "all tools that we offer in terms of ai cli (codex, claude etc)" start in
auto/autopilot mode by default. Issue #2 asked for the same thing for Copilot alone and got
implemented as an opt-in instead, on the reasoning that auto-approving an AI agent's actions is a
safety-relevant default a public installer shouldn't spring on someone unasked. Revisiting that
call for issue #25: the answer is still deliberately the opposite this time - autopilot on by
default for all five, no prompt, no per-machine choice, no override. This is a conscious departure
from `install/first-run-choices.sh`'s own stated principle ("nothing is pre-selected by
default... a public tool should not surprise-install anything the user didn't explicitly ask
for") for these five tools specifically - not an oversight. The tradeoff accepted here: someone
who explicitly wants a *particular* AI CLI installed via the picker is treated as having also
implicitly wanted it to run without per-action confirmation, matching where the industry default
is heading anyway (Claude Code itself switched new sessions to a lighter-touch auto mode by
default as of today, 2026-08-14).

Each tool's actual auto-approve flag, confirmed against its own docs:

| Tool | binary | flag |
|---|---|---|
| Claude Code CLI | `claude` | `--dangerously-skip-permissions` |
| Codex CLI | `codex` | `--dangerously-bypass-approvals-and-sandbox` |
| GitHub Copilot CLI | `copilot` | `--autopilot --allow-all` (unchanged) |
| Antigravity CLI | `agy` | `--dangerously-skip-permissions` |
| opencode | `opencode` | `--auto` |

opencode's `--auto` is the softer of two real flags that surfaced during research (the other,
`--dangerously-skip-permissions`, also appears to exist for opencode via an env var reference) -
`--auto` is used here because it's the one documented on opencode's own primary CLI docs page
rather than secondhand, and "still respects explicit deny rules" is a reasonable semantics for
something turned on unconditionally rather than a shortcoming.

All five are implemented as a shell alias in `configs/bashrc`, matching the mechanism the old
Copilot-only feature already used - one mechanism for all five tools, no persistent settings.json
config even where a tool supports one (Claude Code, Antigravity). Aliases only take effect in
interactive bash shells; a script or another tool invoking the binary directly bypasses them.
Accepted trade-off, for consistency.

**No override mechanism.** There is no `choices.env` key for this, no CLI flag to opt out, no
prompt. If a tool is on PATH, its alias is set - full stop. A future `omawsl config` command
(already out of scope per the original Copilot design, still out of scope here) would be the
place to add an opt-out later if this turns out to be wanted; not building it speculatively now.

**Flag-drift risk accepted, no guard.** These CLIs ship fast. If a future version renames or
removes one of these flags, the alias breaks loudly - the very next invocation of that command
errors out on an unrecognized flag - rather than silently failing to auto-approve. Same accepted
risk as the original Copilot design; a `<tool> --help | grep` existence check at alias-time would
add real complexity (five different `--help` output formats) for a failure mode that's already
immediately obvious, not silent.

## Components

### 1. `install/lib.sh` — `omawsl_notice_ai_autopilot_if_needed <picked_csv> <existing_csv>`

Replaces `omawsl_prompt_copilot_autopilot_if_needed` entirely - no prompt, no persisted choice,
just a one-time informational notice so someone isn't surprised days later that `claude` (or any
of the other four) behaves differently than they remember. Shared helper, called from both the
fresh-install and retrofit paths below.

- For each of the five AI-CLI labels (`Claude Code CLI`, `Codex CLI`, `GitHub Copilot CLI`,
  `Antigravity CLI`, `opencode`) present in `picked_csv` but absent from `existing_csv` (i.e.
  newly selected this run), prints one line naming that specific tool and its flag:
  > `omawsl: <label> starts in autopilot mode by default (<flag>) - auto-approves all tool use, no
  > confirmation.`
- Named per-tool rather than a static list of all five, so the notice never implies a tool the
  user didn't just pick is already being auto-approved.
- No persisted state anywhere - the `picked_csv`/`existing_csv` diff alone gives the "one-time per
  machine" property: once a label is in the persisted `OMAWSL_EDITORS`, it counts as "existing" on
  every later run, so the notice for that tool never fires again.
- No `gum` interaction, no exit code to check, nothing to cancel - this cannot fail short of the
  `echo` itself failing.

### 2. `install/first-run-choices.sh` — fresh-install call site

Immediately after `OMAWSL_EDITORS` is picked, calls
`omawsl_notice_ai_autopilot_if_needed "$OMAWSL_EDITORS" ""` (empty existing-list, first run). Same
call site the old prompt used, renamed function, no more `export`/`omawsl_save_choice` around it
since there's nothing to persist.

### 3. `bin/omawsl-sub/install.sh` — retrofit call site

`omawsl_install_apply_editor` calls `omawsl_notice_ai_autopilot_if_needed "$picked" "$existing"`
right after merging and saving `OMAWSL_EDITORS`, before the per-tool install loop. Covers a user
who installs any of the five AI CLIs after their initial setup.

### 4. `configs/bashrc` — the five aliases

Five `command -v`-guarded alias blocks, unconditional - no `choices.env` read at all, replacing
the single choice-gated Copilot-only block:

```bash
command -v claude &>/dev/null && alias claude="claude --dangerously-skip-permissions"
command -v codex &>/dev/null && alias codex="codex --dangerously-bypass-approvals-and-sandbox"
command -v copilot &>/dev/null && alias copilot="copilot --autopilot --allow-all"
command -v agy &>/dev/null && alias agy="agy --dangerously-skip-permissions"
command -v opencode &>/dev/null && alias opencode="opencode --auto"
```

Placed where the old Copilot-only block was, near the `lzg`/`lzd` tool-conditional aliases. Each
alias independently gated on its own `command -v`, so only the tools actually installed get
aliased, and uninstalling one doesn't require any special-casing elsewhere - once its binary is
gone, `command -v` fails and the alias simply isn't set on the next shell.

### 5. `uninstall/app-gh-copilot.sh` — drop the dead choice-clearing line

Removes `omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT ""`. Nothing reads `OMAWSL_COPILOT_AUTOPILOT`
anywhere after this change (bashrc no longer reads any choice for this feature), so clearing it on
uninstall is dead code from the retired mechanism. The other four uninstall scripts
(`app-claude-cli.sh`, `app-codex-cli.sh`, `app-antigravity-cli.sh`, `app-opencode.sh`) need no new
code at all - see the `command -v` self-guarding note in Component 4.

An existing machine that already has `OMAWSL_COPILOT_AUTOPILOT="No - interactive by default
(recommended)"` persisted from before this change keeps that line sitting inert in
`choices.env` - it's simply never read again. No migration needed: the new default-on behavior
applies uniformly regardless of that history, by design (see "Why").

## Data flow

```
first-run-choices.sh: pick OMAWSL_EDITORS → (per newly-picked AI CLI) print notice
                                                                              │
omawsl install editor ...: merge picked into OMAWSL_EDITORS → (per newly-picked) print notice ─┤
                                                                              │
                                                                              ▼
                                            every new shell: bashrc unconditionally aliases each
                                            of the 5 tools independently, gated only on `command -v`
```

## Error handling

- A given tool not installed (`command -v` fails) → that tool's alias never set - independent per
  tool.
- A future CLI release renames/removes one of these flags → that tool's alias breaks loudly on
  its very next invocation (unrecognized-flag error from the tool itself). Accepted risk, no
  guard (see "Why").
- A tool's CLI treats these flags as valid only in certain argument positions (e.g. before vs
  after a subcommand like `codex exec` or `opencode run`) → confirmed for Codex specifically
  (`--dangerously-bypass-approvals-and-sandbox` works before the subcommand); the other four are
  assumed to behave the same way (global flags accepted in any position) based on their CLI
  frameworks' conventions, but this is exactly the kind of assumption the implementation plan
  should smoke-test against the actual installed binaries before considering this done.
- Uninstalling one of the five tools → no persisted state to clean up; the alias for that tool
  simply stops applying once `command -v` fails.

## Testing

- `tests/lib_test.bats`: `omawsl_notice_ai_autopilot_if_needed` prints a notice naming the right
  tool when it's newly picked, prints nothing when a label isn't newly picked (already existing,
  or not selected at all), handles multiple newly-picked tools in one call (one line each).
- `tests/first_run_choices_test.bats`: notice fires on first run for each AI CLI label picked;
  drop the old "persists the answer" assertions entirely (nothing is persisted anymore).
- `tests/omawsl_install_command_test.bats`: retrofit path prints the notice once when an AI CLI is
  newly added, doesn't reprint on a later unrelated install.
- `tests/a_shell_test.bats`: rewrite the existing Copilot-only alias tests to cover all five tools
  unconditionally - alias present whenever `command -v <tool>` succeeds, absent when it doesn't;
  drop every case that exercises `OMAWSL_COPILOT_AUTOPILOT`/choice values, since the alias no
  longer depends on any persisted state.
- `tests/uninstall_gh_copilot_test.bats`: drop the "clears the persisted autopilot choice" test -
  that behavior no longer exists.

## Non-scope / explicitly deferred

- Any opt-out mechanism (choices.env key, CLI flag, env var) - explicitly rejected; see "Why".
- `bin/omawsl-sub/doctor.sh` reporting - no state to report; the behavior is unconditional.
- A dedicated `omawsl config` command - out of scope, same as the original Copilot design's own
  non-scope note; would be the natural place for an opt-out if one is ever wanted later.
- A flag-existence guard against future CLI upgrades - explicitly rejected; see "Why".
