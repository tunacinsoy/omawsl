#!/usr/bin/env bats

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
DOC="$REPO_ROOT/docs/testing-changes.md"

@test "docs/testing-changes.md walks through testing a branch before merging" {
  for s in "omawsl update --ref feat/" "omawsl update --ref master" "git push" "OMAWSL_REF=" "omawsl doctor"; do
    grep -qF "$s" "$DOC" || { echo "missing: $s"; return 1; }
  done
}

@test "README and docs/updating.md link to it" {
  grep -q "docs/testing-changes.md" "$REPO_ROOT/README.md"
  grep -q "testing-changes.md" "$REPO_ROOT/docs/updating.md"
}
