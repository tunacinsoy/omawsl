# Phase 16: upstream-install-hardening

## 1. Concept

Phases 1-15 built a habit: when a tool has no Ubuntu package, install it
straight from the project's own GitHub release instead of piping some
random `curl | bash` one-liner into your shell. omawsl already did this for
zellij and starship. This phase is about what happens once that pattern
meets three kinds of reality it hadn't accounted for yet.

**Reality 1: "it's in apt" is a fact about one Ubuntu release, not about
Ubuntu.** fastfetch and lazygit were originally installed via plain
`apt-get install fastfetch lazygit ...` in the same line as fzf, ripgrep,
bat, and eight other packages. That worked when it was tested — on Ubuntu
26.04, a newer release than the 24.04 LTS floor this project actually
promises to support. Checked against Launchpad's package history:
fastfetch's Ubuntu package doesn't exist before 25.04, and lazygit's
doesn't exist before 25.10. On a real 24.04 machine, `apt-get install
<12-package list>` doesn't skip the two names it can't resolve — apt
resolves the *entire* install line as one atomic operation, and one
unresolvable package name aborts the whole command. So on the most common
real target (24.04 LTS), that one line would have silently taken down
fzf, ripgrep, bat, eza, zoxide, plocate, `apache2-utils`, fd-find, gh,
btop, jq, and bash-completion — twelve unrelated, perfectly-available
packages — because of two names apt couldn't find. The fix isn't "add a
version check" — it's "stop trusting apt's universe repo to carry these
two at all," installing them the same way zellij and starship already
are: fetched directly from the tool's own GitHub Releases.

**Reality 2: `command -v` finding nothing doesn't mean the thing isn't
there.** omawsl reaches across the WSL/Windows boundary by shelling out to
`cmd.exe` (Windows' Command Prompt) to ask Windows for the logged-in
user's profile path. That only works if `cmd.exe` is reachable — normally
true, because WSL2 appends the Windows `PATH` onto the Linux one by
default. But `/etc/wsl.conf` has a setting, `appendWindowsPath`, that
corporate-managed WSL images commonly turn off (for isolation reasons)
without disabling WSL's Windows-interop mechanism itself. On such a
machine, `cmd.exe` still runs fine if you invoke it by its full path —
it's only missing from `$PATH`, so `command -v cmd.exe` reports nothing
and every feature built on top of it (Windows Terminal color sync, the
native VS Code extension install) silently skips itself. The fix is a
fallback to `cmd.exe`'s one fixed, well-known location on disk
(`/mnt/c/Windows/System32/cmd.exe` — WSL2 always mounts the Windows `C:`
drive at `/mnt/c`), used only when the `$PATH` lookup comes up empty.

**Reality 3: an anonymous API call is still an API call someone can run
out of.** Phase 8 built a "check every installed tool's version against
GitHub" feature. GitHub's REST API is free to call without logging in —
but capped at 60 requests per hour, counted **per source IP address**, not
per person. Behind a typical home router that's rarely a problem. Behind a
shared corporate NAT gateway — where every developer's laptop in the
building shares one public IP — that 60/hour budget can be gone before
your own request ever goes out, and every GitHub-based check reports
"unknown" even though GitHub itself is perfectly reachable. Authenticating
the same request (`Authorization: Bearer <token>`, a normal HTTP header
that proves who's asking) raises the cap to 5000/hour, counted per token
instead of per IP. This is what "rate limiting" means in general: an API
protects itself by refusing requests once a caller has made "too many" in
some window, and the window/limit is usually far more generous once the
caller identifies itself — which is exactly why so many CLIs (`gh`, `aws`,
`docker`) nudge you to log in even for read-only operations.

This phase makes all three of those cracks visible and closes them.

## 2. Walkthrough

### fastfetch/lazygit/lazydocker: same-shaped install, different asset names

The pattern (already established for zellij and starship) is: hit the
tool's GitHub Releases API to find the current version, build the exact
download URL for this machine's CPU architecture, fetch and install the
binary. Here's `install/terminal/apps-terminal.sh`'s shared helper:

```bash
omawsl_github_binary_install() {
  local url="$1" binary="$2"
  curl -fsSL "$url" | tar -xz -C /tmp "$binary"
  sudo install -m 0755 "/tmp/$binary" "/usr/local/bin/$binary"
  rm -f "/tmp/$binary"
}
```

`curl -fsSL <url>` streams the release tarball straight into `tar -xz -C
/tmp <binary>` — no intermediate file for the whole archive, just the one
binary extracted out of it into `/tmp`. `sudo install -m 0755 ... /usr/local/bin/...`
copies that binary into a system-wide `PATH` directory with the right
executable permission bits, and the final `rm -f` cleans up `/tmp`. One
function, reused for every tool that ships a plain binary in a `.tar.gz`.

What differs per tool is the *URL* — and getting that right means reading
each project's actual release filenames instead of assuming they all
match one template. lazygit's:

```bash
omawsl_lazygit_arch() {
  case "$(dpkg --print-architecture)" in
    arm64) echo "arm64" ;;
    *) echo "x86_64" ;;
  esac
}

omawsl_lazygit_install_steps() {
  local version
  version="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -Po '"tag_name": "v\K[^"]+')"
  local arch
  arch="$(omawsl_lazygit_arch)"
  omawsl_github_binary_install "https://github.com/jesseduffield/lazygit/releases/download/v${version}/lazygit_${version}_linux_${arch}.tar.gz" lazygit
}
```

`dpkg --print-architecture` reports Debian/Ubuntu's own architecture name
(`amd64` or `arm64`) — but lazygit's release filenames don't use Debian's
naming, they use `x86_64`/`arm64`, so this function's whole job is
translating one vocabulary into another. `grep -Po '"tag_name": "v\K[^"]+'`
pulls the version number out of the API's JSON response without a JSON
parser: `-P` turns on Perl-compatible regex (needed for `\K`, which means
"forget everything matched so far — start the actual reported match
here"), so the pattern matches the literal text `"tag_name": "v` and then
resets, so only what comes after the `v` (up to the closing quote) is
printed. `-o` prints only the matched portion, not the whole line. This
avoids depending on `jq` (a real JSON parser) being installed — a
deliberate, lighter-weight choice for a script that runs before most of
the system is set up. lazygit's asset filename embeds the version number
(`lazygit_0.63.1_linux_x86_64.tar.gz`), so there's no way around resolving
it first — unlike zellij, whose release page always has a fixed
`/releases/latest/download/<name>` URL that redirects to whatever's
current, needing no separate lookup at all.

lazydocker looks almost identical — except its filename capitalizes `Linux`:

```bash
omawsl_lazydocker_install_steps() {
  local version
  version="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazydocker/releases/latest | grep -Po '"tag_name": "v\K[^"]+')"
  local arch
  arch="$(omawsl_lazydocker_arch)"
  omawsl_github_binary_install "https://github.com/jesseduffield/lazydocker/releases/download/v${version}/lazydocker_${version}_Linux_${arch}.tar.gz" lazydocker
}
```

Before this phase, lazydocker was the one holdout still installed via its
own upstream script:

```bash
# old version
omawsl_lazydocker_install_steps() {
  curl -fsSL https://raw.githubusercontent.com/jesseduffield/lazydocker/master/scripts/install_update_linux.sh | bash
}
```

That script's *own* internal logic hits the GitHub API too — but
unauthenticated, and outside omawsl's control, so when it 403'd under rate
limiting in a devcontainer, there was nothing in this repo to fix. Piping
someone else's script into `bash` also means the exact steps aren't
visible in *this* codebase at all — you're trusting whatever that URL
serves today. Rewriting it to the same direct-download shape as
zellij/lazygit made it both auditable and independently fixable.

fastfetch is the odd one out — its release ships a `.deb` package, not a
bare binary, and its filename has no version number in it at all:

```bash
omawsl_fastfetch_arch() {
  case "$(dpkg --print-architecture)" in
    arm64) echo "aarch64" ;;
    *) echo "amd64" ;;
  esac
}

omawsl_fastfetch_install_steps() {
  local arch
  arch="$(omawsl_fastfetch_arch)"
  local tmp_deb
  tmp_deb="$(mktemp --suffix=.deb)"
  curl -fsSL -o "$tmp_deb" "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${arch}.deb"
  sudo apt-get install -y "$tmp_deb"
  rm -f "$tmp_deb"
}
```

Two more differences worth noticing, both taken straight from reading
fastfetch's actual releases page rather than assuming it matches the other
two: its architecture names are `aarch64`/`amd64`, not `arm64`/`x86_64`
(three tools, three different arch-naming conventions — there is no
universal standard here, only what each maintainer happened to pick); and
`apt-get install <path-to-.deb>` is used instead of `omawsl_github_binary_install`,
because fastfetch links against real system libraries (Wayland, X11,
D-Bus) that a bare binary copy wouldn't pull in — `apt install ./foo.deb`
resolves that package's declared `Depends:` from the regular Ubuntu
archive, the same dependency resolution a normal `apt-get install
fastfetch` would have done, just pointed at a local file instead of a
repository name.

**Why this way and not another:** an alternative would be to keep
fastfetch/lazygit in the apt list but wrap that one line in `|| true` so a
failure doesn't abort the rest. That would silently produce a machine with
no fastfetch/lazygit at all on any pre-25.04/25.10 Ubuntu release, with no
signal to the user that anything is missing — worse than either failing
loudly or installing successfully via GitHub.

### cmd.exe: PATH lookup with a fixed-path escape hatch

`install/lib.sh` gained one new function, used by the existing
`omawsl_windows_userprofile`:

```bash
omawsl_resolve_cmd_exe() {
  if command -v cmd.exe &>/dev/null; then
    echo "cmd.exe"
    return 0
  fi
  local fallback="${OMAWSL_CMD_EXE_FALLBACK:-/mnt/c/Windows/System32/cmd.exe}"
  [[ -x "$fallback" ]] && echo "$fallback"
}
```

`command -v cmd.exe` is the normal, cheap way to ask "is there something
named `cmd.exe` reachable on `$PATH` right now?" — it prints the resolved
path and exits 0 if so, and prints nothing and exits nonzero otherwise,
which is exactly what the `if` here is testing. When that fails, rather
than giving up, the function tries one specific, always-true-on-real-WSL2
location instead: `/mnt/c/Windows/System32/cmd.exe`. `${OMAWSL_CMD_EXE_FALLBACK:-...}`
is bash's "default value" parameter expansion — use the environment
variable's value if it's set (and non-empty), otherwise fall back to the
literal path after the `:-`. That's not there for production use; it
exists purely so a test can point the fallback at a path that
*deliberately* doesn't exist, without needing a real Windows filesystem to
verify the "fallback is also missing" branch. `[[ -x "$fallback" ]]` is a
real safety check, not just an existence test — `-x` confirms the path
both exists *and* is executable, so a fallback that's present but somehow
not runnable doesn't get handed back as if it were usable. Every caller —
`omawsl_windows_userprofile`, and, elsewhere in this commit, the
VS Code/Cursor theme sync path — now calls `omawsl_resolve_cmd_exe` once
and uses whatever path it returns, instead of hardcoding the bare name
`cmd.exe` and assuming `$PATH` will always resolve it:

```bash
omawsl_windows_userprofile() {
  local cmd_exe
  cmd_exe="$(omawsl_resolve_cmd_exe)" || return 1
  command -v wslpath &>/dev/null || return 1
  local win_path
  win_path="$("$cmd_exe" /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r\n')"
  [[ -n "$win_path" ]] || return 1
  wslpath -u "$win_path"
}
```

**Why this way and not another:** an alternative would be to just always
call the fixed `/mnt/c/...` path and skip the `$PATH` lookup entirely.
That would work on real WSL2 too — but it throws away the one thing
`command -v` gives you for free: if a user has genuinely customized where
`cmd.exe` resolves to (an unusual setup, but not impossible), the `$PATH`
lookup respects that, while a hardcoded path would silently ignore it.
Try the flexible lookup first, fall back to the one thing you *know* is
almost always true, only when the flexible path comes up empty.

### Authenticating the GitHub version checks

`bin/omawsl-sub/orphan-tools.sh` is Phase 8's registry of tools with no
native updater — for each one, it calls GitHub's API to ask "what's the
latest version?" and compares it against what's installed. Before this
phase, every one of those calls was anonymous:

```bash
# old version
omawsl_orphan_latest_from_github() {
  local repo="$1"
  local tag
  tag="$(curl -fsSL "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null)" || tag=""
  echo "${tag#v}"
}
```

The fix adds a small chain of "do we have a token anywhere?" logic in
front of every such call:

```bash
omawsl_orphan_github_token() {
  if [[ -n "${GH_TOKEN:-}" ]]; then
    echo "$GH_TOKEN"
  elif [[ -n "${GITHUB_TOKEN:-}" ]]; then
    echo "$GITHUB_TOKEN"
  elif command -v gh &>/dev/null; then
    gh auth token 2>/dev/null || true
  fi
}

omawsl_orphan_github_auth_args() {
  local token; token="$(omawsl_orphan_github_token)"
  [[ -n "$token" ]] && printf '%s\n' "-H" "Authorization: Bearer $token"
  return 0
}
```

`omawsl_orphan_github_token` tries three sources, in order, and returns
the first one that has something: the `$GH_TOKEN` environment variable,
then `$GITHUB_TOKEN` (both are names real GitHub tooling and CI systems
already read, so a machine that has either set for some other reason gets
this for free), and finally — if neither is set but the `gh` CLI is
installed — asks `gh` itself for whatever token it's already logged in
with via `gh auth token`. `${GH_TOKEN:-}` (not just `$GH_TOKEN`) matters
here specifically because this file runs under `set -u`: referencing an
unset variable directly would be a hard error, but the `:-` expansion
supplies an empty-string default instead, so the `[[ -n ... ]]` test can
safely ask "is this non-empty?" without crashing when the variable was
never set at all. If none of the three sources produce anything, the
function prints nothing — deliberately not an error, since "no token
available" is an expected, common case that should just mean "fall back
to unauthenticated," not "abort."

`omawsl_orphan_github_auth_args` turns that token into the exact `curl`
arguments needed to send it: `-H "Authorization: Bearer <token>"` is
curl's flag for adding a custom HTTP header, and `Authorization: Bearer
<token>` is the standard HTTP scheme for "here's my credential" (the same
shape used by countless other APIs, not something GitHub invented). It's
factored into its own function — rather than being inlined into every
caller — specifically so the two GitHub-lookup functions below build that
header identically instead of two near-duplicate copies drifting apart
over time.

The lookup function itself changes shape to consume that array:

```bash
omawsl_orphan_latest_from_github() {
  local repo="$1"
  local -a auth_args=()
  while IFS= read -r arg; do auth_args+=("$arg"); done < <(omawsl_orphan_github_auth_args)
  local tag
  tag="$(curl -fsSL "${auth_args[@]}" "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null)" || tag=""
  echo "${tag#v}"
}
```

`while IFS= read -r arg; do auth_args+=("$arg"); done < <(...)` is a bash
idiom worth slowing down on: `omawsl_orphan_github_auth_args` prints each
argument on its own line (`-H` on one line, `Authorization: Bearer
<token>` — which itself contains spaces — on the next), and this loop
reads it back one line at a time into an array, preserving each line as
exactly one array element regardless of spaces inside it. The tempting
shortcut, `auth_args=($(omawsl_orphan_github_auth_args))`, would *not*
work here: bash word-splits an unquoted `$(...)` on whitespace by
default, so `"Authorization: Bearer abc123"` would get split into three
separate array elements (`Authorization:`, `Bearer`, `abc123`) instead of
staying together as one `-H` argument's value — silently sending curl a
mangled header. `${auth_args[@]}` (unquoted... except it *is* effectively
quoted-safe here because each element was captured as a whole line) then
expands back out to zero, one, or two separate `curl` arguments depending
on whether a token was found — when the array is empty, `curl` just runs
with `-fsSL <url>` and nothing else, i.e. plain unauthenticated, exactly
the same request this function always made before.

The second half of this commit is an unrelated but real bug fix in the
same file: `aws/aws-cli` doesn't publish GitHub *Releases* at all, only
plain Git tags, so `releases/latest` always 404'd for it regardless of
authentication. The fix adds a second lookup function against the `/tags`
endpoint instead, and — since tags aren't guaranteed to come back in
version order — collects every semver-shaped tag name and picks the
highest with `sort -V` (a "version sort," which understands that `1.10.0`
comes after `1.9.0`, unlike a plain alphabetical sort).

**Why this way and not another:** an alternative would be to require a
token — refuse to run the version check at all without one. That would
turn a "sometimes rate-limited on some networks" problem into "broken by
default for anyone who's never authenticated to anything," which is worse
for the common case (a fresh machine, no corporate proxy, well under
60/hour) to fix a problem that's real but not universal. Opportunistic
auth — use a token if one is trivially available, silently degrade to
what already worked otherwise — fixes the shared-NAT case without
breaking the simple one.

## 3. Exercise

Close this lesson and, in `practice/16-upstream-install-hardening/install-hardening.sh`,
implement the following functions from scratch. This is a narrower slice
than the full original — you're writing the *decision logic* (which path,
which URL, which headers), not the actual download/install commands
themselves, so nothing here should perform a real install, a real `sudo`,
or a real network request when you're done testing it by hand.

- `omawsl_resolve_cmd_exe` — echo the resolved path to `cmd.exe`: prefer
  whatever `command -v cmd.exe` finds on `$PATH`; if that fails, fall back
  to `${OMAWSL_CMD_EXE_FALLBACK:-/mnt/c/Windows/System32/cmd.exe}`, but
  only if that fallback path exists *and* is executable. Produce no output
  and a nonzero exit if neither works.

- `omawsl_orphan_github_token` — echo a token from, in order: `$GH_TOKEN`,
  then `$GITHUB_TOKEN`, then `gh auth token` (only if the `gh` command is
  reachable). Echo nothing if none of those produce anything — this must
  not error under `set -u` when the environment variables are simply
  unset.

- `omawsl_orphan_github_auth_args` — given whatever
  `omawsl_orphan_github_token` returns, print the `curl` arguments needed
  to send it as a Bearer auth header, one argument per line (so a caller
  can read them back into an array without word-splitting), or nothing at
  all if there's no token.

- `omawsl_lazygit_arch`, `omawsl_lazydocker_arch`, `omawsl_fastfetch_arch`
  — each maps `dpkg --print-architecture`'s output (`arm64` or anything
  else) to that specific tool's own release-asset architecture naming.
  Look at each tool's actual GitHub releases page (or re-read the
  Walkthrough above) rather than assuming all three use the same names —
  they don't.

- `omawsl_lazygit_release_url` and `omawsl_lazydocker_release_url` — each
  should: build the auth args via the functions above, `curl` the
  matching GitHub API `releases/latest` endpoint for that repo
  (`jesseduffield/lazygit` / `jesseduffield/lazydocker`), extract the
  version from the JSON response's `tag_name` field, and echo the full
  download URL for the current architecture. Pay attention to the exact
  filename shape for each — they are not identical (hint: it's not just
  the repo name that differs).

- `omawsl_fastfetch_release_url` — echo fastfetch's download URL for the
  current architecture. Unlike the two functions above, this one needs no
  API call and no version number at all — work out why from the
  Walkthrough before you write it.

## 4. Check

Run `practice/16-upstream-install-hardening/check.sh`. It never makes a
real network request or resolves a real GitHub token, even when your
implementation genuinely calls `curl` and `gh` by name — the check
replaces `curl` with a stand-in that logs what it was called with and
hands back a canned response, and shadows `gh` the same way for the
"no token available" cases, so nothing here can ever hit a real rate
limit or need real network access to run.

Each line is `PASS:` or `FAIL:` for one specific behavior — a failure
tells you *what* didn't match (which URL, which header, which
architecture mapping), not which lines of your code differ from the
original. A passing check means your implementation is behaviorally
correct even if it's structured completely differently from the
Walkthrough's version — different variable names, a different function
split, `jq` instead of `grep -Po`, all fine. Only after it passes, if
you want to compare style choices (not correctness), look at the real
`omawsl_lazygit_install_steps`/`omawsl_lazydocker_install_steps` in
`install/terminal/apps-terminal.sh` and
`omawsl_orphan_github_token`/`omawsl_orphan_github_auth_args` in
`bin/omawsl-sub/orphan-tools.sh`.
