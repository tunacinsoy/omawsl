# Updating what omawsl installed

`omawsl update` pulls the latest omawsl and runs any pending migrations - but not everything
omawsl installs is updated the same way. Five groups, five answers:

## omawsl itself

Run `omawsl update`. This is always the first thing it does: `git pull` inside your omawsl
checkout, then pending migrations.

## Language runtimes

Ruby, Node.js, Go, PHP, Python, Elixir, Rust, Java - all managed by [mise](https://mise.jdx.dev).
Terraform - apt-managed, not mise. Either run `mise upgrade` (languages) or `sudo apt upgrade`
(Terraform) yourself, or re-run `omawsl install language <name>` (e.g. `omawsl install language
go`), which re-installs/re-pins to the latest release the same way the first install did.

## Cloud CLIs

Azure CLI and GCP CLI - both apt-managed. Run `sudo apt upgrade` yourself, or re-run `omawsl
install cloud <name>` (e.g. `omawsl install cloud azure`), which re-installs the latest package
the same way the first install did. AWS CLI has no native updater of its own - see "The rest"
below.

## System packages

Everything installed via `apt` - fzf, ripgrep, bat, eza, zoxide, Docker Engine, Neovim,
LazyGit, and the rest of the always-on terminal tool set. Run `sudo apt upgrade` like you would
for anything else on the system.

**Windows-side GUI apps** (VS Code, Cursor) aren't touched by omawsl at all, ever - they run
their own update lifecycle on Windows (VS Code's built-in updater, Cursor's own auto-update),
the same way omawsl never auto-installs them in the first place.

## The rest: `omawsl update`

Eight tools have no update command of their own - no apt package, no mise tool, nothing to
run yourself. `omawsl update` checks each one that's currently installed against its real
latest release, then offers a picker (pre-checked for anything outdated) to bring them
current:

- Zellij
- LazyDocker
- opencode
- Claude Code CLI
- Codex CLI
- Antigravity CLI
- GitHub Copilot CLI
- AWS CLI

If everything here is already confirmed up to date, `omawsl update` says so and skips the
picker - there's nothing for it to offer.
