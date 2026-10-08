#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RULESET="$REPO_ROOT/.github/rulesets/master.json"
}

@test "the ruleset requires exactly the two checks the runner and the workflow produce" {
  run jq -r '.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context' "$RULESET"
  [ "$status" -eq 0 ]
  [ "$(sort <<< "$output")" = "$(printf 'corporate-checklist\nmachine/personal')" ]
  grep -q '^OMAWSL_MACHINE_STATUS_CONTEXT="machine/personal"$' "$REPO_ROOT/tests/machine/run"
  grep -qE '^  corporate-checklist:$' "$REPO_ROOT/.github/workflows/corporate-checklist.yml"
}

@test "the ruleset has no bypass and requires up-to-date branches" {
  [ "$(jq '.bypass_actors | length' "$RULESET")" -eq 0 ]
  [ "$(jq '.rules[] | select(.type == "required_status_checks") | .parameters.strict_required_status_checks_policy' "$RULESET")" = true ]
  [ "$(jq -r '.enforcement' "$RULESET")" = active ]
}

@test "the ruleset only allows changes through pull requests and protects master itself" {
  run jq -r '.rules[].type' "$RULESET"
  [[ "$output" == *pull_request* ]]
  [[ "$output" == *deletion* ]]
  [[ "$output" == *non_fast_forward* ]]
  [ "$(jq -r '.conditions.ref_name.include[0]' "$RULESET")" = "~DEFAULT_BRANCH" ]
}

@test "CONTRIBUTING.md documents both machines and how the ruleset is applied" {
  local doc="$REPO_ROOT/CONTRIBUTING.md"
  grep -q 'tests/machine/run' "$doc"
  grep -q '## Corporate machine' "$doc"
  grep -q 'gh api -X POST repos/tunacinsoy/omawsl/rulesets --input .github/rulesets/master.json' "$doc"
}
