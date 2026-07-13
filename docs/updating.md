# Updating what omawsl installed

`omawsl update` pulls the latest omawsl and runs any pending migrations - but not everything
omawsl installs is updated the same way. Four groups, four answers:

## omawsl itself

Run `omawsl update`. This is always the first thing it does: `git pull` inside your omawsl
checkout, then pending migrations.

## Language runtimes & cloud tools

Ruby, Node.js, Go, PHP, Python, Elixir, Rust, Java, Terraform, Azure CLI - all managed by
[mise](https://mise.jdx.dev). Either run `mise upgrade` yourself, or re-run
`omawsl install language <name>` (e.g. `omawsl install language go`), which re-pins to the
latest release the same way the first install did.

## System packages

Everything installed via `apt` - fzf, ripgrep, bat, eza, zoxide, Docker Engine, Neovim,
LazyGit, and the rest of the always-on terminal tool set. Run `sudo apt upgrade` like you would
for anything else on the system.

**Windows-side GUI apps** (VS Code, Cursor) aren't touched by omawsl at all, ever - they run
their own update lifecycle on Windows (VS Code's built-in updater, Cursor's own auto-update),
the same way omawsl never auto-installs them in the first place.

## The rest: `omawsl update`

Seven tools have no update command of their own - no apt package, no mise tool, nothing to
run yourself. `omawsl update` checks each one that's currently installed against its real
latest release, then offers a picker (pre-checked for anything outdated) to bring them
current:

- Zellij
- LazyDocker
- opencode
- Claude Code CLI
- Codex CLI
- Gemini CLI
- GitHub Copilot CLI

If everything here is already confirmed up to date, `omawsl update` says so and skips the
picker - there's nothing for it to offer.
