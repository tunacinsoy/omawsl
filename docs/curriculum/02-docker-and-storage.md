# Lesson 2: Docker and Storage

## 1. Concept

Phase 1 gave omawsl its skeleton: an orchestrator (`install.sh`) that walks
through a fixed list of small, sourced sub-scripts, a `lib.sh` of shared
helpers, and a first-run prompt system that asks the user some questions up
front and remembers the answers. Phase 2 is the first phase that has to
make a real *choice* based on one of those answers, and it introduces two
ideas every later phase reuses.

**Idea 1: branch on a user choice, and treat one option as "nothing to
install."** omawsl asks the user how they want Docker set up:
`OMAWSL_DOCKER_MODE` is either `"Docker Engine only, inside WSL
(recommended)"` or `"Docker Desktop for Windows"`. Docker Desktop is a
Windows application with its own installer, running outside WSL entirely -
omawsl cannot install it (it can't reach across into Windows), and
shouldn't try. So the two branches aren't symmetric: one branch really
installs something (`docker-ce`, natively, inside WSL); the other branch
never installs anything at all. It just checks: is `docker` already
reachable (meaning the user finished Docker Desktop's own setup and turned
on WSL integration)? If yes, there's nothing to do. If no, it prints a
message and defers - it adds an item to a checklist the user sees *before*
the WSL-side install even starts, so they know a Windows-side step is
waiting on them, then proceeds anyway if they choose to.

This is the **detect-and-defer pattern**: before installing something,
check if it's already there through some other path, and if a *user*, not
the installer, needs to go do something outside the installer's reach,
say so clearly and move on rather than trying (and failing) to force it.
You'll see this same shape again for VS Code and Cursor in a later phase.

**Idea 2: local dev databases as containers, not native packages.** The
user can also pick MySQL, Redis, and/or PostgreSQL as "storage." Phase 1
already showed you `apt-get install some-package` as an install strategy.
Storage engines don't use that strategy here - they're started as Docker
containers instead. Two reasons: a database installed as a system package
comes with systemd units, config files under `/etc`, and a data directory
that's a pain to fully remove; a container is one `docker run` away from
existing, and one `docker rm -v` away from being gone, with the actual data
living in a Docker-managed *volume* rather than scattered across the
filesystem. It also means "MySQL 8" and "Postgres 16" are exactly the
versions the container image says they are, not whatever Ubuntu's apt
repos happen to carry that month.

A word on two terms this lesson leans on hard, if they're new to you:

- **A Docker image** is a frozen, read-only bundle of a filesystem plus
  metadata (what command to run, what ports it expects) - think of it as a
  installable template, published to a registry like Docker Hub (e.g.
  `mysql:8` or `redis:7`). **A container** is a running (or stopped)
  *instance* of an image - an isolated process with its own filesystem
  view, network namespace, etc, layered on top of that image. You can
  start many containers from the same image; each one is independent.
  "Install Docker" really means "install a daemon (`dockerd`) plus a CLI
  (`docker`) that can pull images and run containers from them."
- **Idempotent** means "safe to run more than once, with the same result
  as running it once." `apt-get install jq` is idempotent - installed once,
  it just says "already the newest version" on a second run. `docker run
  --name foo ...` is *not* idempotent by default - Docker errors out with a
  name collision if a container called `foo` already exists. Every install
  script in omawsl has to be safe to re-run (the user might run
  `install.sh` again after fixing something), so anywhere the underlying
  tool isn't naturally idempotent, the script has to add its own guard.
  You'll see exactly that guard in `omawsl_ensure_container` below.

The Concept doesn't stop at "the code we shipped." This phase's plan
records a **Task 7: manual end-to-end verification** - a step deliberately
excluded from the automated test suite, run once by a human against a real
WSL machine, real `sudo`, and Docker's real apt repository. All of Tasks
1-6 passed their (stubbed) automated tests before Task 7 ever ran. Task 7
still found two real bugs. That's the other half of this lesson: what kind
of bug a stubbed test suite structurally *cannot* catch, and why "green
tests" was never the actual finish line for this phase.

## 2. Walkthrough

### `omawsl_docker_reachable` (`install/lib.sh`)

```bash
omawsl_docker_reachable() {
  command -v docker &>/dev/null
}
```

One line, but it's shared by two different call sites in this phase
(`windows-prereq-checklist.sh` and `docker.sh` itself), which is exactly
why it lives in the shared `lib.sh` instead of being duplicated. `command
-v docker` asks the shell "is there anything named `docker` I could run
right now" (a real file on `$PATH`, or - relevant later, in this same
check script's own tests - a shell function of that name) and exits 0 if
so. `&>/dev/null` throws away whatever it would have printed (we only
care about the exit status), and the function's own exit status becomes
whatever `command -v` returned - no explicit `return` needed, since a bash
function's exit status defaults to its last command's.

An alternative would've been `which docker`, but `command -v` is the
POSIX-portable, builtin-preferring choice - `which` is technically an
external program that may or may not exist on a minimal system, whereas
`command` is a shell builtin guaranteed to be there.

### `omawsl_docker_desktop` and the dispatcher (`install/terminal/docker.sh`)

```bash
OMAWSL_DOCKER_MODE_DESKTOP="Docker Desktop for Windows"

omawsl_docker_desktop() {
  if omawsl_docker_reachable; then
    return 0
  fi

  echo "omawsl: Docker Desktop was selected but 'docker' isn't reachable yet."
  echo "Install Docker Desktop and enable WSL integration for this distro - see docs/windows-setup.md#docker-desktop."
  echo "Nothing else to do here for now; re-run install.sh after completing that step."
}

omawsl_docker() {
  if [[ "${OMAWSL_DOCKER_MODE:-}" == "$OMAWSL_DOCKER_MODE_DESKTOP" ]]; then
    omawsl_docker_desktop
  else
    omawsl_docker_engine
  fi
}
```

Notice what `omawsl_docker_desktop` never does: it never calls `apt-get`,
never calls `docker-ce` install logic, nothing. Its entire job is the
detect-and-defer check from the Concept section. If the daemon's already
reachable (the user did their Windows-side homework), it's a silent no-op.
If not, it's three lines of `echo` and nothing else - a real Windows-side
prerequisite, already flagged earlier in the run by
`windows-prereq-checklist.sh`, so this is just a reminder if the user
plowed ahead anyway.

The dispatcher, `omawsl_docker`, is a single `if`/`else` on one exact
string comparison. Look closely at which branch is the `else`: **anything
that isn't the literal string `"Docker Desktop for Windows"` - including
an *unset* `OMAWSL_DOCKER_MODE`** - falls into Engine-only. That's a
deliberate safety choice, not laziness: Engine-only is the
pre-highlighted default in the first-run prompt, so if this function is
ever called without that variable properly threaded through (a test
calling it in isolation, a future refactor), it fails toward the safe,
already-tested default rather than silently skipping Docker setup
entirely. A lookup table (`case` statement mapping known strings to
functions) would also work and might look more "complete," but it would
have to explicitly enumerate the not-Desktop case anyway - the two-way `if`
says exactly what's true: there are only ever two branches here, and one of
them is presumed.

### `omawsl_check_docker_path_collision` (`install/terminal/docker.sh`)

```bash
omawsl_check_docker_path_collision() {
  local which_output="${1:-$(which -a docker 2>/dev/null || true)}"
  [[ -z "$which_output" ]] && return 0

  local first_path
  first_path="$(echo "$which_output" | head -n1)"
  local count
  count="$(echo "$which_output" | grep -c . || true)"

  if [[ "$count" -gt 1 && "$first_path" != "/usr/bin/docker" ]]; then
    echo "omawsl: multiple 'docker' binaries found on PATH:"
    echo "$which_output"
    echo "'$first_path' resolves first, which isn't the natively installed docker-ce."
    echo "Reorder your PATH (e.g. in ~/.bashrc) so /usr/bin/docker comes first, or the"
    echo "Docker Desktop interop version may shadow it unexpectedly."
  fi
}
```

This one exists because of a real thing seen on a real machine during this
project's own design review: Docker Desktop injects a `docker.exe` interop
shim onto WSL's `$PATH`, and depending on ordering, *that* shim can resolve
before the natively `apt-get`-installed `/usr/bin/docker` - so a user who
installed Engine-only Docker natively might still be unknowingly talking
to Docker Desktop's shim. `which -a docker` (as opposed to plain `which
docker`) lists *every* match on `$PATH` in resolution order, not just the
first, which is exactly what's needed to notice a collision at all.

Look at the function signature: it takes the `which -a docker` output as
an *optional argument*, defaulting to actually running `which -a docker`
if no argument is given. This is what lets it be unit-tested with fixture
strings (`"/mnt/c/.../docker\n/usr/bin/docker"`) instead of depending on
whatever happens to be installed on the machine running the tests - the
same "parameterize the thing you can't control in a test" idea Phase 1
established with `OMAWSL_STATE_DIR`.

### `omawsl_install_docker_ce` and idempotency (`install/terminal/docker.sh`)

```bash
omawsl_install_docker_ce() {
  local apt_sources_file="${1:-/etc/apt/sources.list.d/docker.list}"
  local keyrings_dir="${2:-/etc/apt/keyrings}"

  sudo apt-get update -qq
  sudo apt-get install -y ca-certificates curl gnupg

  if [[ ! -f "$apt_sources_file" ]]; then
    sudo install -m 0755 -d "$keyrings_dir"
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o "$keyrings_dir/docker.gpg"
    sudo chmod a+r "$keyrings_dir/docker.gpg"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyrings_dir/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
      | sudo tee "$apt_sources_file" >/dev/null
    sudo apt-get update -qq
  fi

  sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}
```

This is the first time omawsl adds a **third-party apt repository** -
every package installed before this phase came from Ubuntu's own repos.
Docker's own repo needs a GPG signing key trusted locally first (so `apt`
can verify packages actually came from Docker, not an attacker on the
download path), which is what the `curl | gpg --dearmor` line is doing:
downloading Docker's public key and converting it from its distributed
ASCII-armored text form into the binary form `apt` expects, saved into
`/etc/apt/keyrings/`.

The idempotency guard here is `if [[ ! -f "$apt_sources_file" ]]`: the
repo-add dance (key, sources file, `apt-get update`) only happens the
*first* time this runs, because once `/etc/apt/sources.list.d/docker.list`
exists, it doesn't need re-adding. The final `apt-get install` line runs
unconditionally every time regardless - that's fine, because `apt-get
install` on an already-installed package is itself idempotent (it just
says "already the newest version"). Only the *file-existence-guarded* part
needed an explicit guard; the naturally-idempotent part didn't.

`sudo` shows up seven times in this one function. Every single privileged
action is its own explicit `sudo` call, rather than the whole function
being wrapped in one. That's not just style - it means each line's
privilege requirement is visible right where the line is, and (as you'll
see in the Exercise and Check) it's also what makes this function testable
at all: stub `sudo` itself, and every one of these calls is caught.

### `omawsl_docker_engine`, the systemd guard, and the deliberate `exit 0`

```bash
omawsl_docker_engine() {
  local wsl_conf="${1:-${OMAWSL_WSL_CONF_FILE:-/etc/wsl.conf}}"
  local apt_sources_file="${2:-${OMAWSL_DOCKER_APT_SOURCES_FILE:-/etc/apt/sources.list.d/docker.list}}"
  local keyrings_dir="${3:-${OMAWSL_DOCKER_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if ! grep -q "^systemd=true" "$wsl_conf" 2>/dev/null; then
    printf '[boot]\nsystemd=true\n' | sudo tee -a "$wsl_conf" >/dev/null
    echo "omawsl: WSL systemd support was just enabled."
    echo "Run 'wsl --shutdown' from Windows (PowerShell/cmd), reopen this terminal, then re-run install.sh to finish Docker setup."
    exit 0
  fi

  omawsl_install_docker_ce "$apt_sources_file" "$keyrings_dir"

  sudo usermod -aG docker "$USER"
  echo "omawsl: open a new terminal (or run 'newgrp docker') before using Docker without sudo."

  omawsl_check_docker_path_collision
}
```

Docker's daemon needs `systemd` running as WSL2's init system - not the
default for a fresh WSL install. `/etc/wsl.conf` is how you turn that on
(`[boot]\nsystemd=true`), but WSL only reads that file when its *own*
Linux VM starts up - not while it's already running. A script running
*inside* the already-running WSL instance cannot restart the WSL VM out
from under itself. So the only honest thing to do, if systemd wasn't
already on, is: write the config, tell the user exactly what to do (`wsl
--shutdown` from *Windows*, not from inside WSL), and stop - installing
`docker-ce` right now would be pointless, since the daemon can't run until
after that restart anyway.

That `exit 0`, not `return 0`, is the sharpest design decision in this
whole phase, and it only makes sense in light of one of this phase's
**global constraints** (stated up front in the plan): `install/terminal/*.sh`
scripts are `source`d into `terminal.sh`, not run as separate subprocesses.
Sourcing means they share the same process and the same shell - so `exit`
here doesn't just end `docker.sh`, it ends the *entire* `install.sh` run,
skipping `select-dev-storage.sh` and everything after it. That's
intentional, spelled out in the plan's own global constraints: nothing
after this point has useful work to do until the restart happens, and
re-running `install.sh` afterward just hits this same guard again, finds
`systemd=true` already there, and sails straight through - the guard
itself is idempotent even though the underlying action (a VM restart)
obviously isn't repeatable in the same sense.

The three parameters (`wsl_conf`, `apt_sources_file`, `keyrings_dir`) each
default through an `OMAWSL_*` environment variable override before
falling back to the real system path - the same pattern as
`omawsl_install_docker_ce`'s two parameters, and the same pattern Phase 1
established with `OMAWSL_STATE_DIR`. It's what makes this function
callable two ways: with no arguments in a real run (falls through to the
real `/etc/wsl.conf`), or with explicit scratch paths in a test (never
touches the real filesystem).

### `select-dev-storage.sh`: `omawsl_ensure_container` and the empty-selection case

```bash
omawsl_ensure_container() {
  local name="$1"; shift
  if sudo docker ps -a --format '{{.Names}}' | grep -qx "$name"; then
    return 0
  fi
  sudo docker run -d --name "$name" --restart unless-stopped "$@"
}

omawsl_install_storage() {
  local storage="${OMAWSL_STORAGE:-}"

  if [[ -n "$storage" ]] && ! omawsl_docker_reachable; then
    echo "omawsl: skipping storage containers - 'docker' isn't reachable yet."
    echo "Finish Docker setup (see the checklist above), then re-run install.sh."
    return 0
  fi

  if omawsl_list_has "$storage" "MySQL"; then
    omawsl_ensure_container omawsl-mysql \
      -p 3306:3306 \
      -e MYSQL_ROOT_PASSWORD=password \
      -v omawsl-mysql-data:/var/lib/mysql \
      mysql:8
  fi
  # ... Redis and PostgreSQL follow the identical shape
}
```

`omawsl_ensure_container` is the idempotency guard `docker run` doesn't
give you for free, mentioned in the Concept: `docker ps -a --format
'{{.Names}}'` lists every container's name (running *or* stopped -
`-a`/`--all` matters, since a stopped container still occupies the name),
piped to `grep -qx "$name"` (`-x` requires the *whole line* to match, not
just a substring - so a container literally named `omawsl-mysql-staging`
can't falsely satisfy a check for `omawsl-mysql`). If found, return early;
otherwise, actually create it. Every one of the three storage engines
funnels through this one helper rather than each repeating the same
existence check inline - `docker run -d --name "$name" --restart
unless-stopped "$@"` forwards whatever port/env/volume flags the caller
passed via `"$@"`, so `omawsl_ensure_container` itself doesn't need to
know anything about MySQL vs. Redis vs. Postgres.

`omawsl_install_storage`'s very first check is the one worth sitting
with: **nothing is pre-selected by default, and selecting nothing at all
is a valid, expected state** - one of this phase's explicit global
constraints. There's no `if [[ -z "$storage" ]]; then echo "you should
pick something"; fi` - the function just falls straight through all three
`omawsl_list_has` checks, none of them match, and it returns having done
nothing. No error, no warning, nothing printed. A user who doesn't want
any local databases installed shouldn't see so much as a stray log line
about it.

The reachability guard right above the three checks - `if [[ -n "$storage"
]] && ! omawsl_docker_reachable` - is a second, closely related idea:
what if the user *did* pick some storage, but chose Docker Desktop and
hasn't finished setting it up yet, so `docker` isn't actually reachable?
Without this guard, `docker ps -a` inside `omawsl_ensure_container` would
fail outright, and because every script in this project runs under `set
-euo pipefail`, that failure would abort the *entire* `install.sh` run -
an unrelated, cascading failure from a Windows-side prerequisite the user
just hasn't gotten to yet. The guard turns that into the same
detect-and-defer shape from the Concept section: skip cleanly, print
what's still pending, let the rest of the run continue.

### The two bugs a green test suite couldn't catch

Tasks 1 through 6 all passed their full stubbed bats test suite before
Task 7's real, human-run install ever started. Task 7 still surfaced two
bugs, and both are worth sitting with, because neither is a logic bug -
they're bugs about what happens when code that's individually correct runs
in a real, stateful environment.

**Bug 1 - the stale-group `sudo` crash.** `omawsl_docker_engine` runs `sudo
usermod -aG docker "$USER"` to add the current user to the `docker` Unix
group (an OS-level mechanism for granting a set of users the same
permissions - here, permission to talk to the Docker daemon without typing
`sudo` every time). That's correct. But Linux only *refreshes* a running
shell's group membership on its next login - not retroactively, mid
-session. `terminal/*.sh` scripts are sourced into one continuous shell
process (the same fact that made the `exit 0` above meaningful), so
`select-dev-storage.sh` runs moments later, in that *same* not-yet
-refreshed session - and its bare `docker ps`/`docker run` calls hit a real
"permission denied while trying to connect to the docker API," even though
the daemon was running fine. The fix (commit `871a92a`) was to route
`omawsl_ensure_container` through `sudo docker` instead of bare `docker` -
which is exactly the code shown above. No stubbed test could have caught
this: a stub for `sudo usermod` just logs that it was called and returns
0 - it has no concept of "and now the current process's group cache is
stale," because that's a fact about the real OS, not about the script's
logic.

**Bug 2 - the reminder that scrolled out of view.** The fix above still
prints a one-time reminder mid-run: `"omawsl: open a new terminal (or run
'newgrp docker') before using Docker without sudo."` That's correct
*information*, but by the time a real install finishes, `terminal/
libraries.sh`'s own `apt-get` output (dozens of lines) has scrolled it well
off the top of the terminal. The human running Task 7 hit exactly the
error that message was trying to prevent, seconds after seeing "install
complete," because they never actually saw the reminder. The fix (commit
`abc46e8`) was `omawsl_docker_final_reminder`, which re-prints the same
message a second time, in `install.sh`'s own final summary - the one place
guaranteed to still be on screen:

```bash
omawsl_docker_final_reminder() {
  if [[ "${OMAWSL_DOCKER_MODE:-}" != "$OMAWSL_DOCKER_MODE_DESKTOP" ]]; then
    echo "omawsl: remember to open a new terminal (or run 'newgrp docker') before using Docker without sudo."
  fi
}
```

Both bugs share a lesson: a stubbed test suite verifies that your code
*calls the right commands with the right arguments*. It cannot verify
what a real OS does in response, or what a real human sitting at a real
terminal actually sees. That's exactly why this project's plans end every
phase with a manual, human-run, unstubbed verification step, not just a
green `bats` run - and it's why this lesson's own Check (below) is
explicit that passing it certifies your *decision logic*, not that your
code would survive a real machine.

## 3. Exercise

Close this lesson and rebuild this phase from scratch in
`practice/02-docker-and-storage/`. Three files are stubbed out for you
there:

- `lib.sh` already has `omawsl_list_has` given (carried over from Lesson
  1 - not new material here). Implement `omawsl_docker_reachable`.
- `docker.sh` already has the `SCRIPT_DIR`/`source` boilerplate and the
  `OMAWSL_DOCKER_MODE_DESKTOP` constant. Implement, in this order (later
  ones call earlier ones):
  - `omawsl_docker_desktop` - no arguments. Silent no-op if
    `omawsl_docker_reachable`; otherwise print a message that mentions
    `docs/windows-setup.md#docker-desktop` and tells the user to re-run
    `install.sh`.
  - `omawsl_check_docker_path_collision [which_a_docker_output]` - takes
    the `which -a docker` output as an optional argument (default to
    actually running `which -a docker` if omitted). Warn only when more
    than one path is present *and* the first one isn't `/usr/bin/docker`.
  - `omawsl_install_docker_ce [apt_sources_file] [keyrings_dir]` -
    parameters default to the real system paths. Guard the repo-add
    steps (key + sources file + one `apt-get update`) on the sources file
    not already existing; always end with an unconditional `apt-get
    install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
    docker-compose-plugin`.
  - `omawsl_docker_engine [wsl_conf_file] [apt_sources_file]
    [keyrings_dir]` - each parameter defaults through an `OMAWSL_*`
    environment variable override (`OMAWSL_WSL_CONF_FILE`,
    `OMAWSL_DOCKER_APT_SOURCES_FILE`, `OMAWSL_DOCKER_APT_KEYRINGS_DIR`)
    before falling back to the real system path. Check `wsl_conf` for a
    `^systemd=true` line; if it's missing, append `[boot]\nsystemd=true\n`
    to it, print a restart message, and stop the whole run with `exit 0`
    (not `return`). If systemd was already on, call
    `omawsl_install_docker_ce`, then `sudo usermod -aG docker "$USER"`
    plus a reminder message, then `omawsl_check_docker_path_collision`.
  - `omawsl_docker_final_reminder` - no arguments. Prints the same
    "open a new terminal / newgrp docker" reminder, unless
    `OMAWSL_DOCKER_MODE` is the literal Desktop string.
  - `omawsl_docker` - the dispatcher: Desktop mode only for the exact
    string `"Docker Desktop for Windows"`, Engine mode for everything
    else (including unset).
- `select-dev-storage.sh` already has the `SCRIPT_DIR`/`source`
  boilerplate. Implement:
  - `omawsl_ensure_container <name> <docker run args...>` - no-op if a
    container by that name already exists (running or stopped); otherwise
    `docker run -d --name "$name" --restart unless-stopped` plus whatever
    args were passed through. Route every `docker` call through `sudo`.
  - `omawsl_install_storage` - reads `OMAWSL_STORAGE` (a comma-delimited
    list, possibly empty or unset). If it's non-empty but
    `omawsl_docker_reachable` fails, print a skip message and return
    cleanly - don't let a `docker` call fail and abort the run. Otherwise,
    for each of `"MySQL"`, `"Redis"`, `"PostgreSQL"` present in the list
    (via `omawsl_list_has`), call `omawsl_ensure_container` with a name of
    `omawsl-<lowercase-name>` and reasonable port/volume/env flags for
    that engine (exact flag values aren't graded - only which containers
    get created for which selections).

Don't peek at the real `install/terminal/docker.sh` or
`install/terminal/select-dev-storage.sh` until after your check passes.

## 4. Check

Run:

```bash
practice/02-docker-and-storage/check.sh
```

This check never installs `docker-ce`, never touches the real `docker`
group, and never starts a real container - every dangerous command
(`sudo`, `docker`, `apt-get`, `usermod`, `curl`, `gpg`) is replaced with a
harmless stand-in that only records what it was asked to do, so it's safe
to run as many times as you like, on any machine, with no root access.
What it *does* verify is your decision logic: given a mode variable and a
reachability check, does the right branch run; given a storage selection,
do the right (and only the right) containers get created; does the
systemd guard actually stop the run; does the idempotency guard actually
skip an existing container.

Each assertion prints its own `PASS:` or `FAIL:` line, and the check
keeps going after a failure instead of stopping at the first one - read
every `FAIL:` line you get, not just the first, before going back to fix
anything. A `FAIL:` line names the *behavior* that didn't match (e.g.
"routes to engine mode when OMAWSL_DOCKER_MODE is unset") and usually
shows what your code actually produced - that's what to fix, not any
particular line number.

A passing check means your implementation is behaviorally correct even if
it's organized completely differently from the original - different
variable names, a different order of `if` branches, whatever. Once it
passes, you can `diff` your files against `install/terminal/docker.sh`,
`install/terminal/select-dev-storage.sh`, and `install/lib.sh` purely to
compare style and see the real comments explaining *why* - never treat
that diff as the actual grade.

One thing this check *can't* verify, on purpose, mirroring this phase's
own real-world lesson: it can't tell you whether your code would survive
a real machine, with a real `sudo` password, a real stale group cache, and
a real scrolling terminal. That's what Task 7 in this phase's own plan was
for, and no automated check - this one included - is a substitute for it.
