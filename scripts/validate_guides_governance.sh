#!/usr/bin/env bash
set -euo pipefail

ROOT="${GUIDES_GOVERNANCE_ROOT:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "$ROOT"

GUIDES_ROOT="guides"
SPEC_MATRIX="specs/conformance/spec_conformance_matrix.md"
SPEC_SCENARIO_CATALOG="specs/conformance/scenario_catalog.md"
GUIDE_MATRIX="guides/conformance/guide_conformance_matrix.md"
GUIDE_SCENARIO_CATALOG="guides/conformance/guide_scenario_catalog.md"
USER_TEMPLATE="guides/templates/user-guide-template.md"
DEVELOPER_TEMPLATE="guides/templates/developer-guide-template.md"

GUIDE_FILE_REGEX='^guides/(user/UG-[0-9]{4}-[a-z0-9][a-z0-9-]*\.md|developer/DG-[0-9]{4}-[a-z0-9][a-z0-9-]*\.md)$'
ALLOWED_STATUS_REGEX='^(Draft|Active|Deprecated|Superseded)$'

failures=0

fail() {
  echo "FAIL: $1"
  failures=1
}

trim() {
  echo "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

required_files=(
  "$SPEC_MATRIX"
  "$SPEC_SCENARIO_CATALOG"
  "$GUIDE_MATRIX"
  "$GUIDE_SCENARIO_CATALOG"
  "$USER_TEMPLATE"
  "$DEVELOPER_TEMPLATE"
)

for f in "${required_files[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: missing required file: $f"
    exit 1
  fi
done

if [[ ! -d "$GUIDES_ROOT" ]]; then
  echo "ERROR: missing guides directory: $GUIDES_ROOT"
  exit 1
fi

GUIDE_FILES="$(rg --files guides/user guides/developer | rg "$GUIDE_FILE_REGEX" | sort || true)"
if [[ -z "$GUIDE_FILES" ]]; then
  echo "ERROR: no guide files found matching UG/DG naming conventions"
  exit 1
fi

KNOWN_SPEC_REQ_FAMILIES="$(rg -I -o 'REQ-[A-Z]+' "$SPEC_MATRIX" | sort -u || true)"
KNOWN_GUIDE_REQ_FAMILIES="$(rg -I -o 'REQ-[A-Z]+' guides/contracts/*.md | sort -u || true)"
KNOWN_REQ_FAMILIES="$(printf '%s\n%s\n' "$KNOWN_SPEC_REQ_FAMILIES" "$KNOWN_GUIDE_REQ_FAMILIES" | sort -u | sed '/^$/d')"

KNOWN_SPEC_SCENARIOS="$(rg -I -o 'SCN-[0-9]+' "$SPEC_SCENARIO_CATALOG" | sort -u || true)"
KNOWN_GUIDE_SCENARIOS="$(rg -I -o 'GSCN-[0-9]+' "$GUIDE_SCENARIO_CATALOG" | sort -u || true)"
KNOWN_SCENARIOS="$(printf '%s\n%s\n' "$KNOWN_SPEC_SCENARIOS" "$KNOWN_GUIDE_SCENARIOS" | sort -u | sed '/^$/d')"

echo "Checking template compliance..."
for template in "$USER_TEMPLATE" "$DEVELOPER_TEMPLATE"; do
  if ! rg -q '^- Diagram Required: `yes\|no`$' "$template"; then
    fail "template missing Diagram Required metadata line: $template"
  fi

  if ! rg -q '```mermaid' "$template"; then
    fail "template missing Mermaid diagram section: $template"
  fi
done

echo "Checking guide files for metadata, traceability, and Mermaid rules..."
while IFS= read -r guide; do
  [[ -z "$guide" ]] && continue

  if ! rg -q '^## Metadata$' "$guide"; then
    fail "missing required section '## Metadata' in $guide"
  fi

  if ! rg -q '^## Governance Mapping$' "$guide"; then
    fail "missing required section '## Governance Mapping' in $guide"
  fi

  guide_id_line="$(rg -n '^- Guide ID: `(UG|DG)-[0-9]{4}`$' "$guide" | head -n1 || true)"
  if [[ -z "$guide_id_line" ]]; then
    fail "missing Guide ID metadata in $guide"
    continue
  fi

  guide_id_in_doc="$(echo "$guide_id_line" | sed -E 's/.*`((UG|DG)-[0-9]{4})`.*/\1/')"
  guide_basename="$(basename "$guide")"
  guide_id_from_filename="$(echo "$guide_basename" | sed -E 's/^((UG|DG)-[0-9]{4})-.+$/\1/')"

  if [[ "$guide_id_in_doc" != "$guide_id_from_filename" ]]; then
    fail "Guide ID mismatch in $guide (filename=$guide_id_from_filename metadata=$guide_id_in_doc)"
  fi

  audience_line="$(rg -n '^- Audience: `(User|Developer)`$' "$guide" | head -n1 || true)"
  if [[ -z "$audience_line" ]]; then
    fail "missing or invalid Audience metadata in $guide"
  else
    audience_value="$(echo "$audience_line" | sed -E 's/.*`(User|Developer)`.*/\1/')"
    if [[ "$guide" == guides/user/* && "$audience_value" != "User" ]]; then
      fail "audience/path mismatch in $guide (expected User)"
    fi
    if [[ "$guide" == guides/developer/* && "$audience_value" != "Developer" ]]; then
      fail "audience/path mismatch in $guide (expected Developer)"
    fi
  fi

  status_line="$(rg -n '^- Status: `[^`]+`$' "$guide" | head -n1 || true)"
  if [[ -z "$status_line" ]]; then
    fail "missing Status metadata in $guide"
  else
    status_value="$(echo "$status_line" | sed -E 's/.*`([^`]+)`.*/\1/')"
    if ! echo "$status_value" | rg -q "$ALLOWED_STATUS_REGEX"; then
      fail "invalid status '$status_value' in $guide"
    fi
  fi

  if ! rg -q '^- Owners: `[^`]+`$' "$guide"; then
    fail "missing Owners metadata in $guide"
  fi

  reviewed_line="$(rg -n '^- Last Reviewed: `[0-9]{4}-[0-9]{2}-[0-9]{2}`$' "$guide" | head -n1 || true)"
  if [[ -z "$reviewed_line" ]]; then
    fail "missing or invalid Last Reviewed metadata in $guide"
  fi

  diagram_required_line="$(rg -n '^- Diagram Required: `(yes|no)`$' "$guide" | head -n1 || true)"
  if [[ -z "$diagram_required_line" ]]; then
    fail "missing Diagram Required metadata in $guide"
  else
    diagram_required_value="$(echo "$diagram_required_line" | sed -E 's/.*`(yes|no)`.*/\1/')"
    has_mermaid=0
    if rg -q '```mermaid' "$guide"; then
      has_mermaid=1
    fi

    if [[ "$diagram_required_value" == "yes" && "$has_mermaid" -eq 0 ]]; then
      fail "Diagram Required is yes but Mermaid diagram is missing in $guide"
    fi

    if [[ "$diagram_required_value" == "yes" ]] && rg -q '!\[[^]]*\]\([^)]*\)' "$guide" && [[ "$has_mermaid" -eq 0 ]]; then
      fail "static image used as required diagram without Mermaid in $guide"
    fi
  fi

  spec_refs="$(rg -o 'specs/[a-z0-9_./-]+\.md' "$guide" | sort -u || true)"
  if [[ -z "$spec_refs" ]]; then
    fail "missing specs/ references in $guide"
  else
    while IFS= read -r spec_ref; do
      [[ -z "$spec_ref" ]] && continue
      if [[ ! -f "$spec_ref" ]]; then
        fail "guide references missing spec path '$spec_ref' in $guide"
      fi
    done <<< "$spec_refs"
  fi

  req_refs="$(rg -o 'REQ-[A-Z]+' "$guide" | sort -u || true)"
  if [[ -z "$req_refs" ]]; then
    fail "missing REQ references in $guide"
  else
    while IFS= read -r req; do
      [[ -z "$req" ]] && continue
      if ! echo "$KNOWN_REQ_FAMILIES" | grep -Fxq "$req"; then
        fail "unknown REQ family '$req' in $guide"
      fi
    done <<< "$req_refs"
  fi

  scn_refs="$(rg -o 'SCN-[0-9]+|GSCN-[0-9]+' "$guide" | sort -u || true)"
  if [[ -z "$scn_refs" ]]; then
    fail "missing scenario references in $guide"
  else
    while IFS= read -r scn; do
      [[ -z "$scn" ]] && continue
      if ! echo "$KNOWN_SCENARIOS" | grep -Fxq "$scn"; then
        fail "unknown scenario id '$scn' in $guide"
      fi
    done <<< "$scn_refs"
  fi

  matrix_row="$(grep -F "| \`$guide\` |" "$GUIDE_MATRIX" | head -n1 || true)"
  if [[ -z "$matrix_row" ]]; then
    fail "missing guide conformance matrix row for $guide"
  else
    req_col="$(echo "$matrix_row" | awk -F'|' '{print $5}')"
    scn_col="$(echo "$matrix_row" | awk -F'|' '{print $6}')"

    if ! echo "$req_col" | rg -q 'REQ-[A-Z]'; then
      fail "guide conformance row for $guide missing REQ mappings"
    fi

    if ! echo "$scn_col" | rg -q '(SCN-[0-9]+|GSCN-[0-9]+)'; then
      fail "guide conformance row for $guide missing scenario mappings"
    fi
  fi
done <<< "$GUIDE_FILES"

echo "Checking guide conformance matrix reference integrity..."
MATRIX_REQS="$(rg -I -o 'REQ-[A-Z]+' "$GUIDE_MATRIX" | sort -u || true)"
while IFS= read -r req; do
  [[ -z "$req" ]] && continue
  if ! echo "$KNOWN_REQ_FAMILIES" | grep -Fxq "$req"; then
    fail "guide conformance matrix references unknown REQ family: $req"
  fi
done <<< "$MATRIX_REQS"

MATRIX_SCNS="$(rg -I -o 'SCN-[0-9]+|GSCN-[0-9]+' "$GUIDE_MATRIX" | sort -u || true)"
while IFS= read -r scn; do
  [[ -z "$scn" ]] && continue
  if ! echo "$KNOWN_SCENARIOS" | grep -Fxq "$scn"; then
    fail "guide conformance matrix references unknown scenario id: $scn"
  fi
done <<< "$MATRIX_SCNS"

DIFF_BASE="${DIFF_BASE:-}"
DIFF_HEAD="${DIFF_HEAD:-}"
DIFF_RANGE=""
CHANGED_FILES=""
IN_WORK_TREE="false"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  IN_WORK_TREE="$(git rev-parse --is-inside-work-tree 2>/dev/null || echo false)"
fi

if [[ "$IN_WORK_TREE" == "true" ]] && [[ -n "$DIFF_BASE" && -n "$DIFF_HEAD" ]] \
  && git rev-parse --verify "${DIFF_BASE}^{commit}" >/dev/null 2>&1 \
  && git rev-parse --verify "${DIFF_HEAD}^{commit}" >/dev/null 2>&1; then
  DIFF_RANGE="${DIFF_BASE}..${DIFF_HEAD}"
fi

if [[ "$IN_WORK_TREE" != "true" ]]; then
  echo "Skipping change-policy checks: not running inside a git work tree."
elif [[ -n "$DIFF_RANGE" ]]; then
  CHANGED_FILES="$(git diff --name-only "$DIFF_RANGE" -- guides scripts/validate_guides_governance.sh .github/workflows/guides-governance.yml || true)"
else
  CHANGED_FILES="$({
    git diff --name-only -- guides scripts/validate_guides_governance.sh .github/workflows/guides-governance.yml
    git diff --name-only --cached -- guides scripts/validate_guides_governance.sh .github/workflows/guides-governance.yml
  } | sort -u | sed '/^$/d')"
fi

if [[ -n "$CHANGED_FILES" ]]; then
  CHANGED_GUIDE_DOCS="$(echo "$CHANGED_FILES" | rg '^guides/(user|developer)/(UG|DG)-[0-9]{4}-.+\.md$' || true)"
  MATRIX_CHANGED=0

  if echo "$CHANGED_FILES" | rg -q '^guides/conformance/guide_conformance_matrix\.md$'; then
    MATRIX_CHANGED=1
  fi

  if [[ -n "$CHANGED_GUIDE_DOCS" && "$MATRIX_CHANGED" -eq 0 ]]; then
    fail "guide document changes require guide conformance matrix updates in the same change set."
  fi
fi

if [[ "$failures" -ne 0 ]]; then
  echo
  echo "Guide governance validation failed."
  exit 1
fi

echo "Guide governance validation passed."
