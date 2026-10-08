# Contributing

`master` is what every `omawsl update` pulls, so merging is shipping. Nothing reaches `master` until its exact head commit has been tested on **both** a personal and a corporate machine. GitHub enforces this for everyone, admins and AI tools included.

## The flow

1. Work on a branch, push it, open a PR. The template adds the two sections below.
2. **Personal machine (automated).** From a checkout of the branch, with the head commit pushed:

   ```bash
   tests/machine/run
   ```

   This runs every check in `tests/machine/*.bats` against the real machine, inside a sandbox: a temporary copy of the commit, a throwaway `HOME`, no sudo, no Windows side. A before/after fingerprint fails the run if anything real changed. When all pass, it marks the commit `machine/personal` on GitHub. `--no-report` runs without marking.
3. **Corporate machine (by hand).** Work through the PR's `## Corporate machine` checklist on the corporate laptop. Tick each item as you go, and fill in `Tested commit:` with the commit you tested. The `corporate-checklist` check passes once every box is ticked and that commit is the PR's head.
4. Merge. Any new push, or a branch that has fallen behind `master`, means re-testing both machines. The checks only count for the exact commit that lands.

## Adding a feature

- **Machine checks:** add `tests/machine/<feature>.bats` for what the feature brings: real downloads, real binaries, real shell start-up. The runner's sandbox keeps them safe. A check never needs sudo, and anything it writes goes to the throwaway `HOME`.
- **Corporate items:** add them to the PR's checklist between `omawsl doctor` and the switch back. The corporate laptop isn't ours, so every item:
  - uses only omawsl's own commands (`omawsl ...`) and opening a new terminal;
  - never hand-edits VPN, proxy, `.bashrc`/`.profile` or other existing config;
  - needs no sudo, and no network access beyond what omawsl already does;
  - says **Do / Expect / Undo**.

## The ruleset

`.github/rulesets/master.json` is the rule GitHub enforces on `master`:
- changes arrive only through PRs;
- both checks above are required on an up-to-date branch;
- there is no bypass.

It was applied once with:

```bash
gh api -X POST repos/tunacinsoy/omawsl/rulesets --input .github/rulesets/master.json
```

To change it, edit the JSON in a PR, then update the live ruleset by id: `gh api repos/tunacinsoy/omawsl/rulesets` lists it.

`corporate-checklist` is pinned to GitHub Actions (app id 15368), so a status posted by hand under that name doesn't count.

**Trust model:** GitHub can't know that a person really did a corporate step, only that the box is ticked. The gate stops accidental and automated merges, not deliberate false ticks.

**For people and AI tools alike:** Never edit the gate's own files (`.github/scripts/check-corporate-checklist.sh`, `.github/workflows/corporate-checklist.yml`, `.github/rulesets/master.json`, `tests/machine/run`) to get a red check to pass, and never post `machine/personal` or `corporate-checklist` by hand. A red check means a machine hasn't been tested yet. Test it, or ask the maintainer.
