#!/usr/bin/env bats

load 'helpers/stubs'

setup() {
  stub_init
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  source "$REPO_ROOT/.github/scripts/check-corporate-checklist.sh"
  HEAD="0123456789abcdef0123456789abcdef01234567"
}

# body <corporate-section-lines...>
# A PR body with a Summary section and the given corporate section lines.
body() {
  printf '## Summary\n\nSomething.\n\n## Corporate machine\n\n'
  printf '%s\n' "$@"
}

@test "passes when every box is ticked and Tested commit matches head" {
  run omawsl_check_corporate_checklist "$(body '- [x] one' '- [x] two' '' 'Tested commit: 0123456')" "$HEAD"
  [ "$status" -eq 0 ]
  [[ "$output" == OK:* ]]
}

@test "fails and counts the unticked boxes" {
  run omawsl_check_corporate_checklist "$(body '- [x] one' '- [ ] two' '- [ ] three' 'Tested commit: 0123456')" "$HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: 2 unticked"* ]]
}

@test "fails when the section is missing" {
  run omawsl_check_corporate_checklist $'## Summary\n\n- [x] done\nTested commit: 0123456' "$HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: no '## Corporate machine' section"* ]]
}

@test "fails on an empty body" {
  run omawsl_check_corporate_checklist "" "$HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: no '## Corporate machine' section"* ]]
}

@test "fails when the section has no ticked box at all" {
  run omawsl_check_corporate_checklist "$(body 'Nothing to test here.' 'Tested commit: 0123456')" "$HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: no ticked items"* ]]
}

@test "fails on the template's <sha> placeholder" {
  run omawsl_check_corporate_checklist "$(body '- [x] one' 'Tested commit: <sha>')" "$HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: no 'Tested commit:' line"* ]]
}

@test "fails when Tested commit is a different commit" {
  run omawsl_check_corporate_checklist "$(body '- [x] one' 'Tested commit: fedcba9')" "$HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: Tested commit fedcba9 is not this PR's head ($HEAD)"* ]]
}

@test "fails when Tested commit is shorter than 7 characters" {
  run omawsl_check_corporate_checklist "$(body '- [x] one' 'Tested commit: 012345')" "$HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: no 'Tested commit:' line"* ]]
}

@test "accepts a backticked, uppercase, full-length Tested commit" {
  run omawsl_check_corporate_checklist "$(body '- [X] one' 'Tested commit: `0123456789ABCDEF0123456789ABCDEF01234567`')" "$HEAD"
  [ "$status" -eq 0 ]
}

@test "handles CRLF line endings from GitHub's web editor" {
  local crlf; crlf="$(body '- [x] one' 'Tested commit: 0123456' | sed 's/$/\r/')"
  run omawsl_check_corporate_checklist "$crlf" "$HEAD"
  [ "$status" -eq 0 ]
}

@test "ignores boxes inside HTML comments" {
  run omawsl_check_corporate_checklist "$(body '<!--' '- [ ] example rule' '-->' '- [x] one' 'Tested commit: 0123456')" "$HEAD"
  [ "$status" -eq 0 ]
}

@test "ignores unticked boxes in other sections" {
  run omawsl_check_corporate_checklist "$(body '- [x] one' 'Tested commit: 0123456' '' '## Notes' '- [ ] later idea')" "$HEAD"
  [ "$status" -eq 0 ]
}

@test "accepts a longer heading like '## Corporate machine checklist'" {
  run omawsl_check_corporate_checklist $'## Corporate machine checklist\n- [x] one\nTested commit: 0123456' "$HEAD"
  [ "$status" -eq 0 ]
}

@test "executed directly, it reads PR_BODY and HEAD_SHA from the environment" {
  PR_BODY="$(body '- [ ] one' 'Tested commit: 0123456')" HEAD_SHA="$HEAD" \
    run bash "$REPO_ROOT/.github/scripts/check-corporate-checklist.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: 1 unticked"* ]]
}

@test "the PR template as-is fails the check: nothing ticked, no commit" {
  run omawsl_check_corporate_checklist "$(cat "$REPO_ROOT/.github/pull_request_template.md")" "$HEAD"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL: 5 unticked"* ]]
  [[ "$output" == *"FAIL: no 'Tested commit:' line"* ]]
}

@test "the PR template passes once every box is ticked and the commit filled in" {
  local filled
  filled="$(sed -e 's/- \[ \]/- [x]/' -e 's/^Tested commit: <sha>$/Tested commit: 0123456/' \
    "$REPO_ROOT/.github/pull_request_template.md")"
  run omawsl_check_corporate_checklist "$filled" "$HEAD"
  [ "$status" -eq 0 ]
}

@test "the workflow passes the PR body via env, never inline in a run: line" {
  local wf="$REPO_ROOT/.github/workflows/corporate-checklist.yml"
  grep -q 'PR_BODY: ${{ github.event.pull_request.body }}' "$wf"
  grep -q 'HEAD_SHA: ${{ github.event.pull_request.head.sha }}' "$wf"
  ! grep -E '^[[:space:]]*run:.*\$\{\{' "$wf"
}

@test "the workflow re-runs when the PR description is edited (ticking a box)" {
  grep -qE 'types: \[opened, edited, synchronize, reopened\]' "$REPO_ROOT/.github/workflows/corporate-checklist.yml"
}
