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
  # gem install rails happens via `mise exec ruby@latest -- gem install ...`,
  # a single call into the stubbed `mise` function - the `gem` stub is never
  # separately invoked for this. Assert the exact literal command.
  [[ "$(stub_calls)" == *"mise use --global ruby@latest"* ]]
  [[ "$(stub_calls)" == *"mise exec ruby@latest -- gem install rails --no-document"* ]]
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

@test "installs erlang before elixir when Elixir is selected" {
  export OMAWSL_LANGUAGES="Elixir"
  omawsl_select_dev_language
  local calls; calls="$(stub_calls)"
  [[ "$calls" == *"mise use --global erlang@latest"* ]]
  [[ "$calls" == *"mise use --global elixir@latest"* ]]
  # erlang must be installed first - elixir's own post-install step needs
  # `erl` already on PATH, or it fails looking for it.
  local erlang_pos elixir_pos
  erlang_pos="${calls%%mise use --global erlang@latest*}"
  elixir_pos="${calls%%mise use --global elixir@latest*}"
  [ "${#erlang_pos}" -lt "${#elixir_pos}" ]
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

@test "installs all eight languages when all are selected" {
  export OMAWSL_LANGUAGES="Ruby on Rails,Node.js,Go,PHP,Python,Elixir,Rust,Java"
  omawsl_select_dev_language
  [[ "$(stub_calls)" == *"mise use --global ruby@latest"* ]]
  [[ "$(stub_calls)" == *"mise exec ruby@latest -- gem install rails --no-document"* ]]
  [[ "$(stub_calls)" == *"mise use --global node@latest"* ]]
  [[ "$(stub_calls)" == *"mise use --global go@latest"* ]]
  [[ "$(stub_calls)" == *"mise use --global php@latest"* ]]
  [[ "$(stub_calls)" == *"mise use --global python@latest"* ]]
  [[ "$(stub_calls)" == *"mise use --global erlang@latest"* ]]
  [[ "$(stub_calls)" == *"mise use --global elixir@latest"* ]]
  [[ "$(stub_calls)" == *"mise use --global rust@latest"* ]]
  [[ "$(stub_calls)" == *"mise use --global java@latest"* ]]
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
