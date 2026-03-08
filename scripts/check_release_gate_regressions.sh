#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

required_scripts=(
  "scripts/validate_specs_governance.sh"
  "scripts/validate_guides_governance.sh"
  "scripts/validate_rfc_governance.sh"
  "scripts/run_conformance.sh"
  "scripts/run_release_readiness.sh"
)

required_workflows=(
  ".github/workflows/specs-governance.yml"
  ".github/workflows/guides-governance.yml"
  ".github/workflows/rfc-governance.yml"
  ".github/workflows/conformance.yml"
)

for f in "${required_scripts[@]}"; do
  if [[ ! -x "$f" ]]; then
    echo "FAIL: missing executable release-gate script: $f"
    exit 1
  fi
done

for f in "${required_workflows[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "FAIL: missing release-gate workflow: $f"
    exit 1
  fi
done

echo "Release gate regression checks passed."
