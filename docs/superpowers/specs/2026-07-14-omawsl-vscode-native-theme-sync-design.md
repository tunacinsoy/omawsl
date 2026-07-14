# Sync theme to native Windows-side VS Code/Cursor — design

**Date:** 2026-07-14
**Status:** approved

## Why

`bin/omawsl theme <name>` already patches `workbench.colorTheme` in VS Code's and Cursor's
Remote-WSL/Remote-SSH *machine-scoped* settings.json
(`~/.vscode-server/data/Machine/settings.json`, `~/.cursor-server/data/Machine/settings.json` —
see `themes/set-vscode-theme.sh`). That only takes effect when the editor is connected *into*
this WSL distro remotely. It does nothing for the native Windows-side app itself — the far more
common way people actually run VS Code/Cursor.

The user asked for the native app to theme too, "just like Omakub does" on native Linux,
explicitly accepting the one exception omawsl already carved out for this exact situation: `bin/omawsl theme`
already reaches across `/mnt/c` to edit Windows Terminal's real `settings.json` (design spec
`2026-07-05-omawsl-design.md` §11/§13) — "a local JSON edit to an already-installed app, no
network call, no admin rights," explicitly categorized as different from the general
no-automatic-Windows-side-installs rule. This is the same category of edit, to the same class of
app-owned config file, using the same Windows-profile-resolution helper
(`omawsl_windows_userprofile`, `install/lib.sh`) and the same jq-merge-with-backup safety
pattern (`bin/omawsl-sub/windows-terminal.sh`).

## Scope

Add native-Windows theme sync for VS Code and Cursor, **alongside** (not replacing) the existing
Remote-WSL machine-settings sync. Both keep getting patched; a user who only ever uses Remote-WSL
sessions loses nothing, and a user who runs the app natively on Windows now gets themed too.

Target files, resolved via `omawsl_windows_userprofile`:

- VS Code: `<Windows profile>/AppData/Roaming/Code/User/settings.json`
- Cursor: `<Windows profile>/AppData/Roaming/Cursor/User/settings.json`

Both are **skipped gracefully, never created**, if missing. This differs from the Remote-WSL
machine-settings file, which omawsl proactively deploys itself (so it's "inert until VS Code
connects" — `install/terminal/app-vscode.sh`). A native `settings.json` is the user's own
long-lived, hand-curated file; omawsl only ever edits one that's already there.

No extension-install step is added for either native path: `code --install-extension` (already
invoked when `code` is reachable via Win32 interop) already covers the Windows-side VS Code
binary. Cursor never gets an automatic extension install, per existing precedent (its own
extension marketplace, commonly blocks Microsoft-published extensions) — unchanged.

## The JSONC problem

A hand-edited native `settings.json` commonly contains `//` and `/* */` comments (valid VS
Code JSONC, invalid strict JSON). `jq`, used for the existing Remote-WSL merge, can't parse a
file with comments — it would simply fail on most real native settings files, defeating the
point of the feature.

Rather than adding a full JSONC parser dependency, `themes/set-vscode-theme.sh` gets one merge
function used for **all four** settings-file targets (the 2 existing Remote-WSL files + the 2
new native files), with a two-path strategy:

1. **Fast path** — `jq empty "$settings_file"` succeeds (true for every omawsl-deployed
   machine-settings file, and for any native file without comments): merge with `jq` exactly as
   today (`.["workbench.colorTheme"] = $theme`).
2. **JSONC fallback** — `jq empty` fails. Strip comments into a *throwaway scratch copy*, used
   only to (a) confirm the file is otherwise structurally valid JSON and (b) check via
   `jq -e 'has("workbench.colorTheme")'` whether the key already exists. The scratch copy is
   never written back anywhere. The real edit is a targeted `sed`/`awk` pass against the
   **original, comment-containing file**:
   - key exists → `sed` replaces just that key's value on its line
   - key absent → `awk` inserts a new `"workbench.colorTheme": "<name>",` line immediately
     after the file's first `{`
   Comments survive because the write path never touches them — not because anything is
   stripped and reinserted.

The comment stripper (new `omawsl_strip_jsonc_comments`) handles the common case — `//` line
comments and single-line `/* ... */` — via `sed`, not multi-line block comments (documented
limitation, rare in practice for a settings key/value file). If the stripped scratch copy still
doesn't parse as JSON, the whole merge skips gracefully rather than guessing.

**Safety, matching the Windows Terminal precedent exactly:**

- Always `cp` a `.bak` copy of the target file before any edit — including the 2 existing
  Remote-WSL files, which don't currently get one. A corrupted settings.json breaks the user's
  whole editor, not just the theme.
- After editing, re-run the strip-and-validate check on the *result*. If it doesn't come back
  structurally valid JSON, discard the edit and leave the original file in place (backup still
  available at `<file>.bak`), printing a skip message instead of failing the rest of
  `bin/omawsl theme`.
- Never `mv` across the `/mnt/c` boundary for the same reason `bin/omawsl-sub/windows-terminal.sh`
  already avoids it (drvfs doesn't support the metadata-preserving syscalls `mv` attempts) — use
  `cp` + `rm` for the final commit step.

## Wiring

`omawsl_theme_apply_vscode` (in `themes/set-vscode-theme.sh`) calls the unified merge function
for all 4 targets:

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

If `omawsl_windows_userprofile` itself fails (not real WSL2, or `cmd.exe`/`wslpath` unreachable —
same condition Windows Terminal theming already tolerates), the two native syncs are silently
skipped; the Remote-WSL syncs and extension install are unaffected.

## Docs

`docs/windows-setup.md`:

- Quick-reference table: extend the existing "After running `bin/omawsl theme`" row's
  description to cover VS Code/Cursor's native settings too (still "nothing — automatic").
- Add a new sibling `#vscode-theme` anchor/section, same style as `#windows-terminal-theme`,
  documenting: this is automatic, lists the two native paths, and gives the manual fallback —
  set `"workbench.colorTheme"` to the theme's Title Case name (e.g. `"Tokyo Night"`) yourself —
  for the skip case.

## Testing

New `tests/theme_vscode_windows_test.bats`, mirroring `tests/windows_terminal_test.bats`'s
structure (stubbed `cmd.exe`/`wslpath` to fake a Windows profile dir, real `jq`):

- Key added when the target file exists but has no `workbench.colorTheme` key yet (strict JSON).
- Key replaced when it already exists (strict JSON).
- JSONC file with `//` comments: key merged/added, comments still present in the result
  byte-for-byte outside the edited line.
- Target file missing → skipped, no file created, no error.
- Edited result fails re-validation (simulated) → original file left untouched, `.bak` exists.
- `omawsl_windows_userprofile` failing (non-WSL2 environment) → native syncs skipped, Remote-WSL
  syncs still run.
