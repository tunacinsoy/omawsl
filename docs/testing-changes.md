# Testing a change before it ships

`master` is what every omawsl install pulls on `omawsl update`, so **merging a pull request
releases it to everyone**. Test a change on real machines *before* merging it, while it's
still on its own branch.

## Why this works

Each machine runs whatever omawsl code is checked out in its own install folder
(`~/.local/share/omawsl`). Normally that's `master`. `omawsl update --ref <branch>` switches
*that one machine* to another branch, and later `omawsl update` runs keep following it. No
other machine is affected.

## The workflow

1. **Build the change on a branch** (`feat/...` or `fix/...`) in your working copy, and push
   it:

       git push -u origin feat/my-change

2. **Switch each machine you want to test on** (personal, corporate, ...):

       omawsl update --ref feat/my-change

   Open a new terminal - you're now running the branch.

3. **Found a problem?** Fix it in your working copy, `git push` again, then on the test
   machine:

       omawsl update

   It pulls the branch's latest commits, because the machine is following that branch.

4. **Happy with it?** Put every test machine back on `master`:

       omawsl update --ref master

   Then merge the pull request. That's the release.

5. **Optionally tag it** when a set of changes is worth naming (e.g. `v1.2.0`), with a GitHub
   release describing it.

## Don't forget a machine on a test branch

As long as a machine is on a branch other than `master`, both `omawsl update` and
`omawsl doctor` remind you:

    omawsl: this machine is testing 'feat/my-change', not master - go back with: omawsl update --ref master

## Good to know

- The branch must be **pushed to GitHub** - the machine fetches it from there. If it isn't,
  `--ref` says so and changes nothing.
- `--ref` refuses to switch if the install folder has local edits, same as `omawsl update`.
- **Going back to `master` moves the code, not what the branch did to the machine.** Tools a
  branch installed or config it wrote stay. Usually harmless, but worth remembering.
- **A brand-new machine** can install straight from a branch:

      curl -fsSL https://raw.githubusercontent.com/tunacinsoy/omawsl/master/boot.sh | OMAWSL_REF=feat/my-change bash

  Afterwards, `omawsl update --ref master` puts it on `master` like any other install.
