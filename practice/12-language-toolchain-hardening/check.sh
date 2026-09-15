#!/usr/bin/env bash
set -euo pipefail

# Strategy B (side effects: installs additional system "-dev" packages via
# apt). This check never lets a real apt-get or mise install happen: it
# defines its own `sudo` and `mise` functions that just record what they
# were asked to do, sources the learner's scripts (both files have a
# guarded dispatcher - `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]` - so
# sourcing them does not also invoke anything), and calls the functions
# under test directly. `sudo` is stubbed rather than `apt-get` because
# `sudo` execs its target directly - a same-process `apt-get` stub is never
# consulted for a `sudo apt-get ...` call.

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failed=0

practice_dir="$(cd "$(dirname "$0")" && pwd)"

# --- Part 1: libraries.sh's new "-dev" packages -------------------------

apt_log="$scratch/apt-calls.log"
sudo() { echo "sudo $*" >> "$apt_log"; return 0; }

if (
  cd "$scratch"
  HOME="$scratch"
  source "$practice_dir/libraries.sh"
  omawsl_install_libraries >/dev/null
); then
  echo "PASS: 'omawsl_install_libraries' ran without error"
else
  echo "FAIL: running 'omawsl_install_libraries' raised an error - check for a syntax or runtime error"
  failed=1
fi

apt_calls="$(cat "$apt_log" 2>/dev/null || echo '<no calls recorded>')"

for pkg in libcurl4-openssl-dev libgd-dev libicu-dev libzip-dev libonig-dev; do
  if [[ "$apt_calls" == *"$pkg"* ]]; then
    echo "PASS: apt-get install includes $pkg"
  else
    echo "FAIL: apt-get install is missing $pkg"
    failed=1
  fi
done

if [[ "$apt_calls" == *"build-essential"* && "$apt_calls" == *"postgresql-client-common"* ]]; then
  echo "PASS: the original library list is still intact"
else
  echo "FAIL: the original library list appears to have been altered or removed"
  failed=1
fi

# --- Part 2: select-dev-language.sh's erlang-before-elixir ordering -----

elixir_log="$scratch/mise-calls-elixir.log"
mise() { echo "mise $*" >> "$elixir_log"; return 0; }

if (
  cd "$scratch"
  HOME="$scratch"
  export OMAWSL_LANGUAGES="Elixir"
  source "$practice_dir/select-dev-language.sh"
  omawsl_select_dev_language >/dev/null
); then
  echo "PASS: 'omawsl_select_dev_language' ran without error for Elixir"
else
  echo "FAIL: running 'omawsl_select_dev_language' with Elixir selected raised an error"
  failed=1
fi

elixir_calls="$(cat "$elixir_log" 2>/dev/null || echo '<no calls recorded>')"

if [[ "$elixir_calls" == *"mise use --global erlang@latest"* ]]; then
  echo "PASS: selecting Elixir also installs erlang"
else
  echo "FAIL: selecting Elixir did not install erlang"
  failed=1
fi

if [[ "$elixir_calls" == *"mise use --global elixir@latest"* ]]; then
  echo "PASS: selecting Elixir installs elixir itself"
else
  echo "FAIL: selecting Elixir did not install elixir"
  failed=1
fi

if [[ "$elixir_calls" == *"erlang@latest"* && "$elixir_calls" == *"elixir@latest"* ]]; then
  erlang_pos="${elixir_calls%%mise use --global erlang@latest*}"
  elixir_pos="${elixir_calls%%mise use --global elixir@latest*}"
  if [ "${#erlang_pos}" -lt "${#elixir_pos}" ]; then
    echo "PASS: erlang is installed before elixir"
  else
    echo "FAIL: erlang must be installed before elixir (elixir's post-install needs erl already on PATH)"
    failed=1
  fi
else
  echo "FAIL: cannot check install order - erlang and/or elixir was never installed"
  failed=1
fi

# --- Part 3: a non-Elixir selection must not touch erlang at all --------

go_log="$scratch/mise-calls-go.log"
mise() { echo "mise $*" >> "$go_log"; return 0; }

if (
  cd "$scratch"
  HOME="$scratch"
  export OMAWSL_LANGUAGES="Go"
  source "$practice_dir/select-dev-language.sh"
  omawsl_select_dev_language >/dev/null
); then
  echo "PASS: 'omawsl_select_dev_language' ran without error for Go"
else
  echo "FAIL: running 'omawsl_select_dev_language' with Go selected raised an error"
  failed=1
fi

go_calls="$(cat "$go_log" 2>/dev/null || echo '<no calls recorded>')"

if [[ "$go_calls" == *"mise use --global go@latest"* ]]; then
  echo "PASS: selecting Go installs go"
else
  echo "FAIL: selecting Go did not install go"
  failed=1
fi

if [[ "$go_calls" != *"erlang"* ]]; then
  echo "PASS: selecting Go alone does not install erlang"
else
  echo "FAIL: selecting Go alone installed erlang too - erlang must only ride along with an Elixir selection"
  failed=1
fi

exit "$failed"
