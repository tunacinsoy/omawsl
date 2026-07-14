#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  gum_stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export HOME="$BATS_TEST_TMPDIR/home"
  export OMAWSL_STATE_DIR="$BATS_TEST_TMPDIR/state"
  mkdir -p "$HOME"
  stub_command sudo
  stub_command git
  stub_command curl
  stub_command gpg
  stub_command mise
  stub_command gem
  stub_command tar
  stub_command gh
  stub_hide_command docker terraform az lazydocker zellij code cursor claude codex gemini opencode

  export OMAWSL_WSL_CONF_FILE="$BATS_TEST_TMPDIR/wsl.conf"
  printf '[boot]\nsystemd=true\n' > "$OMAWSL_WSL_CONF_FILE"
  export OMAWSL_DOCKER_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/docker.list"
  export OMAWSL_DOCKER_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  # Pre-seed every third-party apt sources file this run could touch as
  # already-existing, so each one takes its "already configured" branch
  # and skips its curl|gpg / echo|tee repo-add pipes. Found during Phase
  # 2's Task 5: those pipes' stubbed sudo/curl/gpg exit near-instantly
  # without draining stdin (unlike the real commands), so when this whole
  # script runs as a freshly exec'd process the writer side can lose the
  # SIGPIPE race under pipefail (deterministic 141, not flaky). Every one
  # of these pipes already has dedicated, non-flaky coverage via a direct
  # in-process call in docker_test.bats/cloud_tools_test.bats, so this
  # loses no coverage.
  : > "$OMAWSL_DOCKER_APT_SOURCES_FILE"
  export OMAWSL_TERRAFORM_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/hashicorp.list"
  export OMAWSL_TERRAFORM_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  : > "$OMAWSL_TERRAFORM_APT_SOURCES_FILE"
  export OMAWSL_AZURE_CLI_APT_SOURCES_FILE="$BATS_TEST_TMPDIR/azure-cli.list"
  export OMAWSL_AZURE_CLI_APT_KEYRINGS_DIR="$BATS_TEST_TMPDIR/keyrings"
  : > "$OMAWSL_AZURE_CLI_APT_SOURCES_FILE"
  export USER=testuser
}

@test "runs the full install end to end and writes version state" {
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Engine only, inside WSL (recommended)"
  gum_stub_respond $'VS Code\nNeovim\nGitHub Copilot CLI'
  gum_stub_respond $'Go\nTerraform'
  gum_stub_respond ""
  gum_stub_respond "Nerd Font (enhanced)"
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  # VS Code was chosen and `code` is hidden (stub_hide_command above), so
  # windows-prereq-checklist.sh's VS Code item fires and its y/N prompt
  # reads stdin - answer "y" so the full install actually proceeds and
  # completes (mirrors the second @test's "echo n" pattern for its own,
  # deliberately-declined prompt).
  run bash -c "echo y | bash '$REPO_ROOT/install.sh'"

  [ "$status" -eq 0 ]
  [[ "$output" == *"install complete"* ]]
  [[ "$output" == *"remember to open a new terminal"* ]]
  [ -f "$HOME/.bashrc" ]
  [ -f "$HOME/.inputrc" ]
  [ -f "$OMAWSL_STATE_DIR/version" ]
  [ "$(cat "$OMAWSL_STATE_DIR/version")" = "$(cat "$REPO_ROOT/version")" ]
  [ -f "$OMAWSL_STATE_DIR/choices.env" ]
  grep -q '^OMAWSL_NETWORK_MODE="Personal / unrestricted"$' "$OMAWSL_STATE_DIR/choices.env"
  grep -q '^OMAWSL_EDITORS="VS Code,Neovim,GitHub Copilot CLI"$' "$OMAWSL_STATE_DIR/choices.env"
  grep -q '^OMAWSL_LANGUAGES="Go,Terraform"$' "$OMAWSL_STATE_DIR/choices.env"
  [[ "$(stub_calls)" == *"sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"* ]]
  [[ "$(stub_calls)" == *"mise use --global go@latest"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y terraform"* ]]
  [[ "$(stub_calls)" == *"sudo apt-get install -y fzf ripgrep bat eza zoxide plocate apache2-utils fd-find gh btop fastfetch lazygit"* ]]
  [ -f "$HOME/.vscode-server/data/Machine/settings.json" ]
  [[ "$(stub_calls)" == *"git clone https://github.com/LazyVim/starter $HOME/.config/nvim"* ]]
  [[ "$(stub_calls)" == *"gh extension install github/gh-copilot"* ]]
  [[ "$(stub_calls)" != *"cursor-server"* ]]
  # Not a bare "opencode" substring check: the gum stub logs its own
  # invocation verbatim, including every offered-but-unselected choice
  # (e.g. "gum choose --no-limit --header Editors & AI tooling ... VS
  # Code Neovim opencode Cursor ..."), so that would false-positive on
  # the option label alone. Assert against opencode's actual install
  # command instead (same string app_opencode_test.bats checks for).
  [[ "$(stub_calls)" != *"curl -fsSL https://opencode.ai/install"* ]]
}

@test "choosing Docker Desktop surfaces the pre-install checklist, and declining exits before installing" {
  # Relies on `docker` not being reachable via `command -v docker` -
  # already handled by setup()'s stub_hide_command call above.
  gum_stub_respond "Personal / unrestricted"
  gum_stub_respond "Docker Desktop for Windows"
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond ""
  gum_stub_respond "Cascadia Mono (zero install)"
  gum_stub_respond "Ada Lovelace"
  gum_stub_respond "ada@example.com"

  run bash -c "echo n | bash '$REPO_ROOT/install.sh'"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Docker Desktop"* ]]
  [[ "$output" == *"Exiting - nothing has been installed yet"* ]]
  [[ "$output" != *"install complete"* ]]
  [ ! -f "$HOME/.bashrc" ]
}
