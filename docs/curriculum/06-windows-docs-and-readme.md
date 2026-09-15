# Phase 6: Windows-side docs and README

## 1. Concept

Every phase so far has written code that runs *inside* WSL and only ever touches things
WSL fully owns: `~/.bashrc`, `~/.config`, apt packages, Docker containers, `mise`-managed
runtimes. That's the sandbox. omawsl's one hard rule, held since Phase 1, is that it never
silently reaches past that sandbox onto the actual Windows machine the user is sitting at
— no unrequested installs, no unrequested edits to files outside WSL.

Windows Terminal, though, *is* outside that sandbox. So is a font. So, on a locked-down
corporate laptop, is anything that needs an IT ticket to install. A bash script running
inside WSL has no supported way to click through the Windows Terminal installer, drop a
`.ttf` into the Windows font store, or decide on the user's behalf that installing
software on their host is fine right now. Phase 5 already carved out the one narrow,
tested exception to this rule — `bin/omawsl theme` editing Windows Terminal's
`settings.json` directly, but only ever the `schemes`/`colorScheme` keys, backed up
first, skipped gracefully on any doubt. Everything else about the Windows side stays
firmly on the other side of the line: never automated, always a human's explicit choice.

So Phase 6 ships no new `install/terminal/*.sh` script and no new `install.sh` step. What
it ships instead is:

- **`docs/windows-setup.md`** — the one canonical walkthrough for every "you'll need to
  do something on Windows" moment elsewhere in the tool (the pre-install checklist, an
  editor's detect-and-defer message, `bin/omawsl doctor`). Every one of those messages
  links here instead of re-explaining the steps inline.
- **`windows/*.json`** — ready-made Windows Terminal settings *fragments* a human copies
  into their own `settings.json` by hand. Never read by any bash script.
- **`windows/fonts/README.md`** — a pointer to where the actual font file lives upstream
  (not vendored into this repo).
- **`windows/setup.ps1`** — an optional PowerShell helper that automates the parts of
  this that *can* be automated (once the user chooses to run it themselves), enforced by
  a repo-wide test that no `.sh` file anywhere ever invokes it.
- **`README.md`** — the front door: what to do before `install.sh` even exists on your
  machine yet.

This phase is also where two loose threads from earlier phases get tied off.
`docs/prerequisites.md` (written in Phase 4) and `docs/zellij-keybinding-fixes.md`
(written in Phase 5) were both **interim stopgap docs** — real findings that needed
somewhere to live before their permanent home existed, each opening with an explicit
blockquote naming the future phase responsible for folding them in and deleting them.
Phase 6 is that future phase. Closing them out is itself a skill: fold the content into
the real location, delete the interim file, and grep the *whole* repo for any reference
that still points at the deleted path before calling it done — a dangling link is worse
than an ugly one.

Two beginner concepts worth pinning down before the walkthrough, because they're used
freely from here on:

**Markdown heading auto-slugs.** Most Markdown renderers (GitHub included) turn a
heading like `## VS Code` into an HTML element with an automatically generated `id`
attribute, built by lowercasing the heading text and turning spaces into hyphens —
`vs-code`. This isn't part of the core Markdown spec; it's a per-renderer convention,
and different renderers slug the same heading differently. That matters here because
code shipped *before* this phase already hardcodes the link
`docs/windows-setup.md#vscode` (no hyphen) in several places — `grep` for it below shows
where. If `docs/windows-setup.md` relied on the auto-slug of a heading spelled `## VS
Code`, the real generated id would be `vs-code`, and every one of those existing links
would silently 404 the moment this repo gets a GitHub remote. A heading's rendered text
is free to change (it did — see the Walkthrough); a hardcoded link string in shipped,
tested code is not something this phase gets to rename.

**Explicit HTML anchors.** The fix is to stop depending on the auto-slug entirely.
`<a id="vscode"></a>` is a literal, empty HTML anchor tag, placed on its own line
immediately above a heading. It defines an exact target string, `vscode`, independent of
whatever the heading's prose says or how any given renderer would have slugged it. A
link to `docs/windows-setup.md#vscode` now resolves by fetching the page and jumping to
whichever element carries `id="vscode"` — and that id is a fact this file states
directly, not a fact you'd have to reverse-engineer from a heading's wording.

## 2. Walkthrough

### The JSON keybinding fragments (`windows/windows-terminal.json`, `windows/windows-terminal-fallback.json`)

JSON is a plain-text data format: objects are `{ "key": value, ... }`, arrays are
`[ value, value, ... ]`, and values nest arbitrarily. A "fragment" here means the file
is deliberately incomplete — it is never meant to *be* someone's whole
`settings.json`; it's a chunk a human copies specific keys out of. Here's the full
content of `windows/windows-terminal.json` (commit `687dbd1`):

```json
{
    "profiles": {
        "defaults": {
            "font": {
                "face": "CaskaydiaMono Nerd Font Mono"
            }
        }
    },
    "actions": [
        { "command": "unbound", "keys": "alt+left" },
        { "command": "unbound", "keys": "alt+down" },
        { "command": "unbound", "keys": "alt+up" },
        { "command": "unbound", "keys": "alt+right" }
    ]
}
```

Two things are happening in this one small file:

1. `profiles.defaults.font.face` sets the default font family for every Windows Terminal
   profile. The value, `CaskaydiaMono Nerd Font Mono`, is not a stylistic choice — it's
   a specific, correct fact sourced from `ryanoasis/nerd-fonts`' own README: Nerd Fonts
   renames patched fonts (`Cascadia Mono` → `CaskaydiaMono`) to avoid a font-licensing
   conflict (Microsoft's Cascadia Code/Mono ships under the SIL Reserved Font Name
   clause, which restricts redistributing modified copies under the *original* name).
   The `Nerd Font Mono` suffix (not plain `Nerd Font`) matters too: the plain variant's
   icon glyphs render about 1.5 character cells wide, which misaligns a monospace grid;
   the `Mono` variant fixes every glyph to exactly one cell, which is what a terminal
   needs.
2. `actions` is a top-level array — Windows Terminal's modern keybinding schema
   (replacing an older `keybindings`/`command`-string form). Each entry maps a `keys`
   chord to a `command`. `"command": "unbound"` is Windows Terminal's documented
   mechanism for *clearing* a built-in default binding without needing to know what its
   original command name was — you don't have to look up that `alt+left` is normally
   bound to `Terminal.MoveFocusLeft`; you just declare it unbound.

Why four unbinds, and why identically in both this file and `windows-terminal-fallback.json`
(same actions array, only the font face differs)? This closes out a real collision
documented in Phase 5's interim doc, `docs/zellij-keybinding-fixes.md`: Omakub's zellij
keybindings (ported verbatim in Phase 5) bind `Alt+Left/Down/Up/Right` for pane focus —
one of the few bindings zellij honors even in its default locked mode. Windows Terminal
binds the exact same four chords, by default, for moving focus between *its own* split
panes — and since Windows Terminal owns the keystroke before zellij (running inside it)
ever sees it, those four zellij bindings were dead on arrival under Windows Terminal.
The fix is independent of which font the user picked, so it belongs in both files
identically rather than being conditioned on font choice.

That interim doc had shipped with an explicit hedge: *"This exact JSON snippet is not
yet verified against a real, current Windows Terminal settings.json... Task 9 (manual
verification) must apply this snippet to the real test machine's actual Windows Terminal
settings.json, confirm Alt+Left/Down/Up/Right reaches zellij afterward."* That
verification had, per project memory, already happened in Phase 5. Phase 6 writes the
confirmed-working form directly into these two files without re-hedging — and then
deletes the interim doc (more on that below), because its only reason to exist was to
hold this finding until it had a permanent home.

### The font source pointer (`windows/fonts/README.md`)

This repo does not vendor a font binary. That's a deliberate precedent match, not an
oversight: Omakub's own font installer (`install/desktop/fonts.sh` in the upstream
project this repo adapts) doesn't commit a font binary to its git repo either — it
downloads the release fresh at install time from
`https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip`.
Since every Windows-side step here is manual/doc-only already, `windows/fonts/README.md`
documents that same upstream URL rather than checking a `.ttf` into git — a font binary
is a large, opaque, license-encumbered blob that doesn't belong in a script repo when
the real project it's already installed by publishes it as a release asset.

### The optional helper (`windows/setup.ps1`)

PowerShell is Windows' native shell scripting language — think of it as bash's Windows
counterpart, with its own syntax. A few things worth naming if this is your first look
at a `.ps1` file:

- The block at the very top, `<# .SYNOPSIS ... .DESCRIPTION ... .NOTES ... #>`, is a
  **comment-based help block** — PowerShell's convention for a script's built-in
  documentation, readable via `Get-Help` without opening the file.
- `param( [switch]$SkipFont )` declares the script's one optional command-line flag — a
  `switch` parameter is a boolean flag with no value to pass (`-SkipFont` present means
  true, absent means false), roughly PowerShell's equivalent of a bash script checking
  `[[ "$1" == "--skip-font" ]]`.
- `$ErrorActionPreference = "Stop"` is PowerShell's rough equivalent of bash's
  `set -euo pipefail` — without it, a failing cmdlet just prints a red error and
  *keeps going*, silently continuing an install with a step missing.
- Ordinary `function Name-Verb { ... }` blocks (`Test-WingetAvailable`,
  `Install-WindowsTerminal`, `Install-NerdFont`) do the actual work, each gated behind
  a check (`Get-Command winget -ErrorAction SilentlyContinue`) before assuming a tool
  is even present.

But the load-bearing property of this file isn't its PowerShell — it's that nothing in
this repo ever calls it. The script's own `.DESCRIPTION` says so in prose ("This script
is NEVER invoked automatically by boot.sh or install.sh"), and that claim is backed by
an actual test (`tests/windows_assets_test.bats`, added alongside this file) that greps
every `.sh` file in the repo for the string `setup.ps1` and fails if it finds one. A
comment saying "never invoked" is a promise; a test that would fail the moment any
future phase adds a call to it is the thing that keeps the promise honest.

### The canonical doc (`docs/windows-setup.md`)

Opens with the quick-reference table — one table, in one place, that every other
pointer into this file links to rather than reproduces:

```markdown
<a id="quick-reference"></a>
## Quick reference

| If you picked... | You'll need | Steps |
|---|---|---|
| (always) Windows Terminal itself | Install it, set the WSL profile as default | [#windows-terminal](#windows-terminal) |
...
```

Every section below it follows the same shape — an explicit anchor immediately above
a heading:

```markdown
<a id="vscode"></a>
## VS Code
```

Run `grep -rn "docs/windows-setup.md#" install bin` against this repo and you'll find
the exact anchor strings this doc has to hit, already load-bearing in shipped code:
`install/first-run-choices.sh` links `#fonts`, `install/windows-prereq-checklist.sh`
links `#docker-desktop`/`#vscode`/`#cursor`, `install/terminal/app-vscode.sh` and
`app-cursor.sh` link `#vscode`/`#cursor`, `install/terminal/docker.sh` links
`#docker-desktop`, and `bin/omawsl-sub/windows-terminal.sh` links
`#windows-terminal-theme`. None of those strings have a hyphen where the heading text
does (`vscode`, not `vs-code`) — proof this doc can't lean on auto-slugging and stay
correct.

Interesting wrinkle: even the `## Quick reference` heading itself was *missed* on the
first pass — commit `6bcd233` shipped the doc without an anchor above that one heading
(it happened to auto-slug to the right string by coincidence, `#quick-reference`, so
nothing broke yet). A later commit, `a3fb33c`, added it anyway, with the commit message
explaining why: *"Consistency fix from the final whole-branch review... per the plan's
own stated principle."* This is worth sitting with: "it happens to work today" and "it's
correct" are different claims, and a working-by-coincidence anchor is exactly the kind
of thing a future heading edit (a rename, a rewording) would silently break. The fix
went in during self-review, not because anything was observed failing yet.

One more real bug worth knowing about, because it's the same lesson Phase 2 taught with
code applied to prose: **doc claims need real-world verification too, not just internal
consistency.** The first draft of the Fonts section claimed the Nerd Font install would
make `fastfetch`'s logo and "powerline-style separators" render with icons. Commit
`2d109aa`, made *during* Task 7's real-machine verification pass, corrects this: this
repo never ships a custom `configs/fastfetch.jsonc` (no phase built one), so fastfetch's
output is plain apt-default text regardless of which font is active — that claim was
simply wrong, an assumption nobody had actually checked against the real installed tool.
The commit replaces it with `eza --icons`, confirmed by direct testing to emit real Nerd
Font glyph codepoints — the one tool actually installed by this repo (Phase 1's
`install/terminal/libraries.sh`) whose output genuinely depends on the font. A doc
passing "does it read sensibly" is not the same bar as "is every specific claim in it
actually true" — and the second bar needs the same real-machine check code does.

### Closing out `docs/prerequisites.md`

Written in Phase 4, this file opened with a blockquote naming its own expiration
condition:

> **Interim document.** ... **When Phase 6 builds them:** fold this file's content into
> that canonical table, delete this file, and update
> `install/terminal/app-gh-copilot.sh`'s failure message (currently pointing at
> `docs/prerequisites.md#github-copilot-cli`) to point at the new location instead - do
> not leave a dangling reference to a deleted file.

Commit `fa7b674` does exactly that, in the order the blockquote implies: update the one
live reference *before* deleting the file it pointed at, never after —

```diff
-    echo "See docs/prerequisites.md#github-copilot-cli for why this needs to happen before install.sh, not after."
+    echo "See docs/windows-setup.md#github-copilot-cli for why this needs to happen before install.sh, not after."
```

(and the matching test assertion in `tests/app_gh_copilot_test.bats`, same diff shape)
— then `git rm docs/prerequisites.md`, then a repo-wide grep for the deleted path to
confirm nothing else still points at it. The alternative order — delete first, fix the
reference later — would leave a real window where shipped code points at a file that no
longer exists; there's no reason to accept that window when reordering the two steps
costs nothing.

### Closing out `docs/zellij-keybinding-fixes.md`

Same pattern, one step simpler: this file's *entire* purpose was to hold the
Alt-arrow-collision finding until `windows/*.json` and `docs/windows-setup.md` existed
to receive it (both landed earlier in this same phase — Tasks 1 and 3 before Task 5).
Closing it out (commit `7c2d398`) is a confirm-then-delete, not a fold-then-delete: grep
both JSON files for `"command": "unbound"` and the doc for the collision writeup, confirm
both are already there, then `git rm` the interim file. Nothing needs rewriting because
the earlier tasks already wrote the permanent copies.

### `README.md`

The repo's front door, and the one file every visitor sees before any other doc. Its
"Before you begin" section is deliberately scoped to *only* what gets a user from having
nothing to a fresh WSL prompt with `install.sh` reachable — installing WSL itself
(`wsl --install -d Ubuntu`, pointing to Microsoft's own docs for the fast-moving details
omawsl doesn't try to maintain a parallel copy of), and an *optional* pointer to prep
Windows-side software before running `install.sh` reactively hits the same checklist.
That optional step links the quick-reference table:

```markdown
See the quick-reference table at the top of
[`docs/windows-setup.md`](docs/windows-setup.md#quick-reference) for exactly what each
picker option needs on the Windows side...
```

— a link, not a second copy of the table. Two copies of the same table drifting out of
sync over time is exactly the failure mode a single canonical source avoids; the project
enforces this with a test (`tests/readme_test.bats`) that both checks for the link *and*
greps for the table's own pipe-syntax header row to make sure nobody pasted it in
verbatim.

The "What omawsl deliberately excludes" section is a different kind of documentation
than everything else in this phase — not "how do I do X," but "why doesn't this tool do
X," naming real, considered decisions (37signals commercial products, the Windows
desktop-app layer, any automatic Windows-side install, Typora, X11 compose-key mappings)
so a reader doesn't mistake a deliberate scope boundary for an oversight.

## 3. Exercise

Close this lesson and rebuild Phase 6 from scratch, blind, in
`practice/06-windows-docs-and-readme/`. You're recreating five files. Be exact about the
pieces below — they're what the check in step 4 verifies:

**`docs/windows-setup.md`**
- Opens with a `## Quick reference` heading, preceded on its own line by
  `<a id="quick-reference"></a>`, appearing before any other `##` section heading in the
  file.
- Contains seven more sections, each preceded by its own explicit anchor tag, using
  exactly these id strings (these are the ones already hardcoded into shipped code, so
  they're not negotiable): `windows-terminal`, `fonts`, `docker-desktop`, `vscode`,
  `cursor`, `github-copilot-cli`, `windows-terminal-theme`. The heading text above each
  anchor is yours to write — the anchor `id` is the part that has to match exactly.

**`windows/windows-terminal.json`**
- Valid JSON.
- `profiles.defaults.font.face` is exactly `CaskaydiaMono Nerd Font Mono`.
- A top-level `actions` array containing four entries with `"command": "unbound"`, whose
  `keys` are exactly `alt+left`, `alt+down`, `alt+up`, and `alt+right` (order doesn't
  matter).

**`windows/windows-terminal-fallback.json`**
- Same shape as above, except `profiles.defaults.font.face` is exactly `Cascadia Mono`.

**`windows/fonts/README.md`**
- Contains, somewhere in its text, the real upstream URL:
  `https://github.com/ryanoasis/nerd-fonts/releases/latest/download/CascadiaMono.zip`

**`README.md`**
- Contains a `## Before you begin` heading.
- Links `docs/windows-setup.md#quick-reference` rather than reproducing the table.

Starter (empty) files for all five are already in place under
`practice/06-windows-docs-and-readme/` — fill them in. `windows/setup.ps1` is
deliberately not part of this exercise's checked scope (there's no PowerShell
interpreter to run it against here); if you want the extra practice, write it anyway
using the Walkthrough's description of what it should do, but the check script won't
grade it.

## 4. Check

Run:

```bash
practice/06-windows-docs-and-readme/check.sh
```

Each line printed is one assertion: `PASS:` or `FAIL:` followed by which requirement it
was checking. A `FAIL:` line tells you which *observable fact* didn't match — a missing
anchor id, a wrong font-face string, a missing keybinding entry — not which lines differ
from the original files. A passing check means your doc and JSON structurally satisfy
everything shipped code and the other tests in this repo actually depend on, even if
your heading wording, prose, or JSON key ordering looks nothing like the original.

Once it's green, you can diff your files against the real ones
(`git show d325b9d:docs/windows-setup.md`, and similarly for the `windows/*.json` files)
purely to compare style and see how the original phrased things — never as part of the
grade.
