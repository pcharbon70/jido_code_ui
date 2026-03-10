#!/usr/bin/env bash
set -euo pipefail

ROOT="${GOVERNANCE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

MATRIX="specs/conformance/spec_conformance_matrix.md"
SCENARIO_CATALOG="specs/conformance/scenario_catalog.md"
COMPONENT_SPEC_REGEX='^specs/(core|infrastructure|services|session)/.+\.md$'

failures=0

fail() {
  echo "FAIL: $1"
  failures=1
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

diff_for_file() {
  local file="$1"
  if [[ -n "${DIFF_RANGE:-}" ]]; then
    git diff "$DIFF_RANGE" -- "$file" || true
  else
    {
      git diff -- "$file"
      git diff --cached -- "$file"
    } || true
  fi
}

if [[ ! -f "$MATRIX" ]]; then
  echo "ERROR: missing conformance matrix: $MATRIX"
  exit 1
fi

if [[ ! -f "$SCENARIO_CATALOG" ]]; then
  echo "ERROR: missing scenario catalog: $SCENARIO_CATALOG"
  exit 1
fi

COMPONENT_SPECS="$(rg -l '\`AC-[0-9]{2}\`' specs | sort | rg -v '^specs/conformance/' || true)"
KNOWN_SCENARIOS="$(rg -o 'SCN-[0-9]+' "$SCENARIO_CATALOG" | sort -u || true)"
MATRIX_SCENARIOS="$(rg -o 'SCN-[0-9]+' "$MATRIX" | sort -u || true)"

if [[ -z "$COMPONENT_SPECS" ]]; then
  echo "INFO: no component specs with AC entries were found."
  echo "INFO: skipping AC-to-REQ/SCN mapping checks (bootstrap mode)."
else
  echo "Checking control-plane matrix references in component specs..."
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if ! rg -q 'control_plane_ownership_matrix\.md' "$f"; then
      fail "missing control-plane matrix reference in $f"
    fi

    if ! rg -q '^## Control Plane$' "$f"; then
      fail "missing required '## Control Plane' section in $f"
    fi

    if ! rg -q '^Primary control-plane ownership:' "$f"; then
      fail "missing primary control-plane ownership declaration in $f"
    fi
  done <<< "$COMPONENT_SPECS"

  echo "Checking AC coverage mappings in conformance matrix..."
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    rows="$(grep -F "| \`$f\` |" "$MATRIX" || true)"
    row_count="$(echo "$rows" | sed '/^$/d' | wc -l | tr -d ' ')"

    if [[ "$row_count" -gt 1 ]]; then
      fail "duplicate conformance rows found for $f"
      continue
    fi

    row="$(echo "$rows" | head -n1 || true)"

    if [[ -z "$row" ]]; then
      fail "missing conformance row for $f"
      continue
    fi

    req_col="$(echo "$row" | awk -F'|' '{print $4}')"
    scn_col="$(echo "$row" | awk -F'|' '{print $5}')"

    if ! echo "$req_col" | rg -q '\`REQ-[A-Z]'; then
      fail "conformance row for $f does not include REQ mapping"
    fi

    if ! echo "$scn_col" | rg -q '\`SCN-[0-9]+'; then
      fail "conformance row for $f does not include SCN mapping"
    fi

    while IFS= read -r scn; do
      [[ -z "$scn" ]] && continue
      if ! echo "$KNOWN_SCENARIOS" | grep -Fxq "$scn"; then
        fail "conformance row for $f references unknown scenario id: $scn"
      fi
    done < <(echo "$scn_col" | rg -o 'SCN-[0-9]+' || true)
  done <<< "$COMPONENT_SPECS"
fi

echo "Checking governance-critical specs for unresolved TODO placeholders..."
GOVERNANCE_CRITICAL_SPECS="$({
  echo "$COMPONENT_SPECS"
  echo "specs/operations/rfc_intake_governance.md"
  echo "specs/operations/release_governance_and_rollout.md"
} | sed '/^$/d' | sort -u)"

while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  [[ -f "$f" ]] || continue

  if rg -n 'TODO' "$f" >/dev/null; then
    fail "unresolved TODO placeholder detected in governance-critical spec: $f"
    rg -n 'TODO' "$f" || true
  fi
done <<< "$GOVERNANCE_CRITICAL_SPECS"

echo "Checking scenario catalog and conformance matrix alignment..."
MATRIX_MISSING_FROM_CATALOG="$(set_difference "$MATRIX_SCENARIOS" "$KNOWN_SCENARIOS")"
CATALOG_MISSING_FROM_MATRIX="$(set_difference "$KNOWN_SCENARIOS" "$MATRIX_SCENARIOS")"

if [[ -n "$MATRIX_MISSING_FROM_CATALOG" ]]; then
  fail "conformance matrix references unknown scenario IDs:"
  echo "$MATRIX_MISSING_FROM_CATALOG"
fi

if [[ -n "$CATALOG_MISSING_FROM_MATRIX" ]]; then
  fail "scenario catalog IDs are missing from conformance matrix:"
  echo "$CATALOG_MISSING_FROM_MATRIX"
fi

echo "Checking canonical runtime namespace references..."
NAMESPACE_PATHS=(
  specs/contracts
  specs/conformance
  specs/core
  specs/infrastructure
  specs/services
  specs/session
)
EXISTING_NAMESPACE_PATHS=()

for p in "${NAMESPACE_PATHS[@]}"; do
  if [[ -d "$p" ]]; then
    EXISTING_NAMESPACE_PATHS+=("$p")
  fi
done

if [[ "${#EXISTING_NAMESPACE_PATHS[@]}" -gt 0 ]]; then
  NAMESPACE_DRIFT="$(rg -n '\bWebUi\b|\bJido\.Os\b|\bJidoOs\b|\bJido\.OS\b|\bJido\.os\b|\bJido_Os\b' "${EXISTING_NAMESPACE_PATHS[@]}" || true)"
else
  NAMESPACE_DRIFT=""
fi

if [[ -n "$NAMESPACE_DRIFT" ]]; then
  fail "non-canonical namespace reference detected (expected JidoCodeUi.*):"
  echo "$NAMESPACE_DRIFT"
fi

DIFF_BASE="${DIFF_BASE:-}"
DIFF_HEAD="${DIFF_HEAD:-}"
DIFF_RANGE=""
CHANGED_FILES=""

if [[ -n "$DIFF_BASE" && -n "$DIFF_HEAD" ]] \
  && git rev-parse --verify "${DIFF_BASE}^{commit}" >/dev/null 2>&1 \
  && git rev-parse --verify "${DIFF_HEAD}^{commit}" >/dev/null 2>&1; then
  DIFF_RANGE="${DIFF_BASE}..${DIFF_HEAD}"
fi

if [[ -n "$DIFF_RANGE" ]]; then
  echo "Checking change-policy governance rules for $DIFF_RANGE..."
  CHANGED_FILES="$(git diff --name-only "$DIFF_RANGE" -- \
    specs \
    .github/workflows/specs-governance.yml \
    scripts/validate_specs_governance.sh || true)"
else
  CHANGED_FILES="$({
      git diff --name-only -- specs .github/workflows/specs-governance.yml scripts/validate_specs_governance.sh
      git diff --name-only --cached -- specs .github/workflows/specs-governance.yml scripts/validate_specs_governance.sh
    } | sort -u | sed '/^$/d')"
fi

if [[ -n "$CHANGED_FILES" ]]; then
  if [[ -z "$DIFF_RANGE" ]]; then
    echo "Checking change-policy governance rules for local workspace changes..."
  fi

  CHANGED_COMPONENT_MARKDOWN="$(echo "$CHANGED_FILES" | rg "$COMPONENT_SPEC_REGEX" || true)"
  CHANGED_AC_COMPONENTS=""

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if echo "$COMPONENT_SPECS" | grep -Fxq "$f"; then
      CHANGED_AC_COMPONENTS="${CHANGED_AC_COMPONENTS}${f}"$'\n'
    fi
  done <<< "$CHANGED_COMPONENT_MARKDOWN"

  COMPONENT_CHANGED=0
  CONTRACT_CHANGED=0
  MATRIX_CHANGED=0
  SCENARIO_CATALOG_CHANGED=0
  ADR_CHANGED=0
  ARCH_BASELINE_CHANGED=0
  AC_SHAPE_CHANGED=0
  BEHAVIOR_SHAPE_CHANGED=0

  if [[ -n "$CHANGED_COMPONENT_MARKDOWN" ]]; then
    COMPONENT_CHANGED=1
  fi

  if echo "$CHANGED_FILES" | rg -q '^specs/contracts/.+\.md$'; then
    CONTRACT_CHANGED=1
  fi

  if echo "$CHANGED_FILES" | rg -q '^specs/conformance/spec_conformance_matrix\.md$'; then
    MATRIX_CHANGED=1
  fi

  if echo "$CHANGED_FILES" | rg -q '^specs/conformance/scenario_catalog\.md$'; then
    SCENARIO_CATALOG_CHANGED=1
  fi

  if echo "$CHANGED_FILES" | rg -q '^specs/adr/ADR-[0-9]{4}-.+\.md$'; then
    ADR_CHANGED=1
  fi

  if echo "$CHANGED_FILES" | rg -q '^specs/(contracts/.+\.md|design\.md|topology\.md|boundaries\.md|control_planes\.md|targets\.md)$'; then
    ARCH_BASELINE_CHANGED=1
  fi

  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    file_diff="$(diff_for_file "$f")"

    if echo "$file_diff" | rg -q '^[+-].*\`AC-[0-9]{2}\`'; then
      AC_SHAPE_CHANGED=1
    fi

    if echo "$file_diff" | rg -q '^[+-].*(MUST|SHALL|REQUIRED|state|terminal|typed|envelope|workflow|retry|timeout|parity|replay)'; then
      BEHAVIOR_SHAPE_CHANGED=1
    fi
  done <<< "$CHANGED_AC_COMPONENTS"

  if [[ -n "$CHANGED_AC_COMPONENTS" ]]; then
    if [[ "$CONTRACT_CHANGED" -eq 0 ]]; then
      fail "AC-bearing component spec changes require at least one contract update in specs/contracts."
    fi

    if [[ "$MATRIX_CHANGED" -eq 0 ]]; then
      fail "AC-bearing component spec changes require conformance matrix updates."
    fi
  fi

  if [[ "$AC_SHAPE_CHANGED" -eq 1 && "$MATRIX_CHANGED" -eq 0 ]]; then
    fail "added/removed AC entries require conformance matrix updates."
  fi

  if [[ "$BEHAVIOR_SHAPE_CHANGED" -eq 1 && "$CONTRACT_CHANGED" -eq 0 ]]; then
    fail "behavior-shape component spec changes require at least one contract update."
  fi

  if [[ "$CONTRACT_CHANGED" -eq 1 && "$MATRIX_CHANGED" -eq 0 ]]; then
    fail "contract schema changes require conformance matrix updates."
  fi

  if [[ "$SCENARIO_CATALOG_CHANGED" -eq 1 && "$MATRIX_CHANGED" -eq 0 ]]; then
    fail "scenario catalog changes require conformance matrix updates."
  fi

  if [[ "$MATRIX_CHANGED" -eq 1 && "$CONTRACT_CHANGED" -eq 0 && -z "$CHANGED_AC_COMPONENTS" ]]; then
    fail "conformance matrix updates require coupled contract changes or AC-bearing component spec changes."
  fi

  if [[ "$SCENARIO_CATALOG_CHANGED" -eq 1 && "$CONTRACT_CHANGED" -eq 0 ]]; then
    fail "scenario catalog updates require coupled contract changes."
  fi

  if [[ "$ARCH_BASELINE_CHANGED" -eq 1 && "$ADR_CHANGED" -eq 0 ]]; then
    fail "contract/architecture baseline changes require at least one ADR update."
  fi
else
  echo "Skipping change-policy checks: no relevant file changes were detected."
fi

if [[ "$failures" -ne 0 ]]; then
  echo
  echo "Governance validation failed."
  exit 1
fi

echo "Governance validation passed."
