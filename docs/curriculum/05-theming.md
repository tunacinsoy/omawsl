# Lesson 5: Theming

## 1. Concept

By Phase 4, omawsl can install a whole dev environment: shell tools, Docker,
language runtimes, editors, AI CLIs. But everything it installs looks like
whatever default colors each tool shipped with — Neovim's default colorscheme,
zellij's default gray, VS Code's default dark-plus theme, Windows Terminal's
default Campbell scheme. None of it matches.

Omakub (the native-Linux project omawsl is a WSL2 port of) solves this with a
`theme` command backed by a `themes/<name>/` folder per theme, each folder
holding one file per tool that theme touches. This phase ports that idea, plus
ten real themes (catppuccin, everforest, gruvbox, kanagawa, matte-black, nord,
osaka-jade, ristretto, rose-pine, tokyo-night) with their real hex color
values, verbatim from Omakub's upstream source.

The hard part isn't picking colors. It's that every tool being themed reads
its config in a *different file format*, and each format calls for a
different editing strategy:

- Neovim reads Lua. Its "theme" is a plugin config file that names a
  colorscheme plugin — Neovim isn't told colors directly, it's told which
  plugin to load.
- zellij and btop each read one *active* config file that names the theme by
  a short string (`theme "tokyo-night"`, `color_theme = "Default"`), plus a
  separate per-theme file holding the actual palette. Applying a theme means
  two things: drop the palette file where the tool expects it, then rewrite
  one line of the main config to point at it.
- VS Code/Cursor read JSON settings and expect a `workbench.colorTheme` key
  naming an installed extension's theme.
- Windows Terminal reads its own JSON `settings.json`, with a `schemes` array
  of full color palettes and a `colorScheme` key naming which one is active.

Five formats, but the same underlying operation every time: *drop the
palette, then point the active config at it.* The bulk of this phase is
disciplined, repetitive data-porting work — five files per theme, ten
themes — following one documented mapping so all fifty files stay
consistent. The interesting design work is the `apply` command that walks
across every one of those formats with the correct edit strategy for each,
and one narrow, deliberate exception this project otherwise refuses to make:
touching a file that lives on the Windows side of the WSL2 boundary.

**Why touch a file that plain-text-editing tools shouldn't touch.** Windows
Terminal's `settings.json` has a `schemes` array — a *list* of theme objects,
not a single line. You cannot correctly append-or-replace an entry in a JSON
array with `sed`, a tool built for line-based text substitution with no
concept of "this text is a nested list of objects." `sed` doesn't parse
anything; it just matches patterns of characters and swaps them, one line at
a time. Get the pattern even slightly wrong against nested `{`/`[` and
`sed` will happily produce broken JSON, because it has no idea JSON syntax
exists at all.

The tool actually built for this is `jq` — a command-line program purpose-
built to read, filter, and rewrite JSON. Where `sed` works one text line at
a time, `jq` works on the JSON document as a whole: it parses the file into
its real tree of objects and arrays first, lets you write a short filter
expression that says what to keep, replace, or add, and prints back
guaranteed-well-formed JSON. That's the tool this phase reaches for anywhere
it edits a `.json` file — VS Code/Cursor's settings and, new this phase,
Windows Terminal's.

Every other phase in this project holds a hard line: omawsl never silently
edits a file on the Windows side of the WSL2 boundary — the whole design
philosophy is "we own the Linux side, we don't touch what we don't own."
Windows Terminal's `settings.json` is the *one* deliberate exception, and
it's narrow on purpose: it's a local file belonging to an app the user
already installed themselves, edited with no network call and no elevated
permissions, and — the important part — the edit code is written to never be
the thing that breaks the user's terminal. It backs the file up before
touching it, and if anything about the file looks wrong (missing, or not
valid JSON), it skips the edit and prints where to do it by hand instead of
crashing or half-writing a corrupted file. That "skip gracefully, never
abort" discipline is the actual lesson of this exception — it's what makes
touching a file you don't fully control defensible at all.

## 2. Walkthrough

### One theme, five formats

Here is `themes/catppuccin/`, one theme's worth of files (colors trimmed
for brevity where noted — the real files carry the theme's full palette).

`themes/catppuccin/neovim.lua` — a Lua *table*. Lua is the small scripting
language Neovim configs are written in; `return { ... }` hands back a table
(Lua's one combined array/dictionary type) that LazyVim's plugin loader reads
as declarative config — "load this plugin, with these options":

```lua
return {
	{
		"LazyVim/LazyVim",
		opts = {
			colorscheme = "catppuccin",
		},
	},
}
```

Notice this file doesn't contain a single hex color. Theming Neovim means
naming a *colorscheme plugin* someone else already wrote — the plugin itself
owns every actual color.

`themes/catppuccin/zellij.kdl` — KDL, a newer, human-readable config
language some tools (zellij among them) use instead of JSON or YAML. It reads
like nested named blocks with plain arguments:

```kdl
themes {
  catppuccin-macchiato {
    bg "#5b6078" // Surface2
    fg "#cad3f5"
    red "#ed8796"
    green "#a6da95"
    ...
  }
}
```

`themes/catppuccin/btop.theme` — an ini-like format specific to btop: one
`theme[key]="value"` assignment per line, comment lines starting with `#`.
No nesting, no arrays — just flat key/value pairs, which is exactly why
`sed` is a fine tool for editing btop's *reference* to a theme file (a
single line, `color_theme = "..."`), even though it wouldn't be for
Windows Terminal's nested JSON:

```
theme[main_bg]="#24273a"
theme[main_fg]="#c6d0f5"
theme[hi_fg]="#8caaee"
```

`themes/catppuccin/vscode.sh` — not data at all, a small shell script:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../set-vscode-theme.sh
source "$SCRIPT_DIR/../set-vscode-theme.sh"

omawsl_theme_apply_vscode "Catppuccin Macchiato" "Catppuccin.catppuccin-vsc"
```

`themes/catppuccin/windows-terminal-scheme.json` — plain JSON, Windows
Terminal's own native color-scheme shape (a `name` plus 20 named hex color
slots):

```json
{
    "name": "Catppuccin",
    "background": "#24273a",
    "foreground": "#cad3f5",
    "cursorColor": "#f4dbd6",
    "selectionBackground": "#f4dbd6",
    "black": "#494d64",
    "red": "#ed8796",
    ...
}
```

That JSON file wasn't in Omakub's upstream source at all — Omakub themes
Alacritty (a Linux terminal emulator) instead, which has no place on a
Windows host. omawsl's design spec has this file *hand-derived* from each
theme's Alacritty color values, following one documented, fixed mapping
(Alacritty's `[colors.primary]` → `background`/`foreground`, `[colors.normal]`
→ the eight base color slots, `[colors.bright]` → the eight `bright*` slots,
and so on) — the same colors, reshaped into the format the new consumer
actually needs.

### Why VS Code's helper takes arguments, not globals

Omakub's own `vscode.sh` helper is written to be `source`d after the caller
sets two *global* shell variables (`VSC_THEME`, `VSC_EXTENSION`) — a common
enough shell pattern, but a fragile one. `docs/superpowers/plans/2026-07-06-omawsl-phase1-core-skeleton.md`
(this project's own Phase 1 retrospective) records a real bug caused by
exactly this pattern: two sourced scripts silently colliding on the same
global variable name. This phase's own retrospective explicitly avoids
repeating it — `themes/set-vscode-theme.sh` takes its inputs as **function
arguments** instead:

```bash
# themes/set-vscode-theme.sh
omawsl_theme_set_vscode_settings() {
  local settings_file="$1" color_theme="$2"
  [[ -f "$settings_file" ]] || return 0
  command -v jq &>/dev/null || return 0
  local tmp
  tmp="$(mktemp)"
  jq --arg theme "$color_theme" '.["workbench.colorTheme"] = $theme' "$settings_file" > "$tmp"
  mv "$tmp" "$settings_file"
}

omawsl_theme_apply_vscode() {
  local color_theme="$1" extension_id="$2"

  omawsl_theme_set_vscode_settings "$HOME/.vscode-server/data/Machine/settings.json" "$color_theme"
  omawsl_theme_set_vscode_settings "$HOME/.cursor-server/data/Machine/settings.json" "$color_theme"

  if omawsl_code_reachable; then
    code --install-extension "$extension_id" >/dev/null
  fi
}
```

A few things worth naming explicitly for anyone new to `jq`:

- `jq --arg theme "$color_theme" '...'` binds the shell variable
  `$color_theme` (a plain string) to a `jq`-side variable named `$theme`,
  safely — no manual quoting/escaping needed even if the theme name has
  spaces or punctuation in it (and several do: `"Ocean Green: Dark"` is a
  real value elsewhere in this project). This is the same category of
  problem `sed` handles badly — a theme name containing a `/` would break a
  `sed` script using `/` as its delimiter; `jq`'s `--arg` sidesteps that
  entirely by never treating the string as part of the filter's syntax.
- `.["workbench.colorTheme"] = $theme` is the `jq` *filter*: starting from
  the whole JSON document (`.`), set the value at that one key to `$theme`,
  leaving every other key in the document untouched.
- The result is written to a **temp file first** (`tmp="$(mktemp)"`), then
  `mv`'d over the real file. This is deliberate, not incidental. If the
  process died mid-write while writing directly into the real settings
  file, VS Code would be left with a half-written, corrupted config. `mv`
  (a rename, on the same filesystem) is effectively instantaneous once the
  temp file is fully written — there's no "half-renamed" state to land in.
  You'll see this same write-to-temp-then-move shape everywhere in this
  phase that touches a file that matters.
- Both functions no-op — return success, not an error — when the settings
  file doesn't exist yet, or when `jq` itself isn't installed. This is the
  "detect-and-defer" pattern from earlier phases again: VS Code's settings
  file only exists if Phase 4's picker installed VS Code in the first
  place, so a no-op here isn't a bug, it's the correct behavior for "this
  component wasn't chosen."

### `bin/omawsl-sub/theme.sh` — one `apply`, five formats, one dispatch

```bash
# bin/omawsl-sub/theme.sh
omawsl_theme_apply() {
  local name="$1"
  local theme_dir="$OMAWSL_ROOT_DIR/themes/$name"

  if ! omawsl_theme_is_valid "$name"; then
    echo "omawsl: unknown theme '$name'" >&2
    echo "Valid themes: $(omawsl_theme_names | tr '\n' ' ')" >&2
    return 1
  fi

  mkdir -p "$HOME/.config/zellij/themes"
  cp "$theme_dir/zellij.kdl" "$HOME/.config/zellij/themes/$name.kdl"
  if [[ -f "$HOME/.config/zellij/config.kdl" ]]; then
    sed -i "s/theme \".*\"/theme \"$name\"/g" "$HOME/.config/zellij/config.kdl"
  fi

  if [[ -f "$HOME/.config/btop/btop.conf" ]]; then
    mkdir -p "$HOME/.config/btop/themes"
    cp "$theme_dir/btop.theme" "$HOME/.config/btop/themes/$name.theme"
    sed -i "s/color_theme = \".*\"/color_theme = \"$name\"/g" "$HOME/.config/btop/btop.conf"
  fi

  if [[ -d "$HOME/.config/nvim" ]]; then
    mkdir -p "$HOME/.config/nvim/lua/plugins"
    cp "$theme_dir/neovim.lua" "$HOME/.config/nvim/lua/plugins/theme.lua"
  fi

  # shellcheck source=/dev/null
  source "$theme_dir/vscode.sh"

  omawsl_theme_apply_opencode "$name"

  omawsl_theme_apply_windows_terminal "$theme_dir/windows-terminal-scheme.json"
}
```

Six blocks, six different guard conditions, worth reading one at a time:

- **zellij**: `mkdir -p` + `cp` always run — the per-theme palette file is
  copied unconditionally. Only the *active* config edit is guarded on
  `[[ -f "$HOME/.config/zellij/config.kdl" ]]` — if zellij was never
  installed, there's nothing to patch, and patching a file that doesn't
  exist would be the wrong operation, not a missing one. The `sed`
  itself — `s/theme ".*"/theme "$name"/g` — is safe here specifically
  *because* it's one line in a flat file: find the line matching
  `theme "..."` (any quoted content), replace the quoted part with the new
  theme name. This is exactly the shape `sed` is good at, and exactly why
  Windows Terminal's nested array below needs `jq` instead.
- **btop**: the *entire* block — palette copy and the `sed` patch both — is
  gated on `btop.conf` already existing. Unlike zellij, there's no
  unconditional half: if btop wasn't installed, this phase does nothing to
  it at all.
- **Neovim**: gated on the *directory* `~/.config/nvim` existing (Phase 4's
  `app-neovim.sh` only creates it when Neovim was actually selected).
- **VS Code/Cursor**: `source "$theme_dir/vscode.sh"` — `source` runs that
  theme's tiny script *inline*, in the current shell, meaning it can call
  `omawsl_theme_apply_vscode` because that function was already loaded by
  `themes/set-vscode-theme.sh` earlier. Each theme's own `vscode.sh` is
  effectively a one-line plugin: "this is my display name, this is my
  extension ID," and the shared helper does the actual work.
- **opencode**: `omawsl_theme_apply_opencode` (below) — the one component
  with no Omakub upstream precedent at all, added because research
  confirmed opencode (an AI coding CLI this project also installs) really
  does read a `"theme"` key from its own `~/.config/opencode/tui.json`.
- **Windows Terminal**: the new mechanism, covered next.

```bash
omawsl_theme_apply_opencode() {
  local name="$1"
  command -v opencode &>/dev/null || return 0
  command -v jq &>/dev/null || return 0

  local preset
  preset="$(omawsl_theme_opencode_preset "$name")" || return 0
  ...
}
```

Only 6 of the 10 omawsl themes have a matching built-in opencode preset
(`omawsl_theme_opencode_preset` is a `case` statement that returns failure
for the other 4). Rather than build a from-scratch custom-theme JSON file
for the remaining 4 — a separate, unverified schema — the design spec
explicitly chooses to skip them: "best-effort... skipped rather than
forcing a workaround." That's a real trade-off, made once and stated
plainly, not an oversight.

### `bin/omawsl-sub/windows-terminal.sh` — the one Windows-side edit

```bash
omawsl_windows_terminal_settings_path() {
  local profile
  profile="$(omawsl_windows_userprofile)" || return 1

  local store_path="$profile/AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json"
  local unpackaged_path="$profile/AppData/Local/Microsoft/Windows Terminal/settings.json"

  if [[ -f "$store_path" ]]; then
    echo "$store_path"
  elif [[ -f "$unpackaged_path" ]]; then
    echo "$unpackaged_path"
  else
    return 1
  fi
}
```

`omawsl_windows_userprofile` (in `install/lib.sh`) resolves the Windows
user's home directory by asking Windows itself — `cmd.exe /c "echo
%USERPROFILE%"` — then converts that Windows-style path (`C:\Users\name`) to
the WSL-visible path (`/mnt/c/Users/name`) with `wslpath -u`. WSL2 (Windows
Subsystem for Linux) makes the Windows filesystem reachable from Linux under
`/mnt/c/...`, and makes Windows executables like `cmd.exe` callable directly
from a Linux shell — this is that interop being used on purpose, once,
narrowly. It resolves the profile *dynamically* rather than assuming the
Windows username matches the WSL username — a real, common mismatch (e.g.
`tcinsoy` on Windows, `tuna` in WSL) that a hardcoded path would get wrong
silently.

```bash
omawsl_theme_apply_windows_terminal() {
  local scheme_file="$1"

  if ! command -v jq &>/dev/null; then
    echo "omawsl: 'jq' isn't available - skipping the Windows Terminal color sync."
    echo "See docs/windows-setup.md#windows-terminal-theme for the manual steps."
    return 0
  fi

  local settings_file
  if ! settings_file="$(omawsl_windows_terminal_settings_path)"; then
    echo "omawsl: couldn't find Windows Terminal's settings.json - skipping the Windows Terminal color sync."
    echo "See docs/windows-setup.md#windows-terminal-theme for the manual steps."
    return 0
  fi

  if ! jq empty "$settings_file" 2>/dev/null; then
    echo "omawsl: Windows Terminal's settings.json isn't valid JSON - skipping the Windows Terminal color sync."
    echo "See docs/windows-setup.md#windows-terminal-theme for the manual steps."
    return 0
  fi

  cp "$settings_file" "$settings_file.bak"

  local tmp
  tmp="$(mktemp)"
  jq --argjson scheme "$(cat "$scheme_file")" \
    '.schemes = ((.schemes // []) | map(select(.name != $scheme.name))) + [$scheme]
     | .profiles.defaults.colorScheme = $scheme.name' \
    "$settings_file" > "$tmp"

  if ! jq empty "$tmp" 2>/dev/null; then
    echo "omawsl: the Windows Terminal settings edit produced invalid JSON - leaving settings.json untouched (backup at $settings_file.bak)." >&2
    rm -f "$tmp"
    return 1
  fi

  mv "$tmp" "$settings_file"
}
```

Read this one closely — it's the phase's centerpiece.

- **Three guard clauses in a row, each returning 0 (success), each with a
  pointer to `docs/windows-setup.md` for doing it by hand.** No `jq`? Skip.
  Can't find `settings.json`? Skip. Found it, but it doesn't parse as
  JSON? Skip. None of these abort `bin/omawsl theme` — the rest of the
  theme (zellij, btop, Neovim, VS Code, opencode) still applies normally.
  That third guard — `jq empty "$settings_file"` (an idiom meaning "parse
  this and check it's valid JSON, discard the result, just tell me if it
  parsed") — didn't ship in the first version of this file. It was added
  one commit later (`e1c8722`), after noticing the first version only
  guarded against the file being *missing*, not against it existing but
  being broken — a real gap in the first attempt, closed before merge. The
  lesson generalizes: "never touch a file you don't own" isn't satisfied
  by writing to it carefully once; it means handling every way that file
  might already be in a state you didn't expect, every time.
- **`cp ... .bak` before any edit, unconditionally.** Whatever happens
  next, there is a copy of the working file already sitting on disk.
- **`--argjson` instead of `--arg`.** `--arg` (used in the VS Code helper
  above) binds a plain *string*. `--argjson scheme "$(cat "$scheme_file")"`
  parses the shell string as *JSON* and binds the result as a `jq`-side
  value — here, a whole object (`{"name": "Catppuccin", "background": ...}`),
  not a string containing JSON-looking text. That distinction matters:
  without `--argjson`, `$scheme.name` inside the filter wouldn't work at
  all, because `$scheme` would just be one long string.
- **The merge filter, piece by piece:**
  `.schemes = ((.schemes // []) | map(select(.name != $scheme.name))) + [$scheme]`
  — `.schemes // []` means "the existing `schemes` array, or an empty array
  if the key is missing entirely" (`//` is `jq`'s "use this default if the
  left side is null/missing" operator). `map(select(.name != $scheme.name))`
  filters that array down to every entry *except* one with the same name as
  the theme being applied — removing any previous version of this exact
  theme so re-applying it doesn't leave duplicates. `+ [$scheme]` appends
  the new scheme object. The second filter clause,
  `.profiles.defaults.colorScheme = $scheme.name`, then points Windows
  Terminal's default profile at that scheme by name.
- **Re-validated before it's trusted**: the `jq` output is written to a
  temp file, then checked with `jq empty` a *second* time before being
  `mv`'d over the real file. If somehow the transformation itself produced
  broken output, the function fails loudly (`return 1`) rather than commit
  a corrupted `settings.json` — but note even this failure path leaves the
  original file's `.bak` copy intact and the *original* `settings_file`
  untouched (the broken result only ever lived in `$tmp`, never `mv`'d
  over anything).
- **Targets `profiles.defaults.colorScheme`**, not a specific named
  profile. Windows Terminal falls back to the `defaults` profile settings
  for anything a specific profile doesn't override, so this affects every
  profile a user has, without the more fragile work of finding "the" WSL
  profile by name or GUID (which varies by how Windows Terminal was set
  up).

### The dispatcher

`bin/omawsl` is new this phase — the project's first real CLI entry point,
`bin/omawsl <command> [args]`. `theme` is the only subcommand wired in yet
(Phase 7 adds the rest — `update`, `migrate`, `install`, `uninstall`,
`doctor`), but the shape is built to take them: one `source` line per
`bin/omawsl-sub/<command>.sh`, and a `case` statement in `omawsl_main` that
shifts off the command name and calls into that file's own entry function:

```bash
omawsl_main() {
  local cmd="${1:-}"
  case "$cmd" in
    theme)
      shift
      omawsl_theme_command "$@"
      ;;
    ...
  esac
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_main "$@"
fi
```

`omawsl_theme_command` (in `bin/omawsl-sub/theme.sh`) is what `theme`
dispatches to — with no name given it prompts interactively via `gum choose`
using Title Case labels ("Rose Pine"), then round-trips that back to the
folder-name form ("rose-pine") `omawsl_theme_apply` expects:

```bash
omawsl_theme_display_name() {
  echo "$1" | sed -E 's/(^|-)([a-z])/\1\U\2/g; s/-/ /g'
}

omawsl_theme_folder_name() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | tr ' ' '-'
}
```

Both directions exist because the picker shows the pretty form but the
folder names on disk use the plain form — and a user typing
`omawsl theme "Rose Pine"` or `omawsl theme rose-pine` on the command line
should both work, so `omawsl_theme_command` normalizes either input through
`omawsl_theme_folder_name` before ever calling `omawsl_theme_apply`.

## 3. Exercise

Close this lesson and rebuild a scoped-down version of this phase's core
mechanism, blind, in `practice/05-theming/`.

Two tiny sample themes are already provided for you at
`practice/05-theming/themes/aurora/` and `practice/05-theming/themes/dusk/`,
each with three files: `zellij.kdl`, `btop.theme`, and
`windows-terminal-scheme.json` (with a `"name"` field — `"Aurora"` /
`"Dusk"` — and a handful of color keys). You don't need to invent theme
data; treat these as the `themes/<name>/` folders from the walkthrough,
just smaller.

Write `practice/05-theming/theme.sh` implementing a function
`apply_theme <name>`, wired up so the script also works as a CLI:

```
bash theme.sh apply <name>
```

(a `case` on `$1` at the bottom of the file, guarded the same way you've
seen in this project's own `bin/omawsl`, dispatching `apply` to
`apply_theme "$@"` with the subcommand name shifted off first).

`apply_theme <name>` should:

1. **Validate.** If `themes/<name>/` (resolved relative to `theme.sh`'s own
   location, not the caller's current directory) doesn't exist, print an
   error to stderr and return non-zero. Do nothing else.
2. **zellij, unconditionally.** Copy `themes/<name>/zellij.kdl` to
   `$HOME/.config/zellij/themes/<name>.kdl`, creating directories as
   needed. Then, *only if* `$HOME/.config/zellij/config.kdl` already
   exists, rewrite its `theme "..."` line so the quoted part reads
   `<name>`. If `config.kdl` doesn't exist yet, don't create it — just skip
   that step.
3. **btop, fully gated.** *Only if* `$HOME/.config/btop/btop.conf` already
   exists: copy `themes/<name>/btop.theme` to
   `$HOME/.config/btop/themes/<name>.theme`, and rewrite `btop.conf`'s
   `color_theme = "..."` line so the quoted part reads `<name>`. If
   `btop.conf` doesn't exist, do nothing at all for btop — don't even
   create the `themes/` directory.
4. **A Windows-Terminal-style settings merge**, targeting
   `$HOME/.config/windows-terminal-settings.json` as a stand-in for the
   real Windows path (the real project resolves that path by shelling out
   to `cmd.exe`/`wslpath`, which isn't available in this practice
   sandbox — assume it's already been resolved to this fixed location).
   Using `themes/<name>/windows-terminal-scheme.json` as the scheme to
   merge in:
   - If `jq` isn't installed, print a message and return success (0) —
     don't touch anything.
   - If the target file doesn't exist yet, print a message and return
     success — don't create it.
   - If the target file exists but isn't valid JSON, print a message and
     return success, and leave it completely untouched (no backup, no
     edit).
   - Otherwise: back up the target to `<target>.bak` first, then merge the
     scheme into a top-level `.schemes` array — replacing any existing
     entry whose `"name"` matches this scheme's `"name"`, appending
     otherwise — and set `.profiles.defaults.colorScheme` to the scheme's
     `"name"`. Write safely (temp file, then move into place), never
     editing the real file directly.

Everything `apply_theme` writes should be scoped under `$HOME` — no other
component (Neovim, VS Code, opencode) is in scope for this exercise; the
walkthrough already covered how those extend the same pattern.

## 4. Check

Run:

```bash
bash practice/05-theming/check.sh
```

The check never touches your real home directory or a real Windows Terminal
settings file — it runs your `theme.sh` with `$HOME` (and the working
directory) redirected to a throwaway scratch folder for every single
invocation, so it's safe to run as many times as you like.

Read a failure by which *behavior* it names, not by comparing code:

- A failure naming the zellij palette file or `config.kdl` patch means the
  unconditional-copy-but-gated-patch logic in step 2 isn't matching — check
  which half is misbehaving (the copy that should always happen, or the
  `sed` that should only happen when `config.kdl` already exists).
- A failure naming btop and mentioning a directory or file that "shouldn't
  exist" means step 3's *full* gate isn't being honored — remember, unlike
  zellij, nothing about btop should happen at all when `btop.conf` is
  absent.
- A failure naming the Windows Terminal stand-in file and mentioning
  "malformed" or "invalid JSON" is checking the one behavior this whole
  phase's design turns on: that a bad file gets skipped, not aborted on,
  and left byte-for-byte untouched.
- A failure mentioning `.bak` means a backup wasn't made before a real edit
  happened, or was made when it shouldn't have been (e.g., before the
  invalid-JSON check ran).
- If `jq` isn't installed on the machine running the check, every
  Windows-Terminal-merge assertion prints `SKIP:` instead of `PASS:`/`FAIL:`
  — that's expected, not a problem with your solution.

A passing check means your `apply_theme` is behaviorally correct, even if it
looks nothing like the walkthrough's version — different variable names,
different control flow, `awk` instead of `sed`, whatever you reached for.
Once it passes, you can `diff` your `practice/05-theming/theme.sh` against
`bin/omawsl-sub/theme.sh` and `bin/omawsl-sub/windows-terminal.sh` in the
real repo purely to compare style — never as part of the grade.
