# Lesson 11: Native VS Code/Cursor Theme Sync

## 1. Concept

Phase 5 already broke omawsl's own rule once. The whole project is a WSL2
installer — everything it touches normally lives inside the Linux
filesystem, under `$HOME`. But Windows Terminal's `settings.json` doesn't
live there; it lives on the Windows side, at a path like
`/mnt/c/Users/<you>/AppData/.../Windows Terminal/settings.json`. Phase 5
reached across that boundary anyway, because the edit was narrow and safe
enough to justify it: "a local JSON edit to an already-installed app, no
network call, no admin rights." It backed the file up first, used `jq` to
merge in the new color scheme, and skipped gracefully if anything looked
wrong.

This phase reaches across that same boundary a second time, for the same
reason, for a different app. `bin/omawsl theme <name>` already patches
VS Code's and Cursor's *Remote-WSL* settings
(`~/.vscode-server/data/Machine/settings.json`,
`~/.cursor-server/data/Machine/settings.json`) — but that file only
matters when someone connects VS Code *into* this WSL distro remotely.
Most people don't do that for daily use; they just double-click the VS
Code or Cursor icon on their Windows desktop, which reads a completely
different file:
`%APPDATA%\Code\User\settings.json` on the Windows side. omawsl has never
touched that file. This phase teaches it to.

Two things make this edit harder than Windows Terminal's, and both are
the real content of this lesson:

**The file is the user's, not omawsl's.** Every other settings.json
omawsl edits is one *it* deployed in the first place (Phase 4's
`app-vscode.sh` writes the Remote-WSL machine settings ahead of time, so
they're inert placeholders until VS Code connects). The native
`settings.json` is different: it's the user's own, long-lived,
hand-curated file, edited directly through VS Code's Settings UI or by
hand for months or years before omawsl ever runs. People who hand-edit
JSON commonly leave themselves `//` notes:

```jsonc
{
  // bumped this for the new monitor, don't touch
  "editor.fontSize": 14
}
```

This is **JSONC** — "JSON with Comments" — a format VS Code itself
understands and generates for you (open any Settings JSON file and you'll
likely see comments like this already), but which is *not* valid JSON by
the strict specification. A JSON parser has no concept of a comment at
all. Feed a JSONC file to `jq` — the tool omawsl already trusts for the
Windows Terminal merge — and `jq` doesn't skip the comment gracefully; it
throws a parse error and refuses to touch the file. Worse, even a JSON
tool that's more forgiving about *reading* comments would still lose them
on the way back out: parsing builds an in-memory tree of only the real
values (keys, strings, numbers, objects) with nowhere to attach a
comment, so writing that tree back out to disk reproduces the values but
not the comment that used to sit next to them. There is no "put the
comment back" step, because the comment was never part of the tree to
begin with. A tool that naively parses-and-rewrites a hand-edited
settings.json would quietly delete a user's own notes — a real cost, on a
file omawsl doesn't own and can't apologize on behalf of.

**One command failing can't be allowed to take the whole run down with
it.** This phase also installs the theme's VS Code extension into the
*native* Windows-side extension store (a separate `code --install-extension`
call). `code` might not be reachable at all — VS Code might not be
installed on Windows — and every script in this project runs under
`set -euo pipefail` (Phase 1), meaning an unguarded failing command
normally aborts the whole script immediately. If installing one theme's
extension is allowed to do that, it doesn't just skip the extension — it
kills the rest of `bin/omawsl theme` too: the Windows Terminal sync, the
opencode sync, everything that would have run after it. Phase 4 already
taught this lesson once (one unisolated `gh extension install` failure
silently killing the rest of an install run); this phase applies the same
principle to a different command, in a different corner of the codebase.

Both problems get solved with the same underlying habit, applied more
rigorously than Phase 5 needed to: **back up before you write.** Before
touching a file you don't fully control, copy it somewhere safe first —
so that if your own edit goes wrong, the original is still recoverable.
Phase 5 already did this for Windows Terminal. This phase goes one step
further: after making the edit, it re-checks its own work (does the
result still parse as valid JSON?) and rolls back to the backup if the
edit it just made turned out to be broken, rather than trusting that a
successful `sed`/`awk` run necessarily produced something safe to keep.

## 2. Walkthrough

All code below is from `themes/set-vscode-theme.sh` and `install/lib.sh`
as of commit `854fd3f` (the end of this phase's commit range,
`b97280e..854fd3f`).

### Resolving the Windows-side path (already built, in Phase 5)

```bash
# install/lib.sh
omawsl_windows_userprofile() {
  command -v cmd.exe &>/dev/null || return 1
  command -v wslpath &>/dev/null || return 1
  local win_path
  win_path="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r\n')"
  [[ -n "$win_path" ]] || return 1
  wslpath -u "$win_path"
}
```

This phase doesn't need to write this helper — it reuses the one Phase 5
already built for Windows Terminal. `cmd.exe /c "echo %USERPROFILE%"`
asks *Windows itself* (not WSL) for the logged-in user's profile
directory, because the WSL username and the Windows username are
frequently different, so guessing from `$USER` would be wrong. `wslpath
-u` converts the Windows-style path (`C:\Users\alex`) it gets back into a
WSL-style one (`/mnt/c/Users/alex`) that bash can actually use. Both
external commands are checked with `command -v` first and the function
returns 1 (failure, no output) if either is missing — which happens in
the bats test suite unless a test stubs them, and would also happen on
non-WSL2 Linux. Every caller downstream treats that failure as "skip the
native sync, don't error."

### The comment-stripper

```bash
omawsl_strip_jsonc_comments() {
  sed -E 's#/\*.*\*/##g; s#(^|[^:])//.*$#\1#' "$1"
}
```

Two `sed` substitutions, chained with `;`:

- `s#/\*.*\*/##g` — strip single-line `/* ... */` block comments (`.*`
  is greedy but this only handles comments that open and close on the
  same line; the doc comment above the real function calls out
  multi-line block comments as a known, accepted gap).
- `s#(^|[^:])//.*$#\1#` — strip a `//` line comment and everything after
  it, *unless* the `//` is immediately preceded by `:`. That exception
  matters: `"docsUrl": "http://example.com"` contains a `//` that is
  part of a string value, not a comment, and this pattern preserves it
  by capturing whatever came right before the `//` (either the start of
  the line, `^`, or some non-`:` character) into group 1 and putting
  just that back, dropping only the comment itself.

Notice the delimiter: `sed -E 's#pattern#replacement#'` uses `#` instead
of the usual `/`. That's not a style choice — the pattern itself needs to
contain literal `/` characters (`/\*`, `//`), and `sed` lets you pick any
character as the delimiter precisely so you don't have to backslash-escape
every one of those. Using `/` here would mean writing `s/\/\*.*\*\///g`,
which is correct but far harder to read; swapping the delimiter to `#` (a
character that doesn't otherwise appear in the pattern) sidesteps that
entirely. This is ordinary, idiomatic `sed`, and worth recognizing on
sight in other scripts.

Critically, **this function's output is only ever used to check whether
something still parses as JSON — it's never written back to any real
file.** The doc comment above it in the real code spells this out:
"the result is never written back to any real file, so hand-written
comments in the actual settings.json are never touched or lost." This is
the core trick of the whole phase: comments survive not because anything
clever reconstructs them, but because the code that actually edits the
file never runs its output through the stripper at all.

### The merge function: two paths

```bash
omawsl_theme_set_vscode_settings() {
  local settings_file="$1" color_theme="$2"
  [[ -f "$settings_file" ]] || return 0
  command -v jq &>/dev/null || return 0

  cp "$settings_file" "$settings_file.bak" || {
    echo "omawsl: couldn't back up $settings_file - skipping the color sync." >&2
    echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
    return 0
  }

  # Fast path: strict JSON, no comments - merge directly with jq.
  if jq empty "$settings_file" 2>/dev/null; then
    local tmp
    tmp="$(mktemp)"
    jq --arg theme "$color_theme" '.["workbench.colorTheme"] = $theme' "$settings_file" > "$tmp"
    cp "$tmp" "$settings_file" || { ...; return 0; }
    rm -f "$tmp"
    return 0
  fi
  # ...JSONC fallback below...
```

Every real omawsl-deployed Remote-WSL settings file, and plenty of native
ones, are strict JSON with no comments — for those, `jq empty
"$settings_file"` (a no-op jq filter that only checks "does this parse")
succeeds, and the merge is exactly what Phase 5's Windows Terminal sync
already does: `jq --arg theme "$color_theme" '.["workbench.colorTheme"]
= $theme'`. `--arg` hands the value to `jq` as a bound variable rather
than string-interpolating it into the filter text, so *any* theme name —
quotes, backslashes, anything — is handled safely with zero escaping
concerns. This is the easy 90% case, unchanged from before this phase.

The interesting new code is the fallback, for when `jq empty` fails
(comments, most likely):

```bash
  local stripped
  stripped="$(mktemp)"
  omawsl_strip_jsonc_comments "$settings_file" > "$stripped"

  if ! jq empty "$stripped" 2>/dev/null; then
    echo "omawsl: $settings_file isn't valid JSON - skipping the color sync." >&2
    echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
    rm -f "$stripped"
    return 0
  fi
```

Strip the comments into a *throwaway scratch copy* (`$stripped`, a
`mktemp` file) purely to answer two questions: is the file otherwise
structurally valid JSON at all, and does it already have a
`workbench.colorTheme` key? If stripping the comments still doesn't leave
valid JSON, this is something genuinely broken (or a comment style the
stripper can't handle), and the function skips gracefully rather than
guessing — same "skip, don't corrupt" contract as Phase 5's own
"malformed JSON is skipped, not aborted on."

```bash
  local tmp_edited
  tmp_edited="$(mktemp)"
  if jq -e 'has("workbench.colorTheme")' "$stripped" >/dev/null; then
    local line_no old_line new_line
    line_no="$(grep -n '"workbench\.colorTheme"' "$settings_file" | head -1 | cut -d: -f1)"
    old_line="$(sed -n "${line_no}p" "$settings_file")"
    if [[ "$old_line" =~ ^(.*\"workbench\.colorTheme\"[[:space:]]*:[[:space:]]*)\"[^\"]*\"(.*)$ ]]; then
      printf -v new_line '%s"%s"%s' "${BASH_REMATCH[1]}" "$color_theme" "${BASH_REMATCH[2]}"
      awk -v n="$line_no" -v content="$new_line" 'NR==n { print content; next } { print }' "$settings_file" > "$tmp_edited"
    else
      cp "$settings_file" "$tmp_edited"
    fi
  else
    local line_no old_line before after new_content
    line_no="$(grep -n '{' "$settings_file" | head -1 | cut -d: -f1)"
    old_line="$(sed -n "${line_no}p" "$settings_file")"
    before="${old_line%%\{*}"
    after="${old_line#*\{}"
    printf -v new_content '%s{\n  "workbench.colorTheme": "%s",\n%s' "$before" "$color_theme" "$after"
    awk -v n="$line_no" -v content="$new_content" 'NR==n { print content; next } { print }' "$settings_file" > "$tmp_edited"
  fi
```

This edits `$settings_file` — the *original, comment-containing file* —
never `$stripped`. It works on line numbers, found with `grep -n`:

- If the key already exists, find the line it's on, and use a bash
  regex match (`[[ "$old_line" =~ ... ]]`, with the matched groups landing
  in `BASH_REMATCH[1]` and `BASH_REMATCH[2]`) to split that one line into
  "everything up through the opening quote of the value" and "everything
  after the closing quote" — then rebuild the line with the new value
  spliced in between, using `printf -v` (writes into a variable instead
  of printing).
- If the key doesn't exist yet, find the file's first `{` and splice a
  new `"workbench.colorTheme": "...",` line in right after it, the same
  way.

Either way, an `awk` one-liner (`NR==n { print content; next } { print
}`) then reprints the *whole file*, substituting only that one line
number with the rebuilt content and printing every other line completely
unchanged — comments included, because they were never inspected, let
alone modified.

### Why not just interpolate the value into `sed`/`awk` directly?

The first version of this code (commit `b02e93a`) did exactly that —
built a `sed` substitution and an `awk sub()` call with the theme name
spliced straight into the pattern/replacement text, on the reasonable
assumption that theme names looked like `"Tokyo Night"`: letters and
spaces only. That assumption turned out to be wrong. Real theme names in
this project include `"Ocean Green: Dark"` (a colon) and `"Monokai Pro
(Filter Ristretto)"` (parentheses) — still harmless-looking, but both
`sed`'s `s///` and `awk`'s `sub()` treat certain characters in their
*replacement* text specially (`&` means "the whole matched text", `\`
starts an escape), and a `sed` script built with `/` as its delimiter
would break outright if a value ever contained a literal `/`. Under
`set -e`, a broken `sed` script doesn't just fail to substitute — it can
abort the entire `bin/omawsl theme` run.

Commit `fbbed40` fixed this by changing *how* the value gets into the new
line, not by validating or escaping it: locate the line, then rebuild it
with plain bash string concatenation (`printf -v new_line '%s"%s"%s' ...`
above) — bash's own string handling has no comment/regex/replacement
metacharacters to worry about — and hand the finished line to `awk`'s
`print` (never `sub()`/`gsub()`), which has no replacement-text handling
at all; it just prints exactly the bytes it's given. The general lesson:
the moment you interpolate variable data into another tool's own
mini-language — a `sed` pattern, an `awk` replacement, a `printf` format
string — that mini-language's special characters become your bug, not
just a style nitpick. The fix here wasn't "escape the special
characters" (fragile, easy to miss one); it was "stop asking a
metacharacter-sensitive tool to do the substitution at all."

### Re-validating the edit before committing it

```bash
  local recheck
  recheck="$(mktemp)"
  omawsl_strip_jsonc_comments "$tmp_edited" > "$recheck"
  if jq empty "$recheck" 2>/dev/null; then
    cp "$tmp_edited" "$settings_file" || { ...; return 0; }
  else
    echo "omawsl: the color sync edit to $settings_file produced invalid JSON - leaving it untouched (backup at $settings_file.bak)." >&2
    echo "See docs/windows-setup.md#vscode-theme for the manual steps." >&2
  fi

  rm -f "$stripped" "$tmp_edited" "$recheck"
```

This is the "back up, then double-check your own work" habit taken to
its logical end. The edit above is a best-effort, line-number-based
insertion — the code comments call out a real edge case it can produce
(a literal `{` sitting inside a comment, earlier in the file than the
real opening brace, would fool the "find the first `{`" search). Rather
than trust that the edit succeeded just because the commands that
produced it didn't error, the function strips comments from its *own
output* and checks that it still parses. Only if it does does the edit
get committed (`cp "$tmp_edited" "$settings_file"`, never `mv` — more on
that below); otherwise the original file is left exactly as it was, with
the pre-edit backup still sitting at `$settings_file.bak` as a second
line of defense that was never even needed in that case.

Every `cp`, never an `mv`, when writing back onto a path under
`/mnt/c/...` (Windows' filesystem, mounted via `drvfs`): `mv` across that
boundary isn't a fast metadata-only rename the way it is on a normal
Linux filesystem, and drvfs doesn't support some of the metadata syscalls
a cross-filesystem `mv` falls back to, producing scary-looking (if
harmless) errors. Phase 5's Windows Terminal sync already established
this same rule; this phase just follows it.

### Wiring it up to four targets, and the extension install

```bash
omawsl_theme_apply_vscode() {
  local color_theme="$1" extension_id="$2"

  omawsl_theme_set_vscode_settings "$HOME/.vscode-server/data/Machine/settings.json" "$color_theme"
  omawsl_theme_set_vscode_settings "$HOME/.cursor-server/data/Machine/settings.json" "$color_theme"

  local profile
  if profile="$(omawsl_windows_userprofile)"; then
    omawsl_theme_set_vscode_settings "$profile/AppData/Roaming/Code/User/settings.json" "$color_theme"
    omawsl_theme_set_vscode_settings "$profile/AppData/Roaming/Cursor/User/settings.json" "$color_theme"
  fi

  if omawsl_code_reachable; then
    NODE_NO_WARNINGS=1 code --install-extension "$extension_id" >/dev/null
  fi
}
```

One merge function, called four times — the two pre-existing Remote-WSL
targets, unchanged, plus the two new native ones, gated behind
`omawsl_windows_userprofile` succeeding at all (it returns 1 with no
output outside real WSL2, or if `cmd.exe`/`wslpath` aren't reachable —
the native syncs are silently skipped in that case, but the Remote-WSL
syncs above still run regardless, since they don't depend on it).

The `if omawsl_code_reachable; then ... fi` around the extension install
is this phase's version of "isolate a command that might fail so it
can't take the rest of the run down with it" — it's the same
`command -v code &>/dev/null` reachability gate Phase 4 established, and
it means a machine with no native VS Code at all never even attempts
`code --install-extension`, avoiding the "command not found" failure
that `set -euo pipefail` would otherwise treat as fatal. It's worth
noticing what this gate does *not* yet cover, though: `code` being
reachable on `PATH` doesn't guarantee it actually *runs* successfully —
a broken Remote-WSL interop configuration can make `code
--install-extension` fail even though `command -v code` succeeds, and at
this exact commit, that specific failure is still unguarded and would
abort the run. (A later hardening round, `292cea5`, closes that
remaining gap the same way: wrap the call itself, not just the existence
check. It's outside this phase's commit range, but recognizing the gap
here — "reachable" isn't the same guarantee as "will succeed" — is the
whole point of Phase 4's isolation lesson, and this exercise asks you to
close it fully rather than leave it half-isolated.)

## 3. Exercise

Close this lesson. In `practice/11-native-vscode-cursor-theme-sync/`,
create `theme-sync.sh` from scratch, implementing three functions:

**`strip_jsonc_comments <file>`** — prints a best-effort comment-stripped
copy of `<file>` to stdout. Handle single-line `//` comments (but not
when the `//` is immediately preceded by `:`, so a URL string like
`"http://example.com"` survives) and single-line `/* ... */` block
comments. This output is for structural validation only — it should
never be written back to any real file by any of your other functions.

**`merge_theme_into_settings <settings-file> <theme-key> <theme-value>`**
— edits `<settings-file>` in place, setting `<theme-key>` to
`<theme-value>` as a JSON string value, while:

- No-op'ing (return 0, no changes, no error) if `<settings-file>` doesn't
  exist, or if `jq` isn't on `PATH`.
- Always copying `<settings-file>` to `<settings-file>.bak` before making
  any change.
- Preserving every other key already in the file, and preserving any `//`
  or single-line `/* */` comments already in the file, byte-for-byte,
  whether the key you're setting already exists (replace its value in
  place) or doesn't yet (add it).
- Working correctly on both strict JSON and JSONC input.
- Re-validating its own edit before committing it: if what you're about
  to write back would no longer parse as valid JSON (after stripping
  comments), leave the original file untouched instead — the `.bak` copy
  is your fallback, but the real file itself should never be left
  broken.
- Never interpolating `<theme-value>` directly into a `sed` substitution
  or an `awk` `sub()`/`gsub()` call. Real theme names in this project
  include colons and parentheses (`"Ocean Green: Dark"`, `"Monokai Pro
  (Filter Ristretto)"`) — build the replacement text some other way (bash
  string concatenation is one option) and hand the finished result to a
  plain, metacharacter-blind write instead.

**`install_theme_extension <extension-id>`** — runs `code
--install-extension <extension-id>`, and must never let a failure from
that command escape the function. Whether `code` isn't installed at all,
is on `PATH` but exits non-zero, or succeeds outright, `install_theme_extension`
itself should always return 0 — a missing or broken extension install
must never be able to abort the rest of a theme apply.

A sample hand-edited JSONC settings file, with comments, is provided at
`practice/11-native-vscode-cursor-theme-sync/fixtures/settings.json` if
you want something realistic to test `merge_theme_into_settings` against
by hand before running the check.

## 4. Check

Run:

```bash
practice/11-native-vscode-cursor-theme-sync/check.sh
```

Every assertion prints its own `PASS:`/`FAIL:` line, and the script keeps
going even after a failure, so a single run shows you everything that's
wrong, not just the first thing. The check never touches your real
`$HOME` or any real Windows-side file — it works entirely inside a
scratch directory it creates and deletes itself, and it fakes the `code`
command rather than ever invoking a real one.

If something fails, read the `FAIL:` line for *which behavior* didn't
match — "backup wasn't created with the original value," "comment was
lost," "install_theme_extension returned nonzero when the stubbed `code`
failed" — not which lines of your script differ from the original. A
passing check means your implementation is behaviorally correct even if
your `sed`/`awk`/bash approach looks nothing like the walkthrough above.
Once it passes, you're welcome to `git show 854fd3f:themes/set-vscode-theme.sh`
and compare styles purely out of curiosity — never as the grade.
