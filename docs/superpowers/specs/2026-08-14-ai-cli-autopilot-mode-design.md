# AI CLI autopilot mode — design

**Date:** 2026-08-14
**Status:** approved
**Scope:** generalizes the GitHub Copilot CLI autopilot opt-in
(`docs/superpowers/specs/2026-08-09-copilot-autopilot-mode-design.md`, issue #2) to all five
AI CLI tools offered in the editors/AI-tooling picker - closes issue #25.

## Why

Issue #25 asks that "all tools that we offer in terms of ai cli (codex, claude etc)" start in
auto/autopilot mode. The Copilot-only mechanism already exists and already resolved the same
tension for one tool: a public installer shouldn't silently auto-approve an AI agent's actions
by default (`install/first-run-choices.sh`'s own stated principle), so it stays an explicit
opt-in rather than a hardcoded default - same shape as `OMAWSL_FONT_MODE`. This design applies
that same opt-in shape to the other four AI CLIs (Claude Code CLI, Codex CLI, Antigravity CLI,
opencode) and, rather than bolting on four more tool-specific keys, collapses all five into one
combined choice - the AI CLIs are one category of thing being opted into, not five independent
decisions.

Each tool's actual auto-approve flag, confirmed against its own docs:

| Tool | binary | flag |
|---|---|---|
| Claude Code CLI | `claude` | `--dangerously-skip-permissions` |
| Codex CLI | `codex` | `--dangerously-bypass-approvals-and-sandbox` |
| GitHub Copilot CLI | `copilot` | `--autopilot --allow-all` (unchanged) |
| Antigravity CLI | `agy` | `--dangerously-skip-permissions` |
| opencode | `opencode` | `--auto` |

All five are implemented as a shell alias in `configs/bashrc`, matching the existing Copilot
mechanism exactly - one mechanism for all five tools, rather than mixing in the persistent
settings.json config that Claude Code and Antigravity also happen to support. Aliases only take
effect in interactive bash shells; a script or another tool invoking the binary directly bypasses
them. Accepted trade-off, for consistency with the existing precedent.

## Components

### 1. `install/lib.sh` — `omawsl_prompt_ai_autopilot_if_needed <picked_csv> <existing_csv>`

Replaces `omawsl_prompt_copilot_autopilot_if_needed`. Shared helper, called from both the
fresh-install and retrofit paths below.

- No-ops (returns immediately) unless at least one of the five AI-CLI labels (`Claude Code CLI`,
  `Codex CLI`, `GitHub Copilot CLI`, `Antigravity CLI`, `opencode`) is present in `picked_csv`
  but absent from `existing_csv` (i.e. newly selected this run) **and** `OMAWSL_AI_AUTOPILOT` has
  no persisted value yet (`omawsl_load_choice` returns empty). Fires exactly once per machine:
  not on an unrelated `omawsl install` run, and not a second time once already answered -
  regardless of which of the five tools triggered it or how many more are added later.
- Otherwise prompts via a direct `gum choose` call (same primitive `OMAWSL_FONT_MODE` and the old
  Copilot-only prompt use):
  > "AI CLI tools (Claude Code CLI, Codex CLI, GitHub Copilot CLI, Antigravity CLI, opencode):
  > always start them in autopilot mode (auto-approves all tool use, no confirmation)?"
  > - "No - interactive by default (recommended)"
  > - "Yes - autopilot for all AI CLI tools"
- Saves the picked label via `omawsl_save_choice OMAWSL_AI_AUTOPILOT "<label>"`.
- A cancelled or failed prompt (Esc, Ctrl-C, `gum` missing) is treated as not-yet-answered -
  nothing is persisted, the prompt fires again next time, same as the Copilot-only version did.

### 2. `install/first-run-choices.sh` — fresh-install call site

Immediately after `OMAWSL_EDITORS` is picked, calls
`omawsl_prompt_ai_autopilot_if_needed "$OMAWSL_EDITORS" ""` (empty existing-list, first run).
Same call site as before, renamed function.

### 3. `bin/omawsl-sub/install.sh` — retrofit call site

`omawsl_install_apply_editor` calls `omawsl_prompt_ai_autopilot_if_needed "$picked" "$existing"`
right after merging and saving `OMAWSL_EDITORS`, before the per-tool install loop. Covers a user
who installs any of the five AI CLIs after their initial setup - including installing a second
or third one after already answering for the first.

### 4. `configs/bashrc` — the five aliases

One raw grep/cut read of `choices.env`'s `OMAWSL_AI_AUTOPILOT` (bashrc never sources `lib.sh` or
`choices.env` directly, same rationale as every other choice read here), then five
`command -v`-guarded alias blocks, replacing the single Copilot-only block:

```bash
OMAWSL_AI_AUTOPILOT="$(grep -m1 '^OMAWSL_AI_AUTOPILOT=' "${OMAWSL_STATE_DIR:-$HOME/.local/state/omawsl}/choices.env" 2>/dev/null | cut -d'"' -f2)"
if [[ "$OMAWSL_AI_AUTOPILOT" == "Yes"* ]]; then
  command -v claude &>/dev/null && alias claude="claude --dangerously-skip-permissions"
  command -v codex &>/dev/null && alias codex="codex --dangerously-bypass-approvals-and-sandbox"
  command -v copilot &>/dev/null && alias copilot="copilot --autopilot --allow-all"
  command -v agy &>/dev/null && alias agy="agy --dangerously-skip-permissions"
  command -v opencode &>/dev/null && alias opencode="opencode --auto"
fi
unset OMAWSL_AI_AUTOPILOT
```

Placed where the old Copilot-only block was, near the `lzg`/`lzd` tool-conditional aliases. Each
alias independently gated on its own `command -v`, so only the tools actually installed get
aliased - matches the old Copilot behavior (inert if that one tool was never installed),
generalized to five independent guards under one shared choice.

### 5. `uninstall/app-gh-copilot.sh` — drop the old clear-on-uninstall

Removes the `omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT ""` line. `OMAWSL_AI_AUTOPILOT` is a
standing preference over the AI-CLI category as a whole - the same way `OMAWSL_FONT_MODE` and
`OMAWSL_NETWORK_MODE` are never cleared by any single tool's uninstall - so uninstalling Copilot
alone must not erase an answer that still governs the other four tools. The other four uninstall
scripts (`app-claude-cli.sh`, `app-codex-cli.sh`, `app-antigravity-cli.sh`, `app-opencode.sh`)
need no new cleanup code, for the same reason.

### 6. `migrations/1786721313.sh` — carry forward an existing answer

For installs that already answered the old Copilot-only prompt: if `OMAWSL_COPILOT_AUTOPILOT` is
set and `OMAWSL_AI_AUTOPILOT` is not yet set, copies the value across via
`omawsl_save_choice OMAWSL_AI_AUTOPILOT "$old_value"`. Prevents re-prompting someone who already
made this decision. The old `OMAWSL_COPILOT_AUTOPILOT` line is left in `choices.env` untouched -
nothing reads it anymore after this change, and deleting lines from a file isn't otherwise
something this migration needs to do (matches this project's general preference for the smallest
safe mutation, `docs/config-safety.md`).

## Data flow

```
first-run-choices.sh: pick OMAWSL_EDITORS → (if any AI CLI newly picked) prompt → choices.env
                                                                                        │
omawsl install editor ...: merge picked into OMAWSL_EDITORS → (if any newly picked) prompt ─┤
                                                                                        │
migration (existing installs only): OMAWSL_COPILOT_AUTOPILOT → OMAWSL_AI_AUTOPILOT ──────┤
                                                                                        ▼
                                                              every new shell: bashrc reads
                                                              choices.env, conditionally aliases
                                                              each of the 5 tools independently
```

## Error handling

- A given tool not installed (`command -v` fails) → that tool's alias never set, regardless of
  the choice value - independent per tool, same as the old Copilot behavior.
- `OMAWSL_AI_AUTOPILOT` never set (no AI CLI ever selected, or an install that predates this
  migration and also predates the old Copilot feature) → treated as "No", safe-by-default.
- Re-running `omawsl install editor <any AI CLI>` when it's already installed → helper's "newly
  picked" guard means no re-prompt.
- Uninstalling one AI CLI while others remain installed → `OMAWSL_AI_AUTOPILOT` is untouched;
  the remaining tools keep whatever behavior the existing answer implies.
- Uninstalling all five AI CLIs, then later reinstalling one → the old answer still applies
  (no re-prompt), since nothing clears `OMAWSL_AI_AUTOPILOT`. Accepted trade-off, same standing-
  preference model as `OMAWSL_FONT_MODE`.

## Testing

- `tests/lib_test.bats`: `omawsl_prompt_ai_autopilot_if_needed` prompts once when any of the five
  labels is newly picked, doesn't re-prompt once answered, doesn't fire for unrelated picks,
  handles a cancelled prompt cleanly.
- `tests/first_run_choices_test.bats`: prompt fires on first run when an AI CLI is picked,
  persists `OMAWSL_AI_AUTOPILOT`.
- `tests/omawsl_install_command_test.bats`: retrofit path prompts once when an AI CLI is newly
  added, doesn't re-prompt on a later unrelated install.
- `tests/a_shell_test.bats`: extend the existing Copilot alias coverage to all five tools -
  alias present only when both `command -v <tool>` succeeds and `OMAWSL_AI_AUTOPILOT` is "Yes";
  absent for "No", unset, and tool-not-installed cases; each tool's guard is independent of the
  others.
- `tests/uninstall_gh_copilot_test.bats`: drop the "clears the persisted autopilot choice" case -
  uninstalling Copilot must leave `OMAWSL_AI_AUTOPILOT` untouched now.
- `tests/migration_1786721313_test.bats`: copies an existing `OMAWSL_COPILOT_AUTOPILOT` value
  forward when `OMAWSL_AI_AUTOPILOT` is unset; no-ops when `OMAWSL_AI_AUTOPILOT` is already set
  or `OMAWSL_COPILOT_AUTOPILOT` was never set.

## Non-scope / explicitly deferred

- `bin/omawsl-sub/doctor.sh` reporting: no pending/stale state to detect - the choice is either
  made or it isn't, same as the original Copilot design's own non-scope note.
- A dedicated `omawsl config` command to change an already-made choice: out of scope, same as
  before - today that means editing `choices.env` by hand.
- Per-tool granularity (auto mode for Claude but not Codex): explicitly rejected in favor of one
  combined choice - see "Why" above.
- Persistent settings.json config for Claude Code / Antigravity as an alternative to the bashrc
  alias: explicitly rejected in favor of one consistent mechanism for all five tools.
