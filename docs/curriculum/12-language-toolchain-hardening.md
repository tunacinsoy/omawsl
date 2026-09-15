# Lesson 12: Language Toolchain Hardening

## 1. Concept

By the end of Phase 3 (`languages-and-cloud-tools`), omawsl could already
drive `mise` to install a chosen set of language runtimes. That code was
correct on paper and green in CI. Then it got run on a real machine with a
real set of language selections, and a cluster of very specific,
very-easy-to-miss failures showed up — the subject of this phase.

**Why a compiled extension needs a `-dev` package.** PHP isn't installed as
a single monolithic binary here — mise builds it from source, the same way
it builds most of the tools omawsl manages. PHP's core ships with several
*optional extensions* — curl support, image handling (GD), Unicode/locale
support (intl), zip archive support, multibyte string handling (mbstring) —
each backed by an external C library that already exists on the system
(libcurl, libgd, libicu, libzip, oniguruma). Building an extension means
compiling C code that calls functions declared in that library, which
requires two things at *build* time that are completely separate from
whether the library is usable at *run* time:

- **Header files** (`.h`) — the library's declared function signatures and
  data structures, which the compiler needs to check your code calls the
  library correctly.
- **`pkg-config` metadata** — a small `.pc` file recording which compiler
  and linker flags to pass so the build can actually find and link against
  the library.

Ubuntu's apt packaging splits every C library into (at least) two apt
packages: a runtime package (e.g. `libcurl4`) that ships just the compiled
`.so` file a running program loads, and a **`-dev` package**
(`libcurl4-openssl-dev`) that ships the headers and `pkg-config` metadata,
installed only on machines that *build* software linking against that
library. A machine can have the runtime library and still fail to *build*
anything against it, because the `-dev` package — and only the `-dev`
package — carries what the build needs. That's the exact failure mode
here: mise-building PHP got partway through its own `./configure` step and
died with `Package 'libcurl' not found`, because `pkg-config` had nothing
to find.

**Why install order matters (Erlang before Elixir).** Elixir's own
compiler is written in Erlang. mise's Elixir plugin does not treat Erlang
as a declared dependency it fetches for you — it just assumes an `erl`
binary is already on `PATH` when Elixir's own post-install build step
runs, and fails outright (`exec: erl: not found`) if it isn't. mise has no
general cross-plugin dependency graph; each `mise use --global X@latest`
call is independent. So the *order* two independent install calls happen
to run in — something a machine has no reason to get right on its own —
becomes something the installer script has to get right by construction:
issue the Erlang install and let it finish before issuing the Elixir
install.

**Two narrow, environment-specific workarounds.** Not every bug in this
phase is a missing package. Two are workarounds for behavior specific to
one platform, worth understanding as a category even though the fixes
themselves are narrow:

- An **environment variable** is just a named value living in a process's
  environment — inherited by every child process it starts — used to pass
  configuration around without changing any code (`$HOME`, `$PATH`, and so
  on are all environment variables). `XDG_RUNTIME_DIR` is one defined by
  the freedesktop.org XDG Base Directory spec: a directory, private to the
  current login session, meant for small non-essential runtime files like
  Unix sockets. WSL2's WSLg component (the piece that lets Linux GUI apps
  show up on the Windows desktop) sets `XDG_RUNTIME_DIR` to a synthetic
  mount, `/mnt/wslg/runtime-dir`, that's hardcoded to UID 1000 and doesn't
  reliably support the `chmod 0700` the terminal multiplexer `zellij`
  needs to make on its own socket directory — a real bug in that mount
  (tracked upstream against WSL itself), not something omawsl can fix.
  Instead of touching the mount, the fix points a *different* env var
  zellij itself checks (`ZELLIJ_SOCKET_DIR`) straight at the same
  `/tmp`-based path zellij would already use if `XDG_RUNTIME_DIR` were
  simply unset — sidestepping the broken mount rather than repairing it.
- Third-party apt repositories are usually published **per Ubuntu
  codename** (`jammy` for 22.04, `noble` for 24.04, and so on), because a
  repo's packages can declare codename-specific dependencies. Vendor repos
  lag behind new Ubuntu releases. When the azure-cli fix here was written,
  Microsoft's own azure-cli apt repo had no published directory yet for
  Ubuntu 26.04's codename (`resolute`) — so every install silently failed
  at `apt-get update` and Azure CLI was skipped on every run, with no
  loud error pointing at why. The fix probes whether the repo actually
  publishes the host's codename before trusting it, and falls back to a
  known-good codename (`jammy`) otherwise — the same fallback Microsoft's
  own official install script uses — since the `.deb` package itself
  carries no codename-specific dependencies; only the repo layout does.

The throughline across all four fixes: none of them were discoverable by
reading the code. Each one only showed up by actually running the
installer on a real machine with a real language selection, in real WSL2,
against a real (and changing) third-party apt repo — the same lesson
Phase 10 introduced with a different bug cluster.

## 2. Walkthrough

**The three `libraries.sh` commits.** `install/terminal/libraries.sh`
holds one function, `omawsl_install_libraries`, that always installs a
fixed set of apt packages regardless of which languages were picked (the
GD/intl/zip/curl/mbstring dependencies aren't gated behind "did the user
pick PHP" — they're just always present, the same way `build-essential`
already was). Three commits added one line each to the same
backslash-continued list, in the order each `./configure` failure was hit
for real:

```bash
# 2498394 — curl extension
    redis-tools sqlite3 libsqlite3-0 libsqlite3-dev libmysqlclient-dev libpq-dev \
    libcurl4-openssl-dev \
    postgresql-client postgresql-client-common

# 2d34618 — GD / intl / zip extensions
    libcurl4-openssl-dev libgd-dev libicu-dev libzip-dev \

# 7287c6f — mbstring extension
    libcurl4-openssl-dev libgd-dev libicu-dev libzip-dev libonig-dev \
```

The trailing `\` at the end of each line is bash's line-continuation
syntax — it tells the shell "this logical command keeps going on the next
line," which is why `sudo apt-get install -y \` followed by several
indented continuation lines is still one single command, not several. Each
commit's message names *why* that specific package, not just *that* a
package was added — worth reading in full (`git show 2d34618`), because
it explains a design decision: GD and zip were derived from reading
`mise-plugins/vfox-php`'s own `post_install.lua` (which passes
`--with-external-gd` and `--enable-intl` unconditionally, and `--with-zip`
conditionally) rather than discovering each one by waiting for the next
`./configure` crash. `libonig-dev`, by contrast, really was found by
hitting the failure: PHP 8 dropped bundling its own copy of the oniguruma
regex library, so `--enable-mbstring` now hard-requires the system one via
`pkg-config`, with no fallback.

An alternative not chosen: gating each `-dev` package behind whether the
matching language was actually selected (mirroring how
`select-dev-language.sh` gates *language runtimes* on `OMAWSL_LANGUAGES`).
That would minimize what gets installed on machines that never touch PHP.
It wasn't done here — `omawsl_install_libraries` runs once, unconditionally,
early in the install, before the language picker's choices are even fully
known to every later step, and keeping one flat list avoids threading
`OMAWSL_LANGUAGES` into a script that otherwise has no branching at all.

**The erlang-before-elixir commit (`29ac34a`).**
`install/terminal/select-dev-language.sh`'s `omawsl_select_dev_language`
loops over each possible `OMAWSL_LANGUAGES` selection with its own `if`
block, calling the shared `omawsl_install_language <mise_tool_name>`
helper (a one-line wrapper around `mise use --global <tool>@latest`). The
Elixir block gained one line right before its existing call:

```bash
  if omawsl_list_has "$languages" "Elixir"; then
    # Elixir's compiler is written in Erlang, and mise's elixir plugin doesn't
    # pull Erlang in for you - erlang must already be mise-installed and on
    # PATH before elixir's own post-install step runs, or it fails looking
    # for `erl`. Installing erlang first (not in parallel) avoids that.
    omawsl_install_language erlang
    omawsl_install_language elixir
  fi
```

Nothing about the *mechanism* changed — it's the same helper function,
called twice instead of once. The fix is entirely about *sequence*: bash
executes the statements in a function body top to bottom, and
`omawsl_install_language` is a synchronous call (it doesn't background
`mise` or return before `mise` finishes) — so writing the erlang call
first, in the same `if` block, is sufficient to guarantee it completes
before the elixir call begins. No new synchronization primitive, no flag,
no dependency-graph library — just call ordering, because that's all this
particular problem needed.

Notice that Erlang was deliberately *not* added as its own selectable
option in the language picker. It only exists in this install path as
Elixir's own dependency — a product decision, not an oversight. The
companion `uninstall/dev-language.sh` change (in the same commit) mirrors
this: removing Elixir also removes Erlang, since a user could never have
selected Erlang on its own in the first place, so leaving it behind on
Elixir's removal would orphan it outside anything the picker or `doctor`
can see.

**The WSL2/WSLg zellij fix (`2765fa4`).** `configs/bashrc` execs into
`zellij` (a terminal multiplexer) at the end of an interactive shell's
startup, guarded so it only fires for a shell that isn't already inside a
zellij session:

```bash
if [[ -z "${ZELLIJ:-}" ]] && command -v zellij &>/dev/null; then
  export ZELLIJ_SOCKET_DIR="/tmp/zellij-$(id -u)"
  exec zellij
fi
```

`$(id -u)` is command substitution running the `id -u` command (prints the
current user's numeric UID) and splicing its output into the string —
producing the same `/tmp/zellij-<uid>` path zellij's own code already
falls back to when `XDG_RUNTIME_DIR` is unset entirely. Setting
`ZELLIJ_SOCKET_DIR` explicitly, one line before `exec zellij`, means
zellij never consults the broken WSLg mount for its socket directory in
the first place — a workaround chosen over trying to `chmod` or otherwise
repair the mount, since that mount's behavior is outside anything running
inside WSL2 controls.

**The Azure CLI codename fallback (`869664c`).**
`install/terminal/cloud-tools.sh`'s `omawsl_install_azure_cli` builds an
apt source line for Microsoft's repo using the host's own Ubuntu codename,
read out of `/etc/os-release`:

```bash
codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
curl -fsSL -o /dev/null "https://packages.microsoft.com/repos/azure-cli/dists/$codename/Release" || codename="jammy"
```

`. /etc/os-release` (a leading `.` — the `source` builtin's short form)
runs that file's own `VAR=value` lines in the current shell, which is how
a plain text file ends up defining a shell variable like
`VERSION_CODENAME`; wrapping it with `&& echo "$VERSION_CODENAME"` inside
`$(...)` captures just that one value rather than leaking every variable
`/etc/os-release` sets into the rest of the function. The `curl` line
performs a lightweight existence check — `-o /dev/null` discards the
response body, keeping only the exit status — against the exact path
`apt-get update` would need to succeed later. `||` is bash's
short-circuit-or: the right side (`codename="jammy"`) only runs if the
left side (the `curl`) exits non-zero, whether that's because the
codename genuinely isn't published yet or because the network itself is
down. Both cases fall back to `jammy` identically, and the comment in the
real commit is explicit about why that's fine: an unreachable network
here just means the *real* repo-add attempt a few lines later hits the
same failure anyway, and that path was already wrapped (since Phase 3) in
the `{ ... } || ok=0` failure-isolation pattern that reports the tool as
skipped instead of aborting the whole run.

## 3. Exercise

Rebuild this phase from scratch, blind, in
`practice/12-language-toolchain-hardening/`. Two starter files are
provided there, each representing the *end of Phase 3* — i.e. working,
tested code that predates this phase's hardening:

- `libraries.sh` — has `omawsl_install_libraries`, with the apt package
  list as it stood before this phase (no curl/GD/intl/zip/mbstring `-dev`
  packages yet).
- `select-dev-language.sh` (plus a small `lib.sh` it sources for
  `omawsl_list_has`) — has `omawsl_install_language` and
  `omawsl_select_dev_language`, with the Elixir branch installing only
  `elixir`, not `erlang` first.

Your job:

1. In `libraries.sh`, extend the existing backslash-continued package
   list on `omawsl_install_libraries` so it also installs the five `-dev`
   packages PHP's curl, GD, intl, zip, and mbstring extensions each need
   to configure successfully when built from source. (The Walkthrough
   names all five and which extension needs which — don't just copy the
   list, make sure you can say why each one is there.) Don't remove or
   reorder anything already in the list.
2. In `select-dev-language.sh`, change the Elixir branch of
   `omawsl_select_dev_language` so that selecting `"Elixir"` in
   `OMAWSL_LANGUAGES` installs `erlang` via `omawsl_install_language`
   *before* it installs `elixir` — in the same call, not backgrounded or
   parallel. Every other branch (Ruby on Rails, Node.js, Go, PHP, Python,
   Rust, Java) should keep behaving exactly as it already does; selecting
   a language that isn't Elixir must not install erlang at all.

Keep both functions' names and signatures exactly as given
(`omawsl_install_libraries` takes no arguments; `omawsl_install_language`
takes one mise tool name; `omawsl_select_dev_language` takes no
arguments and reads `OMAWSL_LANGUAGES` from the environment) — the check
in the next section calls them by name.

**Stretch goals (not covered by `check.sh`):** the WSL2/WSLg zellij
workaround and the Azure CLI codename fallback are real parts of this
phase too. If you want the full picture, try writing
`ZELLIJ_SOCKET_DIR="/tmp/zellij-$(id -u)"` into a bashrc-style snippet
before an `exec zellij` line, and a codename-fallback check in front of an
apt-source-file write, using the Walkthrough above as your only reference.
These aren't graded here because one makes a real network call and the
other is only meaningfully observable inside a real interactive shell —
outside what a safe, repeatable automated check can verify.

## 4. Check

Run it from the practice directory:

```bash
bash practice/12-language-toolchain-hardening/check.sh
```

The check never runs a real `apt-get` or `mise` install — it replaces
`sudo` and `mise` with stand-ins that just record what they were asked to
do, then asserts on that recorded call log. You'll see one `PASS:` or
`FAIL:` line per behavior checked: the five new packages each being
present (and the original list staying intact), Elixir's selection
installing both erlang and elixir, erlang's call landing *before*
elixir's in the log, and a non-Elixir selection not touching erlang at
all.

A `FAIL:` line names the behavior that didn't match — e.g. "erlang must
be installed before elixir" — not a line number or a text diff. If you
see one, re-read the relevant `if` block you wrote and check the *order*
statements run in and *what* got appended to the existing list, rather
than guessing. A full pass means your `libraries.sh` and
`select-dev-language.sh` are behaviorally correct even if your line
formatting, comments, or variable names look nothing like the original —
that's expected and fine. You can diff your files against the real
`install/terminal/libraries.sh` and `install/terminal/select-dev-language.sh`
afterward purely as a style comparison, never as part of the grade.
