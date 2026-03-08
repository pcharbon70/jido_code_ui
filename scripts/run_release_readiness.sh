#!/usr/bin/env bash
set -euo pipefail

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

echo "== Release Readiness Gate =="

echo "[1/6] Validate specs governance"
stage_marker "1_specs_governance" "start"
./scripts/validate_specs_governance.sh
stage_marker "1_specs_governance" "pass"

echo "[2/6] Validate guides governance"
stage_marker "2_guides_governance" "start"
./scripts/validate_guides_governance.sh
stage_marker "2_guides_governance" "pass"

echo "[3/6] Validate RFC governance"
stage_marker "3_rfc_governance" "start"
./scripts/validate_rfc_governance.sh
stage_marker "3_rfc_governance" "pass"

echo "[4/6] Scan RFC governance debt (strict)"
stage_marker "4_rfc_debt_scan" "start"
./scripts/scan_rfc_governance_debt.sh --strict
stage_marker "4_rfc_debt_scan" "pass"

if [[ "$SKIP_CONFORMANCE" -eq 0 ]]; then
  echo "[5/6] Run conformance harness"
  stage_marker "5_conformance" "start"
  if [[ "$REPORT_ONLY" -eq 1 ]]; then
    ./scripts/run_conformance.sh --report-only --skip-governance
  else
    ./scripts/run_conformance.sh --skip-governance
  fi
  stage_marker "5_conformance" "pass"
else
  echo "[5/6] Conformance harness skipped (--skip-conformance)"
  stage_marker "5_conformance" "skipped"
fi

if [[ "$REPORT_ONLY" -eq 0 && "$SKIP_TESTS" -eq 0 ]]; then
  echo "[6/6] Run full test suite"
  stage_marker "6_full_tests" "start"
  mix test
  stage_marker "6_full_tests" "pass"
elif [[ "$REPORT_ONLY" -eq 1 ]]; then
  echo "[6/6] Full test suite skipped (--report-only)"
  stage_marker "6_full_tests" "skipped_report_only"
else
  echo "[6/6] Full test suite skipped (--skip-tests)"
  stage_marker "6_full_tests" "skipped_flag"
fi

echo "Release readiness gate passed."
echo "RELEASE_GATE_RESULT=PASS"
