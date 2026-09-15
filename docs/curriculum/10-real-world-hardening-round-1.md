# Lesson 10: Real-World Hardening, Round 1

## 1. Concept

Every phase so far has been verified the same way: run the bats test
suite, see green, move on. That's real verification, but it tests one
specific way of *invoking* the code — `bash boot.sh`, called directly,
with a real file sitting on disk. It does not test the way omawsl is
actually documented to be run: the single-line install command a brand
new user pastes into a fresh WSL2 terminal,

```
curl -fsSL https://raw.githubusercontent.com/tunacinsoy/omawsl/master/boot.sh | bash
```

`curl -fsSL <url>` downloads that URL's content and prints it to
stdout instead of saving it to a file (`-f` fails silently on HTTP
errors instead of printing an HTML error page, `-s` suppresses curl's
own progress output, `-L` follows redirects). The `|` is a pipe: it
takes the stdout of the command on its left and feeds it in as the
stdin of the command on its right. So `curl ... | bash` never writes
`boot.sh` to disk at all — it streams the script's *text* directly into
a running `bash` process's stdin, and bash reads and executes it from
there, the same way it would read a script from a file, except there is
no file.

That distinction — text arriving on stdin instead of a path on disk —
turns out to break several things bash scripts normally take for
granted, and every one of them was invisible to `bash boot.sh` in a
terminal, because that invocation always hands bash a real file. This
phase is four bugs the project's author found by actually running the
real one-liner on a real fresh machine, after the test suite was
already fully green. The throughline stated in the outline is worth
holding onto for the rest of your own projects: **"works when I run it
locally" and "works via the documented one-liner" are different
claims, and the second one needs its own testing** — a passing test
suite tells you your code is correct under the ways you thought to
invoke it, not under every way it will actually be invoked.

Two of the four bugs share a root cause worth understanding precisely,
because it will bite you again in any interactive script meant to be
piped into a shell:

**stdin can only be consumed once, and under `curl | bash` it's already
spoken for.** stdin is one of three standard I/O streams every process
gets on startup (stdin, stdout, stderr) — a single stream of bytes a
program can read from. Normally, when you run a script interactively in
a terminal, its stdin *is* your terminal: every keystroke you type is
what a `read` command inside the script consumes. But under `curl | bash`,
bash's stdin has already been claimed by the pipe — it's the *script's
own source text*, streaming in. If that script later calls `read` to ask
the user something, it isn't reading keystrokes; it's reading whatever
of the script's own text bash hasn't consumed yet (or nothing, once
bash has consumed all of it — an immediate end-of-file, which makes
`read` return failure instantly). The fix real `curl | bash` installers
use (rustup, among others) is to bypass stdin entirely for prompts and
read directly from `/dev/tty` — a special device file that always
refers to whatever terminal is actually controlling the current
process, regardless of what stdin has been redirected to. If a real
person is running the one-liner in a real terminal, `/dev/tty` reaches
their actual keystrokes. If there's no controlling terminal at all (a
CI job, a headless script), opening `/dev/tty` itself fails, which a
correct implementation must treat as "can't ask, so don't hang — just
decline."

## 2. Walkthrough

### Bug 1 — the crash: `BASH_SOURCE` is unbound when there's no file

Before this phase, `boot.sh` ended with the same guard pattern every
other script in the project uses to tell "was I executed directly" from
"was I sourced by something else":

```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  omawsl_boot
fi
```

`BASH_SOURCE` is a bash array holding the source-file path of each
function currently on the call stack; `BASH_SOURCE[0]` is normally
"the file bash is currently executing." `$0` is the name the process
was invoked as. When a file is run directly (`bash boot.sh`), both
resolve to the same path, the guard is true, and `omawsl_boot` runs. If
another script instead `source`s this file, `BASH_SOURCE[0]` is the
*sourced* file while `$0` is the *outer* script's name, so they differ
and the guarded call is skipped — exactly the "only run main if this
file is the entry point, not a library being pulled in" behavior every
other script wants.

But under `curl | bash`, bash isn't reading a file at all — it's
reading arbitrary text from stdin. There is no source file, so
`BASH_SOURCE` is a zero-element array, and `${BASH_SOURCE[0]}` is a
reference to an index that doesn't exist. Every script here runs under
`set -euo pipefail`; the `-u` flag makes referencing *any* unset
variable a hard error. So the very last thing this script tried to do
was blow up with `bash: line 81: BASH_SOURCE[0]: unbound variable`,
before `omawsl_boot` — the function that prints the banner and does
everything else — ever ran. The real fix (commit `94d858e`) is to
delete the guard for this one file:

```bash
omawsl_boot
```

Why is deleting the guard safe here specifically, when the same guard
is correct in 47 other files in this project? Because the guard's whole
job is to distinguish "sourced" from "executed," and `boot.sh` is
never sourced anywhere in this codebase — it's the outermost entry
point, always either executed directly or piped into bash. A guard
that protects against a scenario that can't happen isn't neutral; here
it actively breaks the one scenario (piped stdin) that matters most,
since it's the one in the README's documented install command. This is
a case where "match the pattern every other file uses" was the wrong
instinct — the right call required knowing *why* the pattern exists,
not just that it exists.

### Bug 2 — the misread: `read` without a redirect reads the wrong thing

With the crash fixed, `omawsl_boot` could finally run all the way to
its confirmation prompt — and immediately printed "Aborted." without
ever waiting for an answer. The pre-fix code was:

```bash
local reply=""
read -r -p "Continue? [y/N] " reply || true
[[ "$reply" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
```

`read -r -p "prompt" var` prints `prompt`, then reads one line from
stdin into `var` (`-r` disables backslash-escape processing, so a
literal `\` in the input isn't treated specially). With no explicit
redirect, `read`'s stdin is whatever the surrounding process's stdin
is — and as the Concept section above laid out, under `curl | bash`
that's the tail end of the script's own source text, not the user's
keystrokes. `read` hits end-of-file almost immediately, returns
failure (caught by the `|| true` so the script doesn't abort), `reply`
stays empty, the regex match fails, and "Aborted." prints — even though
a real human was watching, ready to type `y`.

The fix (commit `3fcf402`) adds one redirect:

```bash
read -r -p "Continue? [y/N] " reply < /dev/tty || true
```

`< /dev/tty` overrides *just this command's* stdin to read from the
controlling terminal instead of the process's normal stdin — the same
technique described in the Concept section. The existing `|| true` was
already exactly the right shape for the remaining edge case: if there's
truly no controlling terminal at all (opening `/dev/tty` itself fails,
e.g. `ENXIO` — "no such device"), `read` fails, `|| true` absorbs that
failure instead of crashing, `reply` stays empty, and the script falls
through to the same graceful "Aborted." — matching the project's
existing `OMAWSL_ASSUME_YES=1` escape hatch for headless/CI use, rather
than hanging forever waiting for input that will never come.

Notice what the fix does *not* do: it doesn't try to detect "am I being
piped into" and branch on that. It always reads from `/dev/tty`,
unconditionally. That's a deliberate simplicity: `/dev/tty` degrades
correctly in every case on its own (works when there's a real terminal,
fails cleanly when there isn't) without the script needing to first
figure out which situation it's in.

The commit that fixed this also had to touch the test suite in an
instructive way. The *old* test for this prompt piped `echo n` into
`bash boot.sh` and asserted it aborted — which happened to pass before
the fix, but for the wrong reason (`read` was consuming that piped
"n"). After the fix, that same test would still pass, but again for the
wrong reason (piped stdin is now ignored entirely, and no `/dev/tty` is
available in a normal test harness either, so it aborts regardless of
what's piped in). A test that passes for the wrong reason isn't proof
of anything. The fix replaces it with two tests that isolate what
actually changed:

```bash
run setsid bash -c 'echo y | bash "'"$REPO_ROOT"'/boot.sh"'
[ "$status" -eq 1 ]
[[ "$output" == *"Aborted"* ]]
```

`setsid` runs a command in a new session, detached from any controlling
terminal — so inside it, `/dev/tty` genuinely doesn't exist, the same
as a real headless run. Piping in `y` here and asserting it still
aborts is the actual regression test: it proves piped "y" is ignored,
where the old test only proved piped "n" was rejected (which a *broken*
implementation would also do, coincidentally). The second new test
pipes nothing at all (`< /dev/null`) and asserts the same graceful
abort — proving the missing-terminal case degrades safely rather than
hanging.

### Bug 3 — the cosmetic scare: `mv` across a filesystem boundary

`bin/omawsl theme` writes an updated Windows Terminal `settings.json`
by building the new content in a temp file, then swapping it into
place. The temp file (from `mktemp`) lives on WSL2's own Linux-native
filesystem; `settings.json` lives under `/mnt/c/...` — Windows' C:
drive, mounted into WSL2 via `drvfs`. The original code used `mv` for
that swap:

```bash
mv "$tmp" "$settings_file"
```

`mv`'s fast path is an atomic rename — a filesystem-level pointer swap
that never actually copies the bytes. But an atomic rename only works
*within* a single filesystem; `mv` can't rename across the boundary
from ext4 (WSL2's native filesystem) to `drvfs` (Windows' mount). When
it can't do the fast path, `mv` silently falls back to copying the
bytes, then tries to preserve the source file's metadata (timestamps,
permissions) on the copy, then deletes the original. `drvfs` doesn't
support the specific syscalls (`utime`, `chmod`) that "preserve
metadata" step needs — so every single run printed:

```
mv: preserving times/permissions for '.../settings.json': Operation not permitted
```

twice, on every theme change. The operation still succeeded — the file
still moved, the content was still correct, `mv` still exited `0` — but
it read exactly like a failure, including live during a demo. The fix
(commit `b008062`):

```bash
cp "$tmp" "$settings_file"
rm -f "$tmp"
```

Plain `cp` (no `--preserve`) never attempts to replicate the source's
metadata in the first place, so it never touches the syscalls `drvfs`
rejects — it just copies bytes. Followed by an explicit `rm` of the
temp file, since `cp` alone doesn't delete its source the way `mv`
does. This is a good example of a bug the project's own automated tests
*structurally cannot catch*: the bats test for this function points its
fake `settings_file` at a path that stays on the native filesystem the
whole time, so it never crosses the ext4-to-drvfs boundary that
triggers the warning at all. The fix was verified the only way it could
be — running the real function against a real `/mnt/c/...` path by
hand, both before (confirming the warning) and after (confirming it was
gone and the content still transferred correctly).

### Bug 4 — the false positive: a `docker` shim that isn't really Docker

`omawsl_docker_reachable` in `install/lib.sh` is the shared check two
different install steps use to decide "is Docker already usable, or
does this user need Docker installed / a Windows-side prerequisite
flagged." Before this phase, it was:

```bash
omawsl_docker_reachable() {
  command -v docker &>/dev/null
}
```

`command -v docker` answers one narrow question: is there *something*
named `docker` on `$PATH`. Docker Desktop for Windows, when installed,
drops a `docker` shim onto the `PATH` of *every* WSL distro on the
machine — even ones where that distro's WSL integration toggle is still
off in Docker Desktop's settings. Run that shim on a distro without
integration enabled, and it doesn't behave like "command not found" —
it prints a friendly "enable WSL integration for this distro" message
and exits non-zero. `command -v` can't tell that apart from a real,
working `docker`: the shim satisfies "something named docker exists on
PATH" perfectly well. So omawsl believed Docker was reachable, skipped
its own graceful install-or-defer logic, and let a later step call
`sudo docker ...` directly — which then failed with a raw, confusing
error instead of omawsl's own clear message.

The fix (commit `e5c11cb`) checks that docker actually *does* something,
not just that it exists:

```bash
omawsl_docker_reachable() {
  command -v docker &>/dev/null && docker info &>/dev/null
}
```

`docker info` is a real round-trip to the Docker daemon — it only
succeeds if there's an actual running, reachable daemon behind the
`docker` command. The non-integrated shim fails this immediately
(that's exactly what its nudge message is, dressed up as a normal CLI
failure), while a genuinely working Docker installation succeeds. This
is the general shape worth remembering: "is a command present" and "is
a command functional" are different questions, and a tool that can be
installed-but-inert (a shim, a stub, a not-yet-configured client) needs
the second check, not the first.

## 3. Exercise

Close this lesson and rebuild these fixes from scratch, blind, in
`practice/10-real-world-hardening-round-1/`. Two files are stubbed out
for you there:

**`lib.sh`** — implement two pure functions (no top-level code, nothing
that runs just from being sourced):

- `omawsl_docker_reachable` — takes no arguments. Return 0 only if a
  `docker` command is on `PATH` *and* actually functional (not just
  present as an unhelpful shim). Return 1 otherwise.
- `omawsl_atomic_replace <tmp_path> <dest_path>` — replace
  `dest_path`'s contents with `tmp_path`'s contents and remove
  `tmp_path` afterward, without ever calling `mv`.

**`mini-boot.sh`** — a scaled-down stand-in for the real `boot.sh`.
Rebuild it so it:

1. Prints a banner line containing the word `omawsl`.
2. Unless `OMAWSL_ASSUME_YES=1` is set, prompts with something
   containing `"Continue?"` and reads the answer from the real
   controlling terminal (not bash's own stdin).
3. If the answer isn't `y`/`Y` — including when there's no controlling
   terminal to read from at all — prints exactly `Aborted.` and exits
   1, without hanging.
4. Otherwise, prints exactly `INSTALL_RAN` (standing in for the real
   install step) and exits 0.
5. Does not crash when its own text is piped into `bash` on stdin
   instead of run from a file on disk — try
   `cat mini-boot.sh | bash` yourself while working on this and see
   what breaks before you fix it.

Do not import `install/lib.sh` or `boot.sh` from the real project to
peek — the whole point is rebuilding the reasoning, not the text. It's
fine (encouraged, even) to actually run `cat mini-boot.sh | bash` and
`echo y | bash mini-boot.sh` yourself by hand while developing, the
same way the original bug was actually found — that direct
experimentation is exactly the "test the one-liner, not just the
local run" habit this lesson is about.

## 4. Check

Run:

```
bash practice/10-real-world-hardening-round-1/check.sh
```

It prints one `PASS:`/`FAIL:` line per behavior it checks and exits
non-zero if anything failed — it does not stop at the first failure,
so a single run tells you everything that still needs work. A failure
tells you *which observable behavior* didn't match (e.g. "accepted
piped stdin as the confirmation answer" means your `mini-boot.sh` is
still reading from plain stdin instead of `/dev/tty`), not which lines
of text differ from the original — a solution that looks nothing like
the original project's code still passes if it behaves correctly in
every case tested.

One limitation worth knowing going in: the check for
`omawsl_atomic_replace` can only verify the *functional* outcome (right
content ends up in `dest_path`, `tmp_path` is gone) — it cannot verify
that no cross-filesystem warning would print, because that only
happens when the two paths are actually on different filesystems
(ext4 vs. `drvfs`), which a portable automated check can't set up. The
original project hit the same limitation and verified that part by
hand against a real `/mnt/c/...` path — if you want to see the warning
yourself, use `mv` instead of `cp`+`rm` in your implementation and run
it against a real Windows-mounted path from inside WSL2; then switch
back to `cp`+`rm` and confirm it goes away.

Once your check passes, you can compare your solution against the
original commits (`94d858e`, `3fcf402`, `b008062`, `e5c11cb` in this
repo's git history) purely to see a different way the same behavior was
written — never as the grade. A passing check already means your
solution is behaviorally correct.
