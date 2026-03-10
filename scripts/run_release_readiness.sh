#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/run_release_readiness.sh [--report-only] [--skip-conformance] [--skip-tests]

Options:
  --report-only       Run governance + conformance alignment checks only.
  --skip-conformance  Skip conformance harness execution.
  --skip-tests        Skip full mix test execution.
USAGE
}

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

REPORT_ONLY=0
SKIP_CONFORMANCE=0
SKIP_TESTS=0

for arg in "$@"; do
  case "$arg" in
    --report-only) REPORT_ONLY=1 ;;
    --skip-conformance) SKIP_CONFORMANCE=1 ;;
    --skip-tests) SKIP_TESTS=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg"
      usage
      exit 1
      ;;
  esac
done

stage_marker() {
  local stage="$1"
  local state="$2"
  echo "RELEASE_GATE_STAGE=${stage}:${state}"
}

run_stage() {
  local position="$1"
  local stage_id="$2"
  local label="$3"
  shift 3

  echo "[$position/6] $label"
  stage_marker "$stage_id" "start"

  if "$@"; then
    stage_marker "$stage_id" "pass"
  else
    stage_marker "$stage_id" "fail"
    echo "Release readiness gate failed."
    echo "RELEASE_GATE_RESULT=FAIL"
    exit 1
  fi
}

echo "== Release Readiness Gate =="

run_stage "1" "1_specs_governance" "Validate specs governance" ./scripts/validate_specs_governance.sh
run_stage "2" "2_guides_governance" "Validate guides governance" ./scripts/validate_guides_governance.sh
run_stage "3" "3_rfc_governance" "Validate RFC governance" ./scripts/validate_rfc_governance.sh
run_stage "4" "4_rfc_debt_scan" "Scan RFC governance debt (strict)" ./scripts/scan_rfc_governance_debt.sh --strict

if [[ "$SKIP_CONFORMANCE" -eq 0 ]]; then
  if [[ "$REPORT_ONLY" -eq 1 ]]; then
    run_stage "5" "5_conformance" "Run conformance harness (report-only)" ./scripts/run_conformance.sh --report-only --skip-governance
  else
    run_stage "5" "5_conformance" "Run conformance harness" ./scripts/run_conformance.sh --skip-governance
  fi
else
  echo "[5/6] Conformance harness skipped (--skip-conformance)"
  stage_marker "5_conformance" "skipped"
fi

if [[ "$REPORT_ONLY" -eq 0 && "$SKIP_TESTS" -eq 0 ]]; then
  run_stage "6" "6_full_tests" "Run full test suite" mix test
elif [[ "$REPORT_ONLY" -eq 1 ]]; then
  echo "[6/6] Full test suite skipped (--report-only)"
  stage_marker "6_full_tests" "skipped_report_only"
else
  echo "[6/6] Full test suite skipped (--skip-tests)"
  stage_marker "6_full_tests" "skipped_flag"
fi

echo "Release readiness gate passed."
echo "RELEASE_GATE_RESULT=PASS"
