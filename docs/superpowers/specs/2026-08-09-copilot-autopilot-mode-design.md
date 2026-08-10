# GitHub Copilot CLI autopilot mode — design

**Date:** 2026-08-09
**Status:** approved
**Scope:** an opt-in choice that, when selected, aliases `copilot` to `copilot --autopilot --allow-all` in `configs/bashrc` — closes issue #2.

## Why

Issue #2 asks for `copilot` to always start in autopilot mode via a hardcoded bashrc alias
(`alias copilot="copilot --autopilot --allow-all"`). `--autopilot` and `--allow-all` (alias
`--yolo`) are real GitHub Copilot CLI flags: autopilot lets it work through a task without
per-step confirmation, and `--allow-all` auto-approves every tool/path/URL use it would
otherwise ask permission for.

Making that the unconditional default for anyone who installs GitHub Copilot CLI conflicts with
this project's own stated principle (`install/first-run-choices.sh`): "Nothing is pre-selected by
default... a public tool should not surprise-install anything the user didn't explicitly ask for."
Auto-approving all of an AI agent's actions is a safety-relevant behavior change, not just a
convenience default, so it's implemented as an explicit opt-in choice instead - same shape as the
existing `OMAWSL_FONT_MODE` single-choice prompt.

## Components

### 1. `install/lib.sh` — `omawsl_prompt_copilot_autopilot_if_needed <picked_csv> <existing_csv>`

Shared helper, called from both the fresh-install and retrofit paths below so the prompt logic
and choice key live in exactly one place.

- No-ops (returns immediately) unless `GitHub Copilot CLI` is in `picked_csv` but *not* in
  `existing_csv` (i.e. newly selected this run) **and** `OMAWSL_COPILOT_AUTOPILOT` has no
  persisted value yet (`omawsl_load_choice` returns empty). This makes it fire exactly once per
  machine: not on unrelated `omawsl install` runs, and not a second time if the user already
  answered.
- Otherwise prompts via a direct `gum choose` call (same underlying primitive `omawsl_prompt_single`/
  `OMAWSL_FONT_MODE` uses - no new UI primitive introduced; called directly rather than through
  `omawsl_prompt_single` itself, since that helper is defined in `install/first-run-choices.sh`,
  which `install/lib.sh` cannot depend on without a circular source):
  > "GitHub Copilot CLI: always start in autopilot mode (auto-approves all tool use, no
  > confirmation)?"
  > - "No - interactive by default (recommended)"
  > - "Yes - autopilot + allow-all"
- Saves the picked label via `omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT "<label>"`.

### 2. `install/first-run-choices.sh` — fresh-install call site

Immediately after `OMAWSL_EDITORS` is picked, calls
`omawsl_prompt_copilot_autopilot_if_needed "$OMAWSL_EDITORS" ""` (empty existing-list, since this
is a first run). Mirrors where `OMAWSL_FONT_MODE` is asked in the same file.

### 3. `bin/omawsl-sub/install.sh` — retrofit call site

`omawsl_install_apply_editor` (used by both `omawsl install editor <item>` and the interactive
`omawsl install` picker) calls `omawsl_prompt_copilot_autopilot_if_needed "$picked" "$existing"`
right after merging and saving `OMAWSL_EDITORS`, before the per-tool install loop. Covers a user
who installs GitHub Copilot CLI after their initial setup.

### 4. `configs/bashrc` — the alias itself

Same raw grep/cut read of `choices.env` `OMAWSL_FONT_MODE` already uses (bashrc never sources
`lib.sh` or `choices.env` directly - `omawsl_load_choice`'s own doc comment explains why: a
persisted value could contain shell metacharacters unsafe to `source`):

```bash
OMAWSL_COPILOT_AUTOPILOT="$(grep -m1 '^OMAWSL_COPILOT_AUTOPILOT=' "${OMAWSL_STATE_DIR:-$HOME/.local/state/omawsl}/choices.env" 2>/dev/null | cut -d'"' -f2)"
if command -v copilot &>/dev/null && [[ "$OMAWSL_COPILOT_AUTOPILOT" == "Yes"* ]]; then
  alias copilot="copilot --autopilot --allow-all"
fi
unset OMAWSL_COPILOT_AUTOPILOT
```

Placed alongside the other tool-conditional aliases (near the `lzg`/`lzd` block). Gated on
`command -v copilot` so it's inert if Copilot CLI was uninstalled after the choice was made.

### 5. `uninstall/app-gh-copilot.sh` — choice cleanup

`omawsl_uninstall_gh_copilot` additionally calls `omawsl_save_choice OMAWSL_COPILOT_AUTOPILOT ""`,
clearing the persisted answer so a later reinstall re-prompts instead of silently inheriting a
stale "Yes".

## Data flow

```
first-run-choices.sh: pick OMAWSL_EDITORS → (if Copilot CLI newly picked) prompt → choices.env
                                                                                        │
omawsl install editor ...: merge picked into OMAWSL_EDITORS → (if newly picked) prompt ─┤
                                                                                        │
uninstall gh-copilot: clear OMAWSL_COPILOT_AUTOPILOT ────────────────────────────────┐ │
                                                                                      ▼ ▼
                                                              every new shell: bashrc reads choices.env,
                                                              conditionally aliases `copilot`
```

## Error handling

- Copilot CLI not installed (`command -v copilot` fails) → alias never set, regardless of choice
  value - matches every other tool-conditional block in `configs/bashrc`.
- `OMAWSL_COPILOT_AUTOPILOT` never set (Copilot CLI never selected, or an install that predates
  this feature) → treated as "No", same safe-by-default behavior as an explicit "No".
- Re-running `omawsl install editor "GitHub Copilot CLI"` when it's already installed → helper's
  "newly picked" guard means no re-prompt, no duplicate `choices.env` line
  (`omawsl_save_choice` is idempotent-by-key regardless, but the guard avoids asking twice).

## Testing

- `tests/first_run_choices_test.bats`: prompt fires when Copilot CLI is picked, doesn't fire when
  it isn't, choice value persisted correctly.
- `tests/omawsl_install_command_test.bats`: retrofit path prompts once when Copilot CLI is newly
  added via `omawsl install editor`, doesn't re-prompt on a subsequent unrelated install/re-run.
- `tests/a_shell_test.bats`: alias present only when both `command -v copilot` succeeds and the
  choice is "Yes"; absent for "No", unset, and copilot-not-installed cases.
- `tests/uninstall_gh_copilot_test.bats`: `OMAWSL_COPILOT_AUTOPILOT` cleared on uninstall.

## Non-scope / explicitly deferred

- `bin/omawsl-sub/doctor.sh` reporting: no pending/stale state to detect here (unlike the docker
  proxy design) - the choice is either made or it isn't, and bashrc already reflects it on every
  new shell. Not added.
- A dedicated `omawsl config` command to change already-made choices without touching an
  editor selection - out of scope; changing the answer today means editing `choices.env` by hand
  or uninstalling/reinstalling Copilot CLI.
