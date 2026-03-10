#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

export MIX_ENV="${MIX_ENV:-test}"

SCENARIO_CATALOG="specs/conformance/scenario_catalog.md"
SPEC_CONFORMANCE_MATRIX="specs/conformance/spec_conformance_matrix.md"
CONFORMANCE_TEST_ROOT="test"
CONFORMANCE_SEED="${CONFORMANCE_SEED:-0}"
CONFORMANCE_MAX_FAILURES="${CONFORMANCE_MAX_FAILURES:-1}"

REPORT_ONLY=0
SKIP_GOVERNANCE=0

for arg in "$@"; do
  case "$arg" in
    --report-only) REPORT_ONLY=1 ;;
    --skip-governance) SKIP_GOVERNANCE=1 ;;
    *)
      echo "Unknown argument: $arg"
      echo "Usage: ./scripts/run_conformance.sh [--report-only] [--skip-governance]"
      exit 1
      ;;
  esac
done

read_scenarios() {
  local target="$1"
  if [[ -e "$target" ]]; then
    rg -o --no-filename 'SCN-[0-9]+' "$target" | sort -u || true
  fi
}

set_difference() {
  local left="$1"
  local right="$2"

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    if ! echo "$right" | grep -Fxq "$id"; then
      echo "$id"
    fi
  done <<< "$left"
}

count_list() {
  local values="$1"
  echo "$values" | sed '/^$/d' | wc -l | tr -d ' '
}

summarize_id_locations() {
  local id="$1"
  local target="$2"
  rg -n "$id" "$target" || true
}

requirement_families_for_id() {
  local id="$1"

  rg -n "$id" "$SPEC_CONFORMANCE_MATRIX" \
    | rg -o 'REQ-[A-Z]+-[0-9]{3}' \
    | sort -u \
    | paste -sd ',' - \
    || true
}

status_cell() {
  local list="$1"
  local id="$2"

  if echo "$list" | grep -Fxq "$id"; then
    echo "yes"
  else
    echo "no"
  fi
}

print_alignment_report() {
  local all_scenarios="$1"
  local catalog="$2"
  local matrix="$3"
  local tests="$4"

  echo
  echo "== Scenario Alignment Report =="
  echo "| Scenario | Catalog | Matrix | Tests | Requirement Families |"
  echo "|---|---|---|---|---|"

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue

    local catalog_status
    local matrix_status
    local test_status
    local requirements

    catalog_status="$(status_cell "$catalog" "$id")"
    matrix_status="$(status_cell "$matrix" "$id")"
    test_status="$(status_cell "$tests" "$id")"
    requirements="$(requirement_families_for_id "$id")"

    if [[ -z "$requirements" ]]; then
      requirements="-"
    fi

    echo "| $id | $catalog_status | $matrix_status | $test_status | $requirements |"
  done <<< "$all_scenarios"
}

failures_found=0

record_failure() {
  failures_found=1
}

if [[ "$SKIP_GOVERNANCE" -eq 0 ]]; then
  ./scripts/run_governance_gates.sh
fi

echo "== Conformance Scenario Discovery =="

CATALOG_SCENARIOS="$(read_scenarios "$SCENARIO_CATALOG")"
MATRIX_SCENARIOS="$(read_scenarios "$SPEC_CONFORMANCE_MATRIX")"
TEST_SCENARIOS="$(read_scenarios "$CONFORMANCE_TEST_ROOT")"
ALL_SCENARIOS="$(printf '%s\n%s\n%s\n' "$CATALOG_SCENARIOS" "$MATRIX_SCENARIOS" "$TEST_SCENARIOS" | sed '/^$/d' | sort -u)"

echo "Catalog scenarios: $(count_list "$CATALOG_SCENARIOS")"
echo "Matrix scenarios:  $(count_list "$MATRIX_SCENARIOS")"
echo "Test scenarios:    $(count_list "$TEST_SCENARIOS")"

echo "Scenarios in catalog: ${CATALOG_SCENARIOS//$'\n'/, }"
echo "Scenarios in matrix:  ${MATRIX_SCENARIOS//$'\n'/, }"
echo "Scenarios in tests:   ${TEST_SCENARIOS//$'\n'/, }"

print_alignment_report "$ALL_SCENARIOS" "$CATALOG_SCENARIOS" "$MATRIX_SCENARIOS" "$TEST_SCENARIOS"

MATRIX_MISSING_FROM_CATALOG="$(set_difference "$MATRIX_SCENARIOS" "$CATALOG_SCENARIOS")"
TESTS_MISSING_FROM_CATALOG="$(set_difference "$TEST_SCENARIOS" "$CATALOG_SCENARIOS")"
CATALOG_MISSING_FROM_MATRIX="$(set_difference "$CATALOG_SCENARIOS" "$MATRIX_SCENARIOS")"
CATALOG_MISSING_FROM_TESTS="$(set_difference "$CATALOG_SCENARIOS" "$TEST_SCENARIOS")"

if [[ -n "$MATRIX_MISSING_FROM_CATALOG" ]]; then
  record_failure
  echo
  echo "FAIL: matrix scenarios missing from scenario catalog:"
  echo "$MATRIX_MISSING_FROM_CATALOG"

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "-- matrix references for $id --"
    summarize_id_locations "$id" "$SPEC_CONFORMANCE_MATRIX"
  done <<< "$MATRIX_MISSING_FROM_CATALOG"
fi

if [[ -n "$TESTS_MISSING_FROM_CATALOG" ]]; then
  record_failure
  echo
  echo "FAIL: conformance tests reference scenarios missing from scenario catalog:"
  echo "$TESTS_MISSING_FROM_CATALOG"

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "-- test references for $id --"
    summarize_id_locations "$id" "$CONFORMANCE_TEST_ROOT"
  done <<< "$TESTS_MISSING_FROM_CATALOG"
fi

if [[ -n "$CATALOG_MISSING_FROM_MATRIX" ]]; then
  record_failure
  echo
  echo "FAIL: scenario catalog scenarios missing from conformance matrix:"
  echo "$CATALOG_MISSING_FROM_MATRIX"

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "-- catalog references for $id --"
    summarize_id_locations "$id" "$SCENARIO_CATALOG"
  done <<< "$CATALOG_MISSING_FROM_MATRIX"
fi

if [[ -n "$CATALOG_MISSING_FROM_TESTS" ]]; then
  record_failure
  echo
  echo "FAIL: scenario catalog scenarios missing from conformance tests:"
  echo "$CATALOG_MISSING_FROM_TESTS"

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    echo "-- catalog references for $id --"
    summarize_id_locations "$id" "$SCENARIO_CATALOG"
    echo "-- matrix references for $id --"
    summarize_id_locations "$id" "$SPEC_CONFORMANCE_MATRIX"
  done <<< "$CATALOG_MISSING_FROM_TESTS"
fi

if [[ "$failures_found" -eq 1 ]]; then
  echo
  echo "CONFORMANCE_ALIGNMENT=FAIL"
  exit 1
fi

echo "Scenario alignment checks passed."
echo "CONFORMANCE_ALIGNMENT=PASS"

if [[ "$REPORT_ONLY" -eq 1 ]]; then
  echo "Report-only mode enabled; skipping test execution."
  exit 0
fi

if ! rg -q '@(module)?tag[[:space:]]+:conformance' "$CONFORMANCE_TEST_ROOT" 2>/dev/null; then
  echo "FAIL: no conformance-tagged tests found under $CONFORMANCE_TEST_ROOT"
  exit 1
fi

echo "== Running deterministic conformance suite =="
echo "Conformance seed: $CONFORMANCE_SEED"
echo "Conformance max failures: $CONFORMANCE_MAX_FAILURES"
mix test --only conformance --seed "$CONFORMANCE_SEED" --max-failures "$CONFORMANCE_MAX_FAILURES"
