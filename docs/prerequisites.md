# Prerequisites

> **Interim document.** This file is a stopgap, not part of the design spec's documented
> structure (`docs/superpowers/specs/2026-07-05-omawsl-design.md` §13, §16). The spec's actual
> home for this content is one canonical quick-reference table in `docs/windows-setup.md`,
> reused as-is by `README.md`'s "Before you begin" section (proactive framing) and by
> `install/windows-prereq-checklist.sh` (reactive framing) - never duplicated across files.
> Both `docs/windows-setup.md` and `README.md` are Phase 6 deliverables and don't exist yet.
> **When Phase 6 builds them:** fold this file's content into that canonical table, delete this
> file, and update `install/terminal/app-gh-copilot.sh`'s failure message (currently pointing at
> `docs/prerequisites.md#github-copilot-cli`) to point at the new location instead - do not leave
> a dangling reference to a deleted file.

A couple of `OMAWSL_EDITORS` picks need one thing set up *before* running `install.sh`, so the
whole run completes in one uninterrupted pass instead of partially failing partway through.

## GitHub Copilot CLI

Installing GitHub Copilot CLI runs `gh extension install github/gh-copilot`, which requires an
authenticated `gh` session. On a fresh machine nobody has done this yet, so if you're going to
select "GitHub Copilot CLI" in the Editors & AI tooling picker, run this first:

```bash
gh auth login
```

If you skip this and pick GitHub Copilot CLI anyway, `install.sh` won't lose any other progress
(the failure is isolated and reported) - but the extension won't install, and you'll need to run
`gh auth login` yourself afterward, then either `gh extension install github/gh-copilot` or
re-run `install.sh`.

## VS Code / Cursor

omawsl never auto-installs Windows-side software (VS Code and Cursor are both Windows GUI apps
omawsl only detects and configures, never installs). If you already know you'll want one of
them, installing it on Windows *before* running `install.sh` - then connecting it to this WSL
distro at least once (Remote-WSL for VS Code, its own WSL integration for Cursor) - means the
pre-install checklist has nothing to flag, and the shared settings/extension steps apply
immediately instead of waiting for the editor to connect later.

If you skip this and pick VS Code or Cursor anyway, nothing fails: `install.sh` still deploys the
shared baseline settings file (inert until the editor first connects), skips only the step that
needs the live CLI, and tells you what to do afterward.
