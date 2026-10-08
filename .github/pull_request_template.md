## Summary

<!-- What this PR changes and why. -->

## Personal machine

Run `tests/machine/run` on the pushed head commit. It marks the commit `machine/personal` when every machine check passes.

## Corporate machine

<!--
The corporate laptop isn't ours: these rules keep every item safe on it (see CONTRIBUTING.md).
* Only omawsl's own commands (omawsl ...) and opening a new terminal.
* Never hand-edit VPN, proxy, .bashrc/.profile or any other existing config.
* No sudo.
* No network access beyond what omawsl already does.
* Every item says Do / Expect / Undo.
Replace <branch> with this PR's branch. Add feature items between "omawsl doctor" and "switch back".
Before switching back, fill in Tested commit with: git -C ~/.local/share/omawsl rev-parse --short HEAD
-->

- [ ] Read every item below first. If anything looks unsafe for this machine, stop and comment on this PR instead.
- [ ] **Do:** `omawsl update --ref <branch>` · **Expect:** `switching to '<branch>'`, no errors · **Undo:** the last item
- [ ] **Do:** open a new terminal · **Expect:** it starts as before: prompt and multiplexer · **Undo:** nothing to undo
- [ ] **Do:** `omawsl doctor` · **Expect:** no new [PENDING] lines or errors compared to master · **Undo:** nothing to undo
- [ ] **Do:** `omawsl update --ref master`, then open a new terminal · **Expect:** it starts as before · **Undo:** nothing to undo

Tested commit: `<sha>`
