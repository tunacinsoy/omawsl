# Lesson 19: Starship as the default prompt

## 1. Concept

Every interactive bash shell has a variable called `PS1` ("prompt string 1") that holds
the literal text bash prints before each command line — the thing you type your
commands after. It's just a string, usually full of escape sequences (`\u` for
username, `\w` for working directory, `\[\e]0;...\a\]` to set the terminal tab title)
that bash expands fresh every time it draws a new prompt. Since Lesson 1, omawsl has
set `PS1` to one hand-rolled value: a single Nerd Font glyph (or, without a Nerd Font,
a plain `user@host:path$`), assigned once near the top of `configs/bashrc` and never
touched again.

A static `PS1` string can't show you anything that changes between commands — which
git branch you're on, whether the working tree is dirty, which Node/Ruby/Python version
`mise` (Lesson 3) activated for this directory. To show any of that, you'd need to
recompute the string before every single prompt. Bash has a hook for exactly this:
`PROMPT_COMMAND`, a variable holding a command (or, in modern bash, an array of
commands) that bash runs immediately before drawing each prompt. `zoxide` and `mise`
already use it — `zoxide` to keep track of directories you visit for its `z` jump
command, `mise` to keep language shims current for the directory you just landed in.
The convention this file already follows is "append, don't clobber `PROMPT_COMMAND`" —
each tool adds its own hook without deleting anyone else's.

Starship is an external program (a compiled Rust binary, not a bash function) built
entirely around that hook: `eval "$(starship init bash)"` asks the `starship` binary to
print a chunk of bash code, and `eval` runs it in your current shell. That code
registers starship's own function onto `PROMPT_COMMAND`, which on every prompt draw
re-runs `starship prompt` to compute a fresh `PS1` value — current directory, git
branch/status, and a language-version badge when it detects a matching project, all
read from the filesystem *at that instant*, not baked in once at shell startup.
Starship stays pure display logic: it only ever sets `PS1`/`PROMPT_COMMAND`, so it
doesn't functionally overlap with what `zoxide` or `mise` are doing with the same hook.

This is exactly why *where* the init line goes in `configs/bashrc` matters, and why it
isn't arbitrary the way it might look. `mise activate bash` — like `zoxide init bash` —
mutates `PATH` and environment variables that starship's language-version modules read
on every render (which Ruby version is active, which Node version, etc.). If starship's
own hook were registered *before* mise's, its `PROMPT_COMMAND` entry would run first on
every draw and read whatever `PATH`/env existed *before* mise's hook updated them that
render — a one-render-stale value, not garbage exactly, but wrong. This is the same
category of bug Lesson 3 covered for `PATH` exports (a freshly-mise-installed tool not
being reachable in the *next* shell because the `PATH` export ran too late) — a
different symptom, same root cause: bash config is order-sensitive, and "this variable
exists" isn't the same guarantee as "this variable was updated recently enough to be
useful." Starship's own upstream documentation says as much directly: register its init
line *last*, after every other tool that also hooks `PROMPT_COMMAND`, because a hook
registered after starship's own breaks the chain outright.

Unlike every other optional tool omawsl installs, starship ships as an **unconditional
default**, not a first-run picker choice (see `install/first-run-choices.sh` from
Lesson 1) — the richer prompt is judged a straightforward improvement worth giving
everyone, not a behavior change that needs explicit consent. It still has to respect
one piece of existing state, though: `OMAWSL_FONT_MODE` (Lesson 1's font choice) — the
Nerd Font glyphs starship's fuller default leans on even more than the old icon-only
`PS1` did would render as tofu boxes without a matching font, so the Cascadia Mono
choice gets a second, glyph-free starship config instead.

Starship reads its configuration from a **TOML** file (`~/.config/starship.toml`).
TOML ("Tom's Obvious, Minimal Language") is a plain-text config format built around
`key = "value"` lines, grouped into named sections written as `[section.name]` — the
same shape you'll see below in a `[palettes.<theme>]` block. It has no braces, no
significant indentation, and (unlike YAML) no ambiguity about whether `no` means the
string `"no"` or the boolean `false` — a deliberate design reaction to YAML's rougher
edges, which is part of why a growing set of tool configs (Rust's `Cargo.toml`, this
one) picked it.

## 2. Walkthrough

**Installing the binary** (`install/terminal/apps-terminal.sh`). No Ubuntu package
exists for starship, so — matching zellij/lazydocker/lazygit's precedent already in
this file — it installs the official prebuilt binary straight from GitHub releases,
not starship's own `curl -sS https://starship.rs/install.sh | sh` one-liner. The
project has stayed consistent on this the whole way through: piping an unseen remote
script into a shell is exactly the kind of thing this repo avoids, in favor of explicit
steps you can read and audit yourself.

```bash
omawsl_starship_asset() {
  case "$(uname -m)" in
    aarch64) echo "starship-aarch64-unknown-linux-musl.tar.gz" ;;
    *) echo "starship-x86_64-unknown-linux-gnu.tar.gz" ;;
  esac
}

omawsl_starship_install_steps() {
  local asset
  asset="$(omawsl_starship_asset)"
  curl -fsSL "https://github.com/starship/starship/releases/latest/download/${asset}" | tar -xz -C /tmp starship
  sudo install -m 0755 /tmp/starship /usr/local/bin/starship
  rm -f /tmp/starship
}

omawsl_install_starship() {
  if command -v starship &>/dev/null; then return 0; fi
  omawsl_starship_install_steps
}
```

`omawsl_starship_asset` is a `case` statement dispatching on `uname -m` (the machine's
CPU architecture) — the same shape `omawsl_lazygit_arch`/`omawsl_fastfetch_arch` in the
same file already use, rather than, say, a lookup table or an associative array: a
two-branch decision reads more directly as a `case` here, and it matches how every
other arch-dispatch function in this file is already written. The comment above it in
the real source records something worth noticing about *why* it only special-cases
`aarch64`: starship's releases publish a glibc ("gnu") build for x86_64 but only a musl
build for aarch64 — no `aarch64-unknown-linux-gnu` asset exists at all. musl binaries
are statically linked (they carry their own C library instead of depending on the
system's), so the aarch64 musl build runs fine on Ubuntu's ordinary glibc userspace
regardless. Every other architecture falls through to the `x86_64` default, same
"good default over long unreachable branch" logic used everywhere else in this file.

`omawsl_starship_install_steps` is deliberately unguarded — split out from
`omawsl_install_starship`'s `command -v` check — for the same reason
`omawsl_zellij_install_steps` is: the orphan-tools update registry (below) and the
migration (also below) both need to force a *re*-install of a tool that's already
present, which the guarded wrapper's early-return would block. One function does the
actual work; a second, thin wrapper adds the "skip if already installed" behavior on
top. (In the real repo's history, the three-line `curl | tar` / `sudo install` / `rm`
sequence started out duplicated by hand across zellij/lazydocker/lazygit/starship, and
a later code-review pass factored it into one shared `omawsl_github_binary_install
<url> <binary>` helper all four now call — worth noticing as an example of a
refactor driven by literal duplication becoming visible only once a fourth copy of the
same three lines showed up.)

**Wiring it into `configs/bashrc`.** The old static-`PS1` block is deleted outright —
not commented out, not kept as a fallback path inline — and this goes in near the very
end of the file, after the `mise activate bash` line and right before the
`exec zellij` auto-launch guard that must stay the literal last thing in the file:

```bash
OMAWSL_FONT_MODE="$(grep -m1 '^OMAWSL_FONT_MODE=' "${OMAWSL_STATE_DIR:-$HOME/.local/state/omawsl}/choices.env" 2>/dev/null | cut -d'"' -f2)"
if command -v starship &>/dev/null; then
  if [[ "$OMAWSL_FONT_MODE" == "Cascadia Mono"* ]]; then
    export STARSHIP_CONFIG="$HOME/.config/starship-plain.toml"
  else
    unset STARSHIP_CONFIG
  fi
  eval "$(starship init bash)"
else
  # Pre-starship fallback - offline/failed install, or a checkout that
  # predates this feature and hasn't finished migrating yet.
  if [[ "$OMAWSL_FONT_MODE" == "Cascadia Mono"* ]]; then
    PS1='\u@\h:\w\$ '
  else
    PS1=$' '
  fi
  PS1="\[\e]0;\w\a\]$PS1"
fi
unset OMAWSL_FONT_MODE
```

Three decisions worth naming individually here:

- **`command -v starship &>/dev/null` as the outer branch, with the exact old `PS1`
  logic preserved verbatim in the `else`.** A starship install can fail silently
  (offline machine, corporate proxy blocking GitHub) — without this fallback, a failed
  install would leave `PS1` completely unset instead of degrading to something that
  still works. This is the same defensive shape every other optional-tool block in this
  file already uses (`if command -v X &>/dev/null; then ... fi`), just with a two-sided
  `if`/`else` instead of a bare guard, because "tool missing" here needs to actively
  *do* something (the old logic), not just skip a block.
- **`STARSHIP_CONFIG` is set on *every* branch, not just when it needs a value.** An
  earlier version of this logic only set `STARSHIP_CONFIG` in the Cascadia Mono branch
  and left it alone otherwise — but `configs/bashrc` gets re-sourced (a new terminal
  pane, `source ~/.bashrc`), and a stale exported value from a *previous* font-mode
  choice would leak into a shell that should now be unset. Explicitly `unset`-ing it in
  the Nerd Font branch, not just omitting the `export`, is what makes this correct
  across a font-mode change without requiring a fresh login.
- **Nerd Font mode ships *no* config file at all**, rather than an empty
  `starship.toml`. Starship's real zero-config default (no file present) already *is*
  the fuller, more-informative-than-the-old-PS1 look this lesson is about — directory,
  git status, and every language module auto-activating with no format string to write
  or maintain. Only the no-Nerd-Font case needs a real file, because it has to override
  the small set of modules whose *default* symbols are Nerd-Font-only glyphs.

**The themed configs** (`bin/omawsl-sub/theme.sh`, `themes/<name>/starship.toml` +
`starship-plain.toml`). Every theme directory already carries an 11-color palette
(`red`/`green`/`blue`/`yellow`/`magenta`/`orange`/`cyan`/`black`/`white`/`bg`/`fg`) in
its `zellij.kdl`. Starship has its own palette mechanism built for exactly this: define
a `[palettes.<name>]` section mapping those *same color names* to hex values, then set
`palette = "<name>"`, and every built-in module style that already references `red`,
`green`, etc. gets recolored automatically — no per-module style rewriting needed, just
one palette block per file. Here's `themes/tokyo-night/starship.toml` in full:

```toml
"$schema" = 'https://starship.rs/config-schema.json'

palette = "tokyo-night"

[palettes.tokyo-night]
red = "#F93357"
green = "#9ECE6A"
blue = "#7AA2F7"
yellow = "#E0AF68"
magenta = "#BB9AF7"
purple = "#BB9AF7"
orange = "#FF9E64"
cyan = "#2AC3DE"
black = "#383E5A"
white = "#C0CAF5"
bg = "#1A1B26"
fg = "#A9B1D6"
```

(`purple` duplicates `magenta`'s value — starship's own built-in module styles
reference both names in different places, and this repo's theme data only ever tracked
one "magenta-ish" color, so it's mapped onto both palette keys rather than inventing a
second color the rest of the theme system doesn't have.) The 20 files (2 per theme × 10
themes) are hand-authored static files, matching every other per-theme file in this
repo (`neovim.lua`, `zellij.kdl`, `btop.theme`, `vscode.sh`,
`windows-terminal-scheme.json` are all static too) — there's no generator tooling
committed to the repo, on purpose, matching the project's stated constraint of "no
build step this repo doesn't otherwise have." `omawsl_theme_apply` copies both files
into place unconditionally, right alongside its existing zellij/btop copies:

```bash
cp "$theme_dir/starship.toml" "$HOME/.config/starship.toml"
cp "$theme_dir/starship-plain.toml" "$HOME/.config/starship-plain.toml"
```

No `[[ -f ... ]]` guard — same as every other file `omawsl_theme_apply` copies. That's
deliberate: `omawsl theme <name>` is an explicit, user-invoked action, so overwriting
whatever was there before (including a previous theme's colors, or a hand-edited file)
is exactly what should happen. Compare that to `omawsl_install_starship_config`
(install time, not user-invoked): it copies the plain-mode default *only if the file
isn't already there* — an install should never clobber something a user already
customized, but a theme switch the user just asked for should.

**Update registry and doctor.** `bin/omawsl-sub/orphan-tools.sh` already has a
registry pattern for tools that install outside apt and need their own update-check
logic (zellij, lazydocker, and the AI CLIs) — starship slots into the exact same shape:
one more entry in `omawsl_orphan_tool_slugs`, one more `case` arm in
`omawsl_orphan_tool_label`/`_installed`/`_version_installed`/`_version_latest`/
`_apply_update`, resolving its latest version via the GitHub releases API
(`starship/starship`'s `tag_name`, a plain `vX.Y.Z` tag the existing semver extractor
already handles) the same way lazydocker's entry does. `bin/omawsl-sub/doctor.sh` gets
one small, standalone addition — `omawsl_doctor_starship_missing` — deliberately *not*
routed through `orphan-tools.sh`'s own `omawsl_orphan_tool_installed starship` case,
even though the check (`command -v starship`) is identical: `orphan-tools.sh` pulls in
a much heavier dependency chain (it sources `apps-terminal.sh` plus five other
`app-*.sh` files just to build its registry), and `doctor.sh` is deliberately kept
independently testable without dragging all of that in. Two files doing the same
one-line check, on purpose, because the cost of the "shared" version would be a much
heavier test setup for every doctor test.

**Migrating existing installs.** `migrations/1786305600.sh` installs the binary and
default config for anyone whose checkout predates this feature, then tries to preserve
whatever theme they'd already picked. The subtle part: `configs/zellij.kdl` (what a
fresh install deploys *before* anyone ever runs `omawsl theme`) already ships with
`theme "tokyo-night"` as its own stock reference line — so *just* checking that
`~/.config/zellij/config.kdl` names a real, valid theme isn't enough; it would be true
for every install that never touched theming at all, and would wrongly theme starship
for them. The real signal that someone genuinely ran `omawsl theme <name>` is that the
*actual theme file* it creates — `~/.config/zellij/themes/<name>.kdl` — exists on disk,
since only `omawsl_theme_apply` ever writes that file:

```bash
omawsl_starship_migrate_active_theme() {
  local zellij_config="$HOME/.config/zellij/config.kdl"
  [[ -f "$zellij_config" ]] || return 0
  local active_theme
  active_theme="$(grep -oP '(?<=theme ")[^"]+' "$zellij_config" | head -n1 || true)"
  [[ -n "$active_theme" ]] || return 0
  omawsl_theme_is_valid "$active_theme" || return 0
  [[ -f "$HOME/.config/zellij/themes/$active_theme.kdl" ]] || return 0
  omawsl_theme_apply "$active_theme"
}
```

That `|| true` after `head -n1` isn't decoration — it was added in a follow-up fix
after code review caught a real bug: under `set -euo pipefail`, a `config.kdl` with
*no* `theme "..."` line at all makes `grep -oP` exit 1, and pipefail propagates that
through `head -n1`, aborting the whole migration script before the very next line's
`[[ -n "$active_theme" ]] || return 0` guard — the guard that was *supposed* to handle
exactly this case — ever got a chance to run. Since a migration only counts as complete
once its script exits 0, this made `omawsl migrate` fail permanently for any themeless
config until the fix landed. It's a good concrete example of a general trap: a guard
clause you wrote to handle "no value" doesn't help if the line computing that value
already aborted the whole script before reaching it.

## 3. Exercise

Close this lesson and rebuild it from scratch, blind, in
`practice/19-starship-default-prompt/starship.sh`. That file already has function
signatures and comments (no implementation) for four functions — fill them in:

1. **`omawsl_starship_asset`** — echo the correct release asset filename for the
   current architecture (`uname -m`): the x86_64 gnu build by default, the aarch64
   musl build when `uname -m` says `aarch64`.
2. **`omawsl_starship_install_steps`** — download that asset from starship's GitHub
   releases with `curl`, extract the `starship` binary from the tarball with `tar`,
   and install it to `/usr/local/bin/starship` with `sudo install`. No guard needed —
   this function should always perform the install when called.
3. **`omawsl_write_starship_theme <name> <red> <green> <blue> <yellow> <magenta>
   <orange> <cyan> <black> <white> <bg> <fg>`** — write `$HOME/.config/starship.toml`
   containing a `palette = "<name>"` line and a `[palettes.<name>]` section with one
   `key = "value"` line per color, using starship's own key names. Overwrite
   unconditionally on every call — no "skip if it already exists" check.
4. **`omawsl_ensure_starship_bashrc_line`** — make sure `$HOME/.bashrc` contains
   `eval "$(starship init bash)"`, positioned *after* any existing
   `eval "$(mise activate bash)"` line (or anywhere sensible if there isn't one).
   Calling it twice must not add a second copy of the line, and it must not fail if
   `~/.bashrc` doesn't exist yet.

Don't wire any of this into a CLI dispatcher or write a real `PS1`/`starship init`
fallback branch — this exercise is scoped to the four functions above, not the full
`configs/bashrc` block from the Walkthrough.

## 4. Check

Run:

```bash
practice/19-starship-default-prompt/check.sh
```

It prints one `PASS`/`FAIL` line per behavior it checks and exits non-zero if anything
failed. A few things worth knowing about how it's built, so a failure tells you
something useful:

- It never touches your real `$HOME` or installs a real binary anywhere. Every call
  into your code runs with `HOME` and the working directory pointed at a throwaway
  scratch directory, and `curl`/`sudo`/`tar` are replaced with stand-ins that just
  record what they were called with — so `omawsl_starship_install_steps` is checked by
  *what command it would have run*, not by anything actually downloading or installing.
- The theme-writing checks use real hex values from this repo's own `tokyo-night` and
  `rose-pine` themes, and check for `palette = "tokyo-night"`, a `[palettes.tokyo-night]`
  section, and the recolored `red`/`green`/`blue` values — not the exact byte-for-byte
  file the original ships, so extra whitespace, a different key order, or an extra
  comment won't fail it.
- The bashrc checks pre-write a fake `~/.bashrc` containing a `mise activate bash`
  line, then check both that a `starship init bash` line got added *and* that its line
  number is greater than the mise line's — so a `FAIL` there tells you the ordering is
  wrong, not just that the line is missing.

A passing check means your implementation is behaviorally correct, even if it doesn't
look anything like the original — different variable names, a different way of writing
the TOML, `awk` vs. `sed` for the bashrc insertion, all fine. Once it passes, you can
look at the real functions in `install/terminal/apps-terminal.sh`,
`themes/tokyo-night/starship.toml`, and `configs/bashrc` purely to compare style — never
as part of grading yourself.
