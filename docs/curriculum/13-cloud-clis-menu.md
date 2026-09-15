# Lesson 13: Cloud CLIs Menu

## 1. Concept

By this point in the project, `install/first-run-choices.sh` has one
picker (built in Lesson 3) called "Languages & cloud tools." Its options
are the 8 programming languages this project supports, plus two things
that aren't languages at all: Terraform and Azure CLI. That grouping made
sense the day it was written — Azure CLI was the *only* cloud-provider
CLI this project installed, and it needed to live somewhere, so it rode
along with the languages picker rather than getting a menu of its own.

This phase adds two more cloud-provider CLIs — AWS CLI and GCP CLI
(`gcloud`) — and that's the moment the old grouping stops making sense.
"Languages & cloud tools, plus two more cloud tools that aren't Azure"
is a worse menu than "Languages" and "Cloud CLIs" as two separate,
correctly-named things. So this phase does something narrower than
"add two new tools": it **carves a new picker category out of an
existing one**, moves Azure CLI into it, and adds AWS CLI and GCP CLI
alongside it.

Before getting into the mechanics, it's worth naming precisely what a
"picker category" *is* in this project, because the whole phase is about
keeping one consistent. Recall from Lesson 7: `bin/omawsl-sub/items.sh`
is a single flat registry — three tiny functions
(`omawsl_item_category`, `omawsl_item_label`, `omawsl_item_slugs`) that
answer, for any short slug like `"go"` or `"azure"`, three questions:
*what category is this in* (`language`, `editor`, `storage`, ...),
*what's its exact display label* (`"Go"`, `"Azure CLI"`), and *what
slugs exist in a given category*. Every other piece of this project that
needs to know any of that — the interactive `install`/`uninstall`
pickers, `doctor`'s status report, the update mechanism — reads it from
here rather than each maintaining its own copy. That's the payoff of a
registry, and it's a general software idea worth naming: a **single
source of truth**. The alternative — `install.sh` has its own list of
"things that are cloud CLIs," `uninstall.sh` has another, `doctor.sh` has
a third — works fine on day one and then rots the first time someone
adds a tool and forgets one of the three lists. A shared registry can't
drift, because there's only one copy to edit.

So "add a `cloud` category" sounds like a one-line change (it mostly is,
in `items.sh`), but it's not the *only* place that has to change. Every
place that currently branches on `language`/`editor`/`storage` — the
`install`, `uninstall`, and `doctor` sub-commands, each in its own file —
has to grow a fourth branch for `cloud`, in the same shape as the other
three, or the picker will exist in the registry but silently do nothing
anywhere else. That's the "mechanical cost" the outline names: not hard
individually, but real, and easy to do inconsistently if you touch
`install.sh` and forget `doctor.sh`. This lesson's real commit history
has a small, concrete example of exactly that kind of thing going wrong
and getting caught in review — covered in the Walkthrough below.

There's a second, independent teaching point layered on top: **moving
code without breaking it**. Azure CLI's install function and its
uninstall function already exist and already work — they're just filed
in the wrong place (`install/terminal/cloud-tools.sh`, mixed in with
Terraform; `uninstall/dev-language.sh`, mixed in with the 8 languages'
uninstallers). Moving them means editing *two* existing files (removing
code) and writing *two* new ones (receiving it) — four files touched for
what's conceptually "one tool changed its home." Get any one of those
four wrong — leave a stray reference in the old file, forget to remove
the old dispatcher's branch for it — and you get a tool that either
silently stops working or silently runs twice.

## 2. Walkthrough

### Where Azure CLI used to live

Before this phase, `install/terminal/cloud-tools.sh` held both Terraform
and Azure CLI, because both were selected through the same
`OMAWSL_LANGUAGES` picker string:

```bash
omawsl_cloud_tools() {
  local languages="${OMAWSL_LANGUAGES:-}"

  if omawsl_list_has "$languages" "Terraform"; then
    omawsl_install_terraform
  fi

  if omawsl_list_has "$languages" "Azure CLI"; then
    omawsl_install_azure_cli
  fi
}
```

And `bin/omawsl-sub/items.sh`'s registry reflected that grouping exactly
— `azure` filed under `language`, right alongside the 8 real languages
and Terraform:

```bash
omawsl_item_category() {
  case "$1" in
    ruby|node|go|php|python|elixir|rust|java|terraform|azure) echo "language" ;;
    vscode|neovim|opencode|cursor|claude|codex|gh-copilot|gemini) echo "editor" ;;
    mysql|redis|postgresql) echo "storage" ;;
    docker) echo "docker" ;;
    *) return 1 ;;
  esac
}
```

### The registry change: one category becomes two

Commit `bf89a10` ("feat: add a cloud category to the item registry
(azure/aws/gcp)") is the smallest commit in this phase and the one that
matters most to get right, because every other file in this lesson reads
from it. It touches all three of `items.sh`'s functions:

```diff
 omawsl_item_category() {
   case "$1" in
-    ruby|node|go|php|python|elixir|rust|java|terraform|azure) echo "language" ;;
+    ruby|node|go|php|python|elixir|rust|java|terraform) echo "language" ;;
+    azure|aws|gcp) echo "cloud" ;;
     vscode|neovim|opencode|cursor|claude|codex|gh-copilot|gemini) echo "editor" ;;
```

`azure` doesn't just get a new home — it comes with two new neighbors
that never existed before, `aws` and `gcp`. `omawsl_item_label` gains two
new lines for their exact display strings (`"AWS CLI"`, `"GCP CLI"`) —
`azure`'s own label, `"Azure CLI"`, doesn't change at all, only its
category does. And `omawsl_item_slugs` splits one `printf` line into two:

```diff
 omawsl_item_slugs() {
   case "$1" in
-    language) printf '%s\n' ruby node go php python elixir rust java terraform azure ;;
+    language) printf '%s\n' ruby node go php python elixir rust java terraform ;;
+    cloud) printf '%s\n' azure aws gcp ;;
```

Notice what *doesn't* change here: Terraform stays in `language`. The
design spec is explicit about this (§2, "Out of scope"): Terraform is an
infrastructure-as-code tool, not a cloud provider's own CLI, and moving
it would be scope creep this phase deliberately declines. Only Azure CLI
moves — new tools join it, nothing else does.

### Moving the install code: subtraction and addition, in two different files

`install/terminal/cloud-tools.sh` loses its Azure CLI branch (commit
`72e5a7f`) and shrinks back down to Terraform alone — the exact function
shown at the top of this Walkthrough is what it becomes.
`omawsl_install_azure_cli` doesn't get rewritten; the commit message says
plainly it's "moved," and the new copy in `install/terminal/cloud-clis.sh`
(commit `2a52211`) is byte-for-byte the same function, just filed
somewhere else, with a comment explaining why:

```bash
# omawsl_install_azure_cli [apt_sources_file] [keyrings_dir]
# Moved verbatim from install/terminal/cloud-tools.sh - Azure CLI now lives
# in its own OMAWSL_CLOUD_CLIS-driven picker, alongside AWS CLI and GCP CLI
# (design spec §3), not mixed in with the 8 programming languages.
omawsl_install_azure_cli() {
  ...
}
```

"Moved verbatim" is a deliberate choice, not laziness. Azure CLI's
install function already passed its own tests and had already survived a
real bug fix (the apt-repo codename fallback from Lesson 12). Rewriting
it "while we're in here" would risk reintroducing a bug that was already
fixed, for zero benefit — the function's *logic* isn't what this phase
is changing, only its *address*.

GCP CLI's installer (also in `cloud-clis.sh`) is new code, but it
deliberately reuses Azure CLI's exact shape — idempotency guard, a
`{ ... } || ok=0` block isolating repo-add failures, cleanup of a
partially-written apt source file on failure:

```bash
omawsl_install_gcp_cli() {
  local apt_sources_file="${1:-${OMAWSL_GCP_CLI_APT_SOURCES_FILE:-/etc/apt/sources.list.d/google-cloud-sdk.list}}"
  local keyrings_dir="${2:-${OMAWSL_GCP_CLI_APT_KEYRINGS_DIR:-/etc/apt/keyrings}}"

  if command -v gcloud &>/dev/null; then
    return 0
  fi

  local ok=1
  {
    if [[ ! -f "$apt_sources_file" ]]; then
      sudo install -m 0755 -d "$keyrings_dir" &&
      curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --yes --dearmor -o "$keyrings_dir/google.gpg" &&
      sudo tee "$apt_sources_file" >/dev/null <<< "deb [signed-by=$keyrings_dir/google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" &&
      sudo apt-get update -qq
    fi &&
    sudo apt-get install -y google-cloud-cli
  } || ok=0
  ...
```

The design spec's comment about this (§3) is worth reading precisely: a
new apt repository is, at the mechanical level, just two things — a
signing key (so `apt-get` trusts packages from it) written under
`/etc/apt/keyrings/`, and a one-line "where to find this vendor's
packages" file written under `/etc/apt/sources.list.d/`. `apt-get update`
picks up any `.list` file it finds there. GCP's version is actually
*simpler* than Azure's: Google publishes one `cloud-sdk` repo that covers
every Ubuntu release, so there's no equivalent of Azure's codename/jammy
fallback logic to reproduce — same shape, less to go wrong.

### AWS CLI: a different install mechanism, split into two functions on purpose

AWS doesn't publish an apt repository at all — its official installer is
a downloaded zip you run yourself (design spec §3): fetch
`awscli-exe-linux-<arch>.zip`, unzip it, and run the `install` script it
contains, as root. `omawsl_aws_cli_install_steps` is exactly those three
steps, unguarded:

```bash
omawsl_aws_cli_install_steps() {
  local tmp_dir; tmp_dir="$(mktemp -d)"
  local arch; arch="$(omawsl_aws_cli_arch)"
  local ok=1
  {
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$arch.zip" -o "$tmp_dir/awscliv2.zip" &&
    unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir" &&
    sudo "$tmp_dir/aws/install" --update
  } || ok=0
  rm -rf "$tmp_dir"

  if [[ "$ok" -eq 0 ]]; then
    echo "omawsl: AWS CLI install failed (download unreachable?) - skipping, continuing with the rest of the run."
    return 1
  fi
}
```

and `omawsl_install_aws_cli` is a thin, *guarded* wrapper around it:

```bash
omawsl_install_aws_cli() {
  if command -v aws &>/dev/null; then
    return 0
  fi
  omawsl_aws_cli_install_steps || true
}
```

Why split a straightforward install into two functions instead of one?
Because this tool needs to be callable two different ways, with two
different, *opposite* requirements around its own idempotency guard.
`install.sh` wants the guard (don't reinstall AWS CLI if it's already
there). But this phase also makes AWS CLI the 8th entry in the
"orphan tools" registry from Lesson 8 — Azure CLI and GCP CLI are
apt-installed, so a plain `sudo apt upgrade` already keeps them current,
but AWS CLI's own installer has no update command of its own, so
`omawsl update`'s job for this one tool is to *re-run the install steps
on an already-installed AWS CLI* — the exact case the guard exists to
prevent. Splitting the guard out into its own thin wrapper means
`orphan-tools.sh`'s update path can call `omawsl_aws_cli_install_steps`
directly, bypassing the guard on purpose, while `install.sh` keeps
calling the guarded `omawsl_install_aws_cli` and never has to know the
split exists. This is the same shape the project already used for
opencode's install/update split (`app-opencode.sh`) — not a new pattern,
reused deliberately.

### A real bug in that split, caught by its own tests

Look closely at `omawsl_aws_cli_install_steps` above and you'll notice
something: on failure, it prints a message *and* `return 1`s. That
`return 1` wasn't there in the first version. Commit `3636703` ("fix:
propagate AWS CLI install failure so omawsl update reports it
accurately") is the fix, and its commit message explains the bug
precisely:

> `omawsl_aws_cli_install_steps` always returned 0 even on failure, so
> the orphan-tools update-apply path's failure check for AWS CLI was
> dead code — `omawsl update` would print "updated AWS CLI" on a
> genuinely failed update.

This is worth sitting with, because it's a subtle failure mode: the bug
wasn't a crash, it was a function returning *success* when it should
have returned *failure* — the kind of bug that produces no error message
at all, just a wrong claim ("updated AWS CLI") after a download that
actually failed. The fix has two halves, and they go in *opposite*
directions on purpose:

```bash
# omawsl_aws_cli_install_steps: now propagates the real exit code
if [[ "$ok" -eq 0 ]]; then
  echo "omawsl: AWS CLI install failed (download unreachable?) - skipping, continuing with the rest of the run."
  return 1
fi

# omawsl_install_aws_cli: swallows it, deliberately, right here
omawsl_aws_cli_install_steps || true
```

The comment left on the guarded wrapper says exactly why the same
failure needs different treatment in its two callers:

> Unlike the update path (`bin/omawsl-sub/orphan-tools.sh`), which needs
> the real exit code to tell a failed update from a successful one, a
> failed install here must not abort the rest of an `install.sh` run
> (`set -e`) — so swallow it, same as `omawsl_install_azure_cli`/
> `omawsl_install_gcp_cli` above.

One function, one underlying failure, two callers with genuinely
different needs: `install.sh` needs "never crash the whole run over one
tool," `orphan-tools.sh` needs "tell me the truth about whether this
worked." Splitting the guard out is what makes both needs satisfiable
without either caller lying to the other.

### The mechanical cost, made visible: a stale test fixture

The outline calls out "updating tests to match" as part of this phase's
real cost, and there's a concrete, small example of exactly that in the
history. `install/terminal.sh` runs its scripts in a fixed order (an
array, from Lesson 1's dispatch table). Adding `cloud-clis.sh` to that
array is a one-line change — but `tests/terminal_test.bats` had a
separate, *hardcoded* fixture asserting exactly what that order should
be, and nothing in this phase's plan touched that test file, because no
task in the plan was "update terminal_test.bats." Commit `30ee34e`
("fix: add cloud-clis.sh to terminal_test.bats's expected script order")
is the fix, caught in the final whole-branch review rather than by any
individual task:

```diff
 terminal/select-dev-language.sh
 terminal/cloud-tools.sh
+terminal/cloud-clis.sh
 terminal/select-dev-storage.sh
```

Nothing about this bug is deep — it's a one-line list that needed a
second one-line addition somewhere else entirely. That's the point: a
consistent, single-source-of-truth registry (`items.sh`) doesn't
automatically protect *every* place a new category needs to show up.
`terminal.sh`'s own script-order array is a second, separate list that
also had to grow, and a test asserting on that list's exact contents is
a third place the same change had to land. "Add a category" touches more
files than it looks like it should, and a real review is what catches
the one that got missed.

### Wiring `cloud` through `install`, `uninstall`, and `doctor` — same shape, three files

With the registry and the install/uninstall code in place, the last step
is making the existing `storage` category's plumbing — already built in
Lesson 7 — grow a `cloud` twin in each of three files, one function per
file, same shape every time.

`bin/omawsl-sub/install.sh` gets an `omawsl_install_apply_cloud` /
`omawsl_install_category_cloud` pair, structurally identical to
storage's own pair:

```bash
omawsl_install_apply_cloud() {
  local picked="$1" existing="$2"
  local merged; merged="$(omawsl_merge_csv "$existing" "$picked")"
  export OMAWSL_CLOUD_CLIS="$merged"
  omawsl_save_choice OMAWSL_CLOUD_CLIS "$merged"
  source "$OMAWSL_ROOT_DIR/install/terminal/cloud-clis.sh"
  omawsl_cloud_clis
}
```

`bin/omawsl-sub/uninstall.sh`'s dispatch `case` gains one more arm,
grouping `azure|aws|gcp` the same way `ruby|node|go|...` is already
grouped for `language`:

```bash
azure|aws|gcp)
  label="$(omawsl_item_label "$slug")"
  source "$OMAWSL_ROOT_DIR/uninstall/cloud-clis.sh"
  omawsl_uninstall_cloud_cli "$label"
  ;;
```

and `bin/omawsl-sub/doctor.sh` gets a same-shaped `omawsl_doctor_cloud_installed`,
plumbed into the same generic `omawsl_doctor_report_category` loop every
other category already uses:

```bash
omawsl_doctor_cloud_installed() {
  local slug="$1"
  case "$slug" in
    azure) command -v az &>/dev/null ;;
    aws) command -v aws &>/dev/null ;;
    gcp) command -v gcloud &>/dev/null ;;
    *) return 1 ;;
  esac
}
```

None of these three functions is difficult on its own — each is a
handful of lines, copied from an existing sibling and adapted. The
lesson here is really about *count*: one new category means (at least)
seven touch points across this project — `items.sh` (three functions),
two install files (one shrinks, one grows), two uninstall files (same),
and `doctor.sh`. Miss any one of them and the picker either doesn't
appear, appears but does nothing, or appears and works for `install` but
reports nothing under `doctor`. That's the real, ongoing cost a
consistent taxonomy is paying for: not that any individual change is
hard, but that there's a fixed checklist to run through every time, and
skipping an item on it fails silently rather than loudly.

## 3. Exercise

Close this lesson and rebuild a scaled-down version of this refactor,
blind, in `practice/13-cloud-clis-menu/`. You are not rebuilding the
full `omawsl install`/`uninstall`/`doctor` command-line plumbing from
Lesson 7 again — that machinery already exists and isn't what this
lesson is about. Instead you're doing the two things this phase actually
adds: **splitting a category correctly across a shared registry**, and
**moving install/uninstall code to a new home without breaking either
end**.

The directory already contains some files, in the state they were in
right *before* this phase — read each one's own header comment before
touching anything:

- `lib.sh` — given, don't change it (`omawsl_list_has`, from an earlier
  lesson).
- `items.sh` — given, but **you must edit it**. Right now `azure` is
  filed under `"language"`, alongside `go` and `terraform`. Move it into
  a new `"cloud"` category, and register two brand-new slugs alongside
  it: `aws` (label `"AWS CLI"`) and `gcp` (label `"GCP CLI"`). `go` and
  `terraform` stay in `"language"` — only `azure` moves, exactly as in
  the real project.
- `cloud-tools.sh` — given, but **you must edit it**. It currently
  installs both Terraform and Azure CLI. Delete
  `omawsl_install_azure_cli` from this file entirely, and shrink
  `omawsl_cloud_tools` so it only ever installs Terraform.
- `uninstall-language.sh` — given, but **you must edit it**. Same
  operation on the uninstall side: delete `omawsl_uninstall_azure_cli`
  from this file, and remove its case arm from `omawsl_uninstall_language`
  (an unknown label like `"Azure CLI"` should now fall through to that
  function's existing error case).

You must also write three brand-new files, each with a header comment in
the practice directory spelling out the exact function names, arguments,
and required behavior — read those comments carefully, they are the
actual spec:

- `cloud-clis.sh` — the install side of the new category:
  `omawsl_install_azure_cli` (the function you just deleted from
  `cloud-tools.sh` — move it here, adapted or verbatim, your choice),
  `omawsl_install_gcp_cli`, `omawsl_aws_cli_install_steps` (unguarded),
  `omawsl_install_aws_cli` (guarded, swallows a failed
  `omawsl_aws_cli_install_steps` call), and `omawsl_cloud_clis` (the
  dispatcher, reading `OMAWSL_CLOUD_CLIS`).
- `uninstall-cloud-clis.sh` — the uninstall side, mirroring the above:
  `omawsl_uninstall_azure_cli` (moved from `uninstall-language.sh`),
  `omawsl_uninstall_gcp_cli`, `omawsl_uninstall_aws_cli`, and
  `omawsl_uninstall_cloud_cli <label>` (the dispatcher).
- `doctor-cloud.sh` — one function, `omawsl_doctor_cloud_installed <slug>`,
  a read-only `command -v` check per slug (`az`/`aws`/`gcloud`).

A few behavioral requirements the check in step 4 depends on, all
grounded in the real project's own commit history covered above:

- Every install function must be **idempotent** — if the tool is already
  reachable (`command -v`), it returns immediately without attempting to
  install anything again.
- Every uninstall function must be a **clean no-op** (exit 0, a friendly
  message, no error) when the tool isn't installed — including when
  called a second time right after a successful uninstall.
- `omawsl_cloud_clis`, given an empty or unset `OMAWSL_CLOUD_CLIS`, must
  install nothing at all — a valid, silent no-op, not an error.
- `omawsl_aws_cli_install_steps` must genuinely propagate a real failure
  (return non-zero) if `curl` or `unzip` or the installer itself fails —
  this is the exact bug fixed in commit `3636703`, covered above.
  `omawsl_install_aws_cli`, on the other hand, must **swallow** that same
  failure and still return success — the opposite requirement, for the
  opposite reason, also covered above.

Every file follows this project's usual convention: `set -euo pipefail`
at the top, and a guard at the bottom
(`if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ...; fi`) so each file can
be run standalone without anything happening on a plain `source`.

You will genuinely be calling `apt-get`, `curl`, `unzip`, `sudo`, `gpg`,
and `dpkg` from your own code, the same way the real project does —
don't work around that by skipping those calls. The check in the next
step contains those commands safely; your job is to write the code as if
it were really going to run them.

Don't look back at this lesson's code while you write it. Get something
you believe is correct, then move to the Check step.

## 4. Check

Run:

```bash
practice/13-cloud-clis-menu/check.sh
```

It never lets a real `apt-get`/`curl`/`unzip`/`sudo`/`gpg`/`dpkg` run —
every one of those commands is replaced, for the duration of the check
only, with a stand-in that records what it was asked to do and simulates
the *effect* of a real install (a fake `az`/`aws`/`gcloud` binary
appearing on a scratch, throwaway `PATH` entry) without ever touching a
real system package, a real third-party apt repository, or the network.
This is safe to run as many times as you like.

The check works through, in order: whether `items.sh`'s registry
correctly reports `azure`/`aws`/`gcp` under `"cloud"` (and `go`/
`terraform` still under `"language"`, with `azure` gone from there);
whether `cloud-tools.sh` and `uninstall-language.sh` genuinely no longer
handle Azure CLI (checked by sourcing each file *in isolation*, so this
can't accidentally pass just because your new `cloud-clis.sh` happens to
define the same function name); whether every slug the registry reports
under `"cloud"` is actually recognized, consistently, by your install
functions, your uninstall dispatcher, and your doctor check; whether
installing Azure CLI twice in a row only actually installs it once, and
uninstalling it twice in a row is safe both times; whether
`omawsl_cloud_clis` correctly reads a selection string and installs
exactly the tools named in it, no more and no fewer; and finally the AWS
CLI failure-propagation split described above, exercised directly by
simulating a failed download.

Every check prints its own `PASS:`/`FAIL:` line, and the script runs all
of them regardless of any earlier failure, so one run shows you
everything that's wrong at once. Read a `FAIL:` line as a description of
*behavior*, not a pointer at a line number — e.g. "`cloud-tools.sh`
should no longer define `omawsl_install_azure_cli`" means exactly that:
the function is still there, even though the exercise asked you to
delete it from that file (not just stop calling it). "`omawsl_item_slugs
cloud` expected the set {azure, aws, gcp}, got '...'" means your
registry and your install/uninstall/doctor code have drifted out of
agreement on what belongs in the category — go back to `items.sh` first.

A passing check means your solution is behaviorally correct even if it's
organized differently from the original — different variable names,
Azure CLI's apt-repo-add ceremony written more simply than the real
`cloud-clis.sh`'s jammy-codename fallback, all fine, none of that is
graded. If you want to compare approaches purely as a study aid
afterward, the real files are `install/terminal/cloud-clis.sh`,
`uninstall/cloud-clis.sh`, `bin/omawsl-sub/items.sh`, and
`bin/omawsl-sub/doctor.sh`'s `omawsl_doctor_cloud_installed` in this
repo — but only after your check passes, and only for style, never as
the grade.
