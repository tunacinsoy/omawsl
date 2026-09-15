# Lesson 17: Docker daemon proxy auto-configuration

## 1. Concept

Picture omawsl running on a corporate laptop. The company's network only
allows outbound traffic through a proxy server — a middleman host that
your machine's HTTP requests are routed through, usually because the
company wants to log, filter, or firewall direct internet access. Tools
that speak HTTP (`curl`, package managers, browsers) are taught about this
proxy through two environment variables, `HTTP_PROXY` and `HTTPS_PROXY`
(the value is a URL like `http://webproxy.example.com:8080`), plus an
optional `NO_PROXY` listing hosts that should be reached directly instead
(e.g. `localhost,127.0.0.1`). Historically some tools only recognized the
uppercase spelling and others only the lowercase one, so on a real corp
machine you'll often see both set to the same value, just to be safe.

Here's the trap: `docker pull` (and everything else that talks to a
container registry) is handled by a *daemon* — `dockerd`, a long-running
background process managed by systemd, not by the `docker` command you
type. When you set `export HTTP_PROXY=...` in your terminal, that
environment variable lives in *your shell's* process and everything your
shell launches (like `curl`). `dockerd` was started long before your
shell existed, by systemd, with its own environment — it has no idea your
shell later set `HTTP_PROXY`. So `curl` through the proxy works fine, but
`docker pull redis:7` hangs and eventually dies with a raw TCP timeout,
because the daemon tried to reach the registry directly and the corp
firewall silently dropped the connection. This is exactly what happened
on a real machine during this project's development (see the design doc
below) — Docker looked "installed and reachable" (`docker info` succeeds,
since that's a local socket call, not a network fetch), but the first
real pull failed confusingly deep into the install.

The fix is to tell systemd to inject `HTTP_PROXY`/`HTTPS_PROXY` into
`dockerd`'s own environment when it starts. systemd services are
configured by "unit files" (e.g. `/etc/systemd/system/docker.service`).
You could edit that file directly, but two things make that a bad idea:
package upgrades routinely overwrite the vendor's unit file, silently
discarding your edit; and if some other tool (or a company's own setup
script) also edits the same file, whoever writes last wins and the
earlier edit vanishes without a trace. systemd's answer to this is a
**drop-in directory**: for `docker.service`, that's
`/etc/systemd/system/docker.service.d/`. Any `*.conf` file systemd finds
in that directory is layered on top of the main unit file — you get to
add or override settings (like environment variables) in your own
small, separately-named file, without ever touching the original. This
is the same idea as a `.d`-suffixed config directory you'll see all over
Linux (`/etc/apt/apt.conf.d/`, `/etc/profile.d/`) — an "additive
extension point" instead of "edit the one shared file and hope nobody
else needed to."

Now the harder problem, and the reason this is its own lesson rather
than a one-line fix: omawsl runs on machines that already have a
corporate IT setup, and this project has a hard rule about that (from
`docs/config-safety.md`, built in an earlier phase): *never write into a
file omawsl doesn't exclusively own.* A corp IT manual might already have
told this user to drop their own proxy config into
`docker.service.d/http-proxy.conf` — the obvious, conventional filename.
If omawsl also wrote a file into that same directory, systemd would
merge both, and whichever one systemd happens to apply last would
silently win, with no error, no warning — just a config that quietly
does the wrong thing until someone burns an afternoon debugging it. So
this phase isn't just "detect a proxy and write a file." It's: detect a
proxy, check whether *anyone else* has already claimed this territory,
and — this is the important, easy-to-skip part — back off completely if
so, deferring entirely to whatever's already there rather than trying to
be clever about merging or overriding it.

Three small pieces make this safe:

1. **Detection** — read the proxy out of the environment, tolerating the
   upper/lowercase spelling inconsistency.
2. **Conflict detection** — before writing anything, check whether some
   *other* file in the drop-in directory already configures a proxy.
3. **Idempotent, exclusively-owned write** — if there's no conflict,
   write omawsl's own distinctly-named file (`omawsl-proxy.conf`, never
   the conventional `http-proxy.conf` a corp manual would use), but only
   if the content would actually change — so re-running the installer
   never needlessly restarts a working Docker daemon.

Two smaller pieces round out the feature, mentioned here so you see the
whole shape, though the hands-on exercise below focuses on the three
functions above: `bin/omawsl-sub/doctor.sh` gets a passive, read-only
check that reports `[PENDING]` if a proxy is present in the environment
but omawsl hasn't configured the daemon for it yet (e.g. the user picked
Engine mode before this feature existed) — doctor never writes anything,
it only tells you to re-run `install.sh`. And `uninstall/docker.sh`
removes exactly `omawsl-proxy.conf` and nothing else, so uninstalling
omawsl never touches a corp-owned file it never conflicted with in the
first place.

## 2. Walkthrough

All three functions below are real code from
`install/terminal/docker.sh` in this repo (the outline entry names
`install/lib.sh`, but that's not where they actually live — always
trust the repo over a summary). They were added in commit range
`e3a5509..66fb897`, driven by
`docs/superpowers/specs/2026-07-29-docker-daemon-proxy-autoconfig-design.md`.

### `omawsl_detect_proxy_env`

```bash
omawsl_detect_proxy_env() {
  local var="$1"
  local upper_val="${!var:-}"
  if [[ -n "$upper_val" ]]; then
    echo "$upper_val"
    return 0
  fi
  local lower_var; lower_var="$(echo "$var" | tr '[:upper:]' '[:lower:]')"
  echo "${!lower_var:-}"
}
```

Called as `omawsl_detect_proxy_env HTTP_PROXY`. The interesting bash
syntax is `${!var}` — this is *indirect expansion*: `var` holds the
*name* of another variable (the string `"HTTP_PROXY"`), and `${!var}`
means "look up the variable whose name is stored in `var`, and give me
its value" — one level of pointer-following, done entirely with string
manipulation, no separate data structure needed. It's how you write "a
function that reads whichever env var name I pass it" without a giant
`case` statement listing every possible name.

The `:-` after `!var` (i.e. `${!var:-}`) is the *default-value*
operator: "if this variable is unset, substitute an empty string
instead of erroring." That guard matters because the script runs under
`set -euo pipefail` — the `-u` specifically makes reading an *unset*
variable a hard error. Without `:-`, a machine with no `HTTP_PROXY` set
at all would crash the installer here instead of just yielding an empty
string, which is the whole point of this function (a non-corp machine
is the common case, and it must be a silent no-op).

The function prefers the uppercase form and only falls back to the
lowercase spelling (`tr '[:upper:]' '[:lower:]'` — translates every
uppercase character to lowercase) if the uppercase one is empty. This
exactly matches a real corp environment the author found during
development, which had both `HTTP_PROXY` and `http_proxy` set
identically — an either-convention tool landscape, so omawsl checks
both rather than picking one and guessing wrong.

An alternative you might reach for is a lookup table (an associative
array mapping `HTTP_PROXY` → `http_proxy`), but that's more code for the
same result — the relationship between the two spellings is entirely
mechanical (just case-folding), so computing the lowercase name is
simpler than tabulating it.

### `omawsl_docker_proxy_conflict`

```bash
omawsl_docker_proxy_conflict() {
  local dir="$1" own_file="$2"
  [[ -d "$dir" ]] || return 1
  local f
  for f in "$dir"/*.conf; do
    [[ -f "$f" ]] || continue
    [[ "$f" == "$own_file" ]] && continue
    grep -qE 'Environment=.*PROXY' "$f" 2>/dev/null && return 0
  done
  return 1
}
```

This answers one narrow question: "does some file *other than my own*
already configure a proxy in this directory?" Two arguments: the
drop-in directory, and the path to omawsl's own managed file (so the
loop can skip it — omawsl's own file setting a proxy doesn't count as a
conflict with itself).

`[[ -d "$dir" ]] || return 1` handles the case where the directory
doesn't exist yet at all (a totally fresh machine) — no conflict is
possible if there's nothing there yet, so this returns false (`1`)
immediately rather than looping over a directory that isn't there.

The loop, `for f in "$dir"/*.conf`, is bash's glob expansion — it
literally lists every file matching that pattern and iterates over each
path string. If no `.conf` files exist, bash (by default) leaves the
glob *unexpanded* — the loop body runs once with `f` literally holding
the string `"$dir/*.conf"`, a path that doesn't exist. That's exactly
why the next line, `[[ -f "$f" ]] || continue`, exists: it filters out
that unexpanded-glob case (the file "doesn't exist" check fails, so it
skips to the next iteration, which there isn't one — loop ends cleanly)
as well as skipping any non-regular-file match. Then `[[ "$f" ==
"$own_file" ]] && continue` skips omawsl's own file specifically.

Notice the deliberately shallow check: `grep -qE 'Environment=.*PROXY'`
just asks "does this file mention a `PROXY` environment assignment at
all" — it doesn't parse or understand *which* proxy setting, or
validate it's well-formed. That's a design decision explicit in the
design doc: omawsl only needs to decide whether to defer, never to
understand or merge what's already there. Trying to be smarter here
(parsing the existing value, deciding if it's "compatible") would only
add complexity and risk that omawsl guesses wrong about someone else's
config — "back off entirely" is simpler and strictly safer.

### `omawsl_configure_docker_proxy`

```bash
omawsl_configure_docker_proxy() {
  local dir="${1:-${OMAWSL_DOCKER_SERVICE_D_DIR:-/etc/systemd/system/docker.service.d}}"
  local own_file="$dir/omawsl-proxy.conf"

  local http_proxy_val https_proxy_val no_proxy_val
  http_proxy_val="$(omawsl_detect_proxy_env HTTP_PROXY)"
  https_proxy_val="$(omawsl_detect_proxy_env HTTPS_PROXY)"
  no_proxy_val="$(omawsl_detect_proxy_env NO_PROXY)"

  http_proxy_val="${http_proxy_val//%/%%}"
  https_proxy_val="${https_proxy_val//%/%%}"
  no_proxy_val="${no_proxy_val//%/%%}"

  if [[ -z "$http_proxy_val" && -z "$https_proxy_val" ]]; then
    return 0
  fi

  if omawsl_docker_proxy_conflict "$dir" "$own_file"; then
    echo "omawsl: found an existing proxy config elsewhere in $dir - leaving it as-is, not adding omawsl's own."
    if [[ -f "$own_file" ]]; then
      sudo rm -f "$own_file"
      sudo systemctl daemon-reload
      sudo systemctl restart docker
    fi
    return 0
  fi

  local lines=("[Service]")
  [[ -n "$http_proxy_val" ]] && lines+=("Environment=\"HTTP_PROXY=$http_proxy_val\"")
  [[ -n "$https_proxy_val" ]] && lines+=("Environment=\"HTTPS_PROXY=$https_proxy_val\"")
  [[ -n "$no_proxy_val" ]] && lines+=("Environment=\"NO_PROXY=$no_proxy_val\"")
  local content; content="$(printf '%s\n' "${lines[@]}")"

  local existing=""
  existing="$(sudo cat "$own_file" 2>/dev/null || true)"
  if [[ "$existing" == "$content" ]]; then
    return 0
  fi

  sudo mkdir -p "$dir"
  printf '%s\n' "$content" | sudo tee "$own_file" >/dev/null
  sudo chmod 0600 "$own_file"
  sudo systemctl daemon-reload
  sudo systemctl restart docker
  echo "omawsl: configured Docker daemon proxy from HTTP_PROXY/HTTPS_PROXY."
}
```

Read this top to bottom as a sequence of early exits — each guard
handles one case and returns before the more expensive/dangerous work
below it runs:

- **The path parameter.** `local dir="${1:-${OMAWSL_DOCKER_SERVICE_D_DIR:-/etc/systemd/system/docker.service.d}}"`
  chains two `:-` defaults: try the first positional argument; if that's
  empty, try the `OMAWSL_DOCKER_SERVICE_D_DIR` environment variable; if
  *that's* also empty, fall back to the real system path. This is the
  pattern that makes the function safely testable — a test (or, as
  you'll see below, this lesson's check script) can call
  `omawsl_configure_docker_proxy "/some/scratch/dir"` and know the
  function will never go near the real `/etc/systemd/...` path, without
  the function's everyday, real-install behavior changing at all. This
  is a recurring idiom across the whole codebase (you saw the same
  shape in `omawsl_docker_engine`, `omawsl_install_docker_ce`, etc. from
  earlier phases) — worth internalizing as *the* way to make a function
  that writes to a fixed real-world path unit-testable, rather than
  hardcoding the path and mocking the filesystem.

- **The percent-escaping.** `http_proxy_val="${http_proxy_val//%/%%}"`
  is bash's *global substitution* form of parameter expansion —
  `${var//pattern/replacement}` replaces every occurrence of `pattern`
  in `var` (a single `/` would replace only the first). Here it doubles
  every literal `%` character. This exists because of a systemd-specific
  gotcha found during development: systemd unit file directives (like
  `Environment=`) treat `%` as the start of a "specifier" (a
  `%`-prefixed placeholder systemd expands, similar in spirit to a shell
  variable), so a literal `%` in a proxy URL (which shows up in
  practice — a percent-encoded backslash in a Windows-domain username,
  e.g. `DOMAIN%5Cuser`) could get mangled or rejected by systemd unless
  escaped to `%%` first. This is exactly the kind of bug that never
  shows up in a synthetic test with clean proxy URLs — it was added in a
  later fix-up commit after someone hit it with a real corp URL.
  Escaping an empty string is harmless, so this runs unconditionally,
  even before the "no proxy at all" check below — simpler than adding a
  separate guard.

- **The no-proxy early return.** If neither `HTTP_PROXY` nor
  `HTTPS_PROXY` resolved to anything, return immediately — the common,
  silent, non-corp-machine case.

- **The conflict back-off.** If `omawsl_docker_proxy_conflict` says
  something else already owns this directory, print one informational
  line and stop — but first, if omawsl's *own* file happens to already
  exist (e.g. a proxy was configured on an earlier run, and *since
  then* a corp-managed file appeared, or the user just installed one by
  hand), remove it and restart the daemon so that stale, now-redundant
  config doesn't linger and potentially conflict with the newly
  discovered file. Removing a no-longer-appropriate file, then reloading
  systemd so the removal actually takes effect, is a real fix from a
  later commit in this range (`66fb897`) — the first version removed
  the file but forgot the reload/restart, so the stale environment
  variable kept being injected into `dockerd` until something else
  happened to bounce the daemon.

- **Building the content.** `lines=("[Service]")` starts a bash *array*
  with one element; `lines+=(...)` appends more, each guarded by
  `[[ -n "$val" ]] &&` so an empty `NO_PROXY` doesn't produce a blank
  `Environment="NO_PROXY="` line. `printf '%s\n' "${lines[@]}"` — the
  `"${lines[@]}"` expansion is bash's "give me every array element as
  its own separate word," and `printf` with a single `%s\n` format
  applied repeatedly to each argument turns that into one line per
  array element. The alternative — building the string with `+=`
  concatenation and manual `\n`s — works too, but the array form keeps
  each `Environment=` line's construction (and its own presence/absence
  guard) visually separate and easy to add a fourth variable to later.

- **The idempotency check.** `sudo cat "$own_file" 2>/dev/null || true`
  reads back whatever's currently on disk (empty string if the file
  doesn't exist yet — `2>/dev/null` swallows the "no such file" error
  message, and `|| true` stops that failed `cat` from tripping `set -e`
  and killing the whole script). If that matches the freshly-built
  content byte-for-byte, return immediately — **no write, no daemon
  restart.** This is the detail that makes it safe to run
  `install.sh` over and over: without this check, every re-run would
  rewrite an identical file and bounce a perfectly healthy Docker
  daemon for no reason, which on a machine mid-`docker run` would be a
  real, disruptive regression. Note it uses `sudo cat`, not a plain
  `cat` — a fix from the same later commit, because a bare `cat` on a
  file that (after the next line) ends up `chmod 0600`'d (owner-only
  readable) could itself fail and abort the whole sourced install under
  `set -e`.

- **The actual write**, only reached if content differs: create the
  directory if needed, pipe the content through `sudo tee` (writes to a
  root-owned path — this whole function needs `sudo` because
  `/etc/systemd/system/...` isn't writable by a normal user), lock it
  down to `chmod 0600` (this file can carry proxy credentials embedded
  in the URL, so it shouldn't be world-readable), then
  `daemon-reload` (systemd re-reads unit files from disk) followed by
  `restart docker` (the running daemon process needs to actually
  restart to pick up the new environment — a reload alone doesn't do
  that for `Environment=` changes).

One thing this function deliberately does *not* do: validate that the
proxy URL is well-formed, or that the proxy is actually reachable. That
mirrors the same "just relay what the environment says, don't second-
guess it" philosophy as `omawsl_docker_proxy_conflict`'s shallow grep —
outside this feature's scope per the design doc's "Non-scope" section.

### Where it's wired in, and its two smaller siblings

`omawsl_configure_docker_proxy` is called from `omawsl_docker_engine`
right after `omawsl_install_docker_ce` — Engine mode only; Docker
Desktop's proxy setting lives in Windows-side GUI settings, unreachable
from a WSL script, so that mode is untouched (same boundary this
project has respected since Phase 2). Have a quick look at
`omawsl_doctor_docker_proxy_pending` in `bin/omawsl-sub/doctor.sh` and
`omawsl_uninstall_docker` in `uninstall/docker.sh` — you'll notice both
reuse `omawsl_detect_proxy_env` and `omawsl_docker_proxy_conflict`
directly rather than re-implementing detection or conflict logic, and
the uninstall path's cleanup is a single `rm -f
"$docker_service_d_dir/omawsl-proxy.conf"` — exactly, and only, the one
file this feature ever creates.

## 3. Exercise

Close this lesson and, from scratch, write
`practice/17-docker-daemon-proxy-autoconfig/docker-proxy.sh`. This file
is a **library** meant to be `source`d by other scripts (like the real
`install/terminal/docker.sh` is) — it should define functions only, with
no unconditional dispatcher/`main` call at the bottom.

Implement exactly these three functions, matching the real interface so
they stay independently testable:

- **`omawsl_detect_proxy_env <VAR>`** — given an uppercase variable name
  (e.g. `HTTP_PROXY`), print its value if set and non-empty; otherwise
  print the value of its lowercase form (`http_proxy`); otherwise print
  an empty string. Must not error under `set -u` when neither form is
  set.

- **`omawsl_docker_proxy_conflict <dir> <own_file>`** — return success
  (exit 0) if any `*.conf` file in `<dir>`, other than `<own_file>`
  itself, contains a line matching `Environment=.*PROXY`. Return failure
  (exit 1) if `<dir>` doesn't exist, is empty, or only `<own_file>`
  itself (or nothing) mentions a proxy.

- **`omawsl_configure_docker_proxy [dir]`** — `dir` defaults to
  `${OMAWSL_DOCKER_SERVICE_D_DIR:-/etc/systemd/system/docker.service.d}`
  when not passed explicitly (keep this fallback chain — it's what lets
  a caller point this at a scratch directory without changing the
  function's real-world default). The managed file is always
  `$dir/omawsl-proxy.conf`. Behavior:
  1. Resolve `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY` via your
     `omawsl_detect_proxy_env`. If neither `HTTP_PROXY` nor
     `HTTPS_PROXY` resolved to anything, do nothing and return
     successfully.
  2. If `omawsl_docker_proxy_conflict` says another file already
     configures a proxy in `dir`, print an informational line and
     back off — remove `own_file` (via `sudo rm -f`, followed by
     `sudo systemctl daemon-reload` and `sudo systemctl restart
     docker`, but *only if* it existed) and return, without writing
     anything of your own.
  3. Otherwise build the drop-in content: a `[Service]` line, then one
     `Environment="HTTP_PROXY=..."`-style line per resolved variable
     that's non-empty (omit the line entirely for anything that
     resolved empty).
  4. Compare that content against what's already on disk at
     `own_file` (via `sudo cat ... 2>/dev/null || true` — don't let a
     missing file abort the script). If identical, return without
     writing or restarting anything.
  5. Otherwise: `sudo mkdir -p` the directory, write the content via
     `sudo tee`, `sudo chmod 0600` it, then `sudo systemctl
     daemon-reload && sudo systemctl restart docker`, and print a
     one-line confirmation.

You don't need to escape `%` characters or wire this into
`omawsl_docker_engine`/`doctor.sh`/`uninstall/docker.sh` for the check
to pass — those are real refinements from the original commit history
(worth doing afterward, as a stretch goal, once your version passes the
check) but aren't required for a passing solution here. Focus on getting
the detection → conflict-check → idempotent-write sequence right.

## 4. Check

Run the check from the repo root:

```bash
bash practice/17-docker-daemon-proxy-autoconfig/check.sh
```

It prints one `PASS`/`FAIL` line per behavior it verifies — proxy
detection (upper/lowercase fallback, empty case), the conflict/back-off
case (an existing other file's proxy config is left untouched and
omawsl doesn't write its own file over it), and the written drop-in's
content and format when there's no conflict, plus a check that a
second, identical call doesn't rewrite the file or restart anything.

The check never touches your real system: it points `dir` at a
throwaway temporary directory for every call, and it replaces `sudo`
with a stand-in function for the duration of the check, so nothing it
does can reach `/etc/systemd/system/docker.service.d` or actually
restart your machine's Docker daemon, no matter what path your solution
defaults to internally.

If something fails, the `FAIL:` line tells you which *behavior* didn't
match (e.g. "back-off case wrote its own file anyway" or "drop-in
content didn't include the HTTPS_PROXY line") — not which lines of code
differ from the original. A passing check means your solution is
behaviorally correct even if you structured the bash differently (a
`case` instead of a chain of `[[ ]]` tests, a different variable name,
whatever) — that's fine and expected. Once it passes, you can `diff`
your `docker-proxy.sh` against the real
`install/terminal/docker.sh` purely as a style comparison, never as the
grade.
