# Prerequisites

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
