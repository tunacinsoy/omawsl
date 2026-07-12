#!/usr/bin/env bash
# Shared slug<->label registry, one flat namespace across every option
# `bin/omawsl install`/`bin/omawsl uninstall` can target by a short
# lowercase slug (design spec §14's own examples: "install language go",
# "install editor vscode"). One place, reused by install.sh, uninstall.sh,
# and doctor.sh, so they never drift out of sync on what a name means.

# omawsl_item_category <slug>
omawsl_item_category() {
  case "$1" in
    ruby|node|go|php|python|elixir|rust|java|terraform|azure) echo "language" ;;
    vscode|neovim|opencode|cursor|claude|codex|gh-copilot|gemini) echo "editor" ;;
    mysql|redis|postgresql) echo "storage" ;;
    docker) echo "docker" ;;
    *) return 1 ;;
  esac
}

# omawsl_item_label <slug>
# The exact string used in choices.env's comma-delimited lists
# (OMAWSL_LANGUAGES/OMAWSL_EDITORS/OMAWSL_STORAGE) and passed to each
# uninstall/*.sh function - matches install/first-run-choices.sh's own gum
# choose option strings verbatim.
omawsl_item_label() {
  case "$1" in
    ruby) echo "Ruby on Rails" ;;
    node) echo "Node.js" ;;
    go) echo "Go" ;;
    php) echo "PHP" ;;
    python) echo "Python" ;;
    elixir) echo "Elixir" ;;
    rust) echo "Rust" ;;
    java) echo "Java" ;;
    terraform) echo "Terraform" ;;
    azure) echo "Azure CLI" ;;
    vscode) echo "VS Code" ;;
    neovim) echo "Neovim" ;;
    opencode) echo "opencode" ;;
    cursor) echo "Cursor" ;;
    claude) echo "Claude Code CLI" ;;
    codex) echo "Codex CLI" ;;
    gh-copilot) echo "GitHub Copilot CLI" ;;
    gemini) echo "Gemini CLI" ;;
    mysql) echo "MySQL" ;;
    redis) echo "Redis" ;;
    postgresql) echo "PostgreSQL" ;;
    *) return 1 ;;
  esac
}

# omawsl_item_slugs <category>
# All slugs for one category, in install/first-run-choices.sh's own
# picker order.
omawsl_item_slugs() {
  case "$1" in
    language) printf '%s\n' ruby node go php python elixir rust java terraform azure ;;
    editor) printf '%s\n' vscode neovim opencode cursor claude codex gh-copilot gemini ;;
    storage) printf '%s\n' mysql redis postgresql ;;
    *) return 1 ;;
  esac
}
