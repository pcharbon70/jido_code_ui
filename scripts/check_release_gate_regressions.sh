#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

failures=0

fail() {
  echo "FAIL: $1"
  failures=1
}

require_executable() {
  local path="$1"
  if [[ ! -x "$path" ]]; then
    fail "missing executable release-gate script: $path"
  fi
}

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    fail "missing release-gate dependency: $path"
  fi
}

require_contains() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if [[ ! -f "$file" ]]; then
    fail "cannot validate missing file $file ($description)"
    return
  fi

  if ! rg -q --fixed-strings "$pattern" "$file"; then
    fail "$description is missing in $file (expected: $pattern)"
  fi
}

required_scripts=(
  "scripts/run_governance_gates.sh"
  "scripts/validate_specs_governance.sh"
  "scripts/validate_guides_governance.sh"
  "scripts/validate_rfc_governance.sh"
  "scripts/run_conformance.sh"
  "scripts/run_release_readiness.sh"
  "scripts/check_release_gate_regressions.sh"
)

required_workflows=(
  ".github/workflows/specs-governance.yml"
  ".github/workflows/guides-governance.yml"
  ".github/workflows/rfc-governance.yml"
  ".github/workflows/conformance.yml"
  ".github/workflows/release-readiness.yml"
)

required_hooks=(
  ".githooks/pre-commit"
  ".githooks/pre-push"
)

for f in "${required_scripts[@]}"; do
  require_executable "$f"
done

for f in "${required_workflows[@]}"; do
  require_file "$f"
done

for f in "${required_hooks[@]}"; do
  require_executable "$f"
done

require_contains ".githooks/pre-commit" "./scripts/run_governance_gates.sh" "pre-commit governance gate parity"
require_contains ".githooks/pre-push" "./scripts/run_governance_gates.sh" "pre-push governance gate parity"
require_contains ".githooks/pre-push" "./scripts/run_conformance.sh --skip-governance" "pre-push conformance gate command"

require_contains ".github/workflows/conformance.yml" "Run governance gates (fail-fast)" "conformance workflow fail-fast governance stage"
require_contains ".github/workflows/conformance.yml" "./scripts/run_conformance.sh --skip-governance" "conformance workflow governance-skip execution"

require_contains ".github/workflows/release-readiness.yml" "pull_request:" "release-readiness PR trigger"
require_contains ".github/workflows/release-readiness.yml" "./scripts/check_release_gate_regressions.sh" "release-readiness regression probes"

require_contains "scripts/run_release_readiness.sh" "RELEASE_GATE_STAGE=" "release-readiness stage markers"
require_contains "scripts/run_release_readiness.sh" "RELEASE_GATE_RESULT=PASS" "release-readiness PASS marker"
require_contains "scripts/run_release_readiness.sh" "RELEASE_GATE_RESULT=FAIL" "release-readiness FAIL marker"

require_contains "scripts/run_conformance.sh" "CONFORMANCE_ALIGNMENT=PASS" "conformance alignment PASS marker"
require_contains "scripts/run_conformance.sh" "CONFORMANCE_ALIGNMENT=FAIL" "conformance alignment FAIL marker"

if [[ "$failures" -ne 0 ]]; then
  echo
  echo "Release gate regression checks failed."
  exit 1
fi

echo "Release gate regression checks passed."
