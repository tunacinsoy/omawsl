#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/install/lib.sh"
  source "$REPO_ROOT/install/terminal/select-dev-language.sh"
  stub_command mise
  stub_command gem
}

@test "installs ruby and rails when Ruby on Rails is selected" {
  export OMAWSL_LANGUAGES="Ruby on Rails"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global ruby@latest"* ]]
  [[ "$(stub_calls)" == *"gem install rails --no-document"* ]]
}

@test "installs node when Node.js is selected" {
  export OMAWSL_LANGUAGES="Node.js"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global node@latest"* ]]
  [[ "$(stub_calls)" != *"gem install"* ]]
}

@test "installs go when Go is selected" {
  export OMAWSL_LANGUAGES="Go"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global go@latest"* ]]
}

@test "installs php when PHP is selected" {
  export OMAWSL_LANGUAGES="PHP"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global php@latest"* ]]
}

@test "installs python when Python is selected" {
  export OMAWSL_LANGUAGES="Python"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global python@latest"* ]]
}

@test "installs elixir when Elixir is selected" {
  export OMAWSL_LANGUAGES="Elixir"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global elixir@latest"* ]]
}

@test "installs rust when Rust is selected" {
  export OMAWSL_LANGUAGES="Rust"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global rust@latest"* ]]
}

@test "installs java when Java is selected" {
  export OMAWSL_LANGUAGES="Java"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global java@latest"* ]]
}

@test "installs multiple languages when several are selected" {
  export OMAWSL_LANGUAGES="Go,Rust,Python"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global go@latest"* ]]
  [[ "$(stub_calls)" == *"mise use --global rust@latest"* ]]
  [[ "$(stub_calls)" == *"mise use --global python@latest"* ]]
  [[ "$(stub_calls)" != *"php"* ]]
  [[ "$(stub_calls)" != *"java"* ]]
}

@test "does not treat Terraform or Azure CLI as languages (cloud-tools.sh's job)" {
  export OMAWSL_LANGUAGES="Terraform,Azure CLI"
  omawsl_select_dev_language
  [[ "$(stub_calls)" != *"mise use"* ]]
}

@test "selecting nothing installs no languages" {
  export OMAWSL_LANGUAGES=""
  omawsl_select_dev_language
  [[ "$(stub_calls)" != *"mise use"* ]]
}

@test "no-ops cleanly when OMAWSL_LANGUAGES is unset entirely" {
  unset OMAWSL_LANGUAGES
  run omawsl_select_dev_language
  [ "$status" -eq 0 ]
  [[ "$(stub_calls)" != *"mise use"* ]]
}
