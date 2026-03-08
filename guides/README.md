# Guides Governance Index

This directory defines the user-guide and developer-guide system that is a governance sibling to `specs/` and `rfcs/`.

The guide system has two goals:

1. provide user-facing workflows for using `jido_code_ui` safely and consistently
2. provide developer-facing architecture guidance aligned to canonical contracts and conformance

Normative language in this directory uses RFC-2119 terms: **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY**.

## Directory Layout

- [user/README.md](user/README.md): index for user guides (`UG-*`).
- [developer/README.md](developer/README.md): index for developer guides (`DG-*`).
- [contracts/guide_contract.md](contracts/guide_contract.md): canonical authoring and quality requirements.
- [contracts/guide_traceability_contract.md](contracts/guide_traceability_contract.md): traceability and coverage rules.
- [conformance/guide_conformance_matrix.md](conformance/guide_conformance_matrix.md): requirement-to-guide scenario mapping.
- [conformance/guide_scenario_catalog.md](conformance/guide_scenario_catalog.md): canonical guide-governance scenarios.
- [templates/user-guide-template.md](templates/user-guide-template.md): required user-guide template.
- [templates/developer-guide-template.md](templates/developer-guide-template.md): required developer-guide template.

## Governance Model

Every guide document (`guides/user/UG-*.md` or `guides/developer/DG-*.md`) MUST include:

1. machine-readable metadata (`Guide ID`, `Audience`, `Status`, `Owners`, `Last Reviewed`, `Diagram Required`)
2. governance mapping to `specs/` source documents
3. governance mapping to `REQ-*` requirement families
4. governance mapping to scenario IDs (`SCN-*` and/or `GSCN-*`)
5. coverage row in [guide_conformance_matrix.md](conformance/guide_conformance_matrix.md)

Guide diagrams are governed by a strict format rule:

- when `Diagram Required` is `yes`, the guide MUST include at least one Mermaid fenced block (` ```mermaid `)
- static images MAY be supplemental, but MUST NOT be the primary required diagram format

## Commands

Validate guide governance:

```bash
./scripts/validate_guides_governance.sh
```

## CI Gate

Guide governance is enforced in CI by:

- `.github/workflows/guides-governance.yml`

This gate is complementary to:

- `.github/workflows/specs-governance.yml`
- `.github/workflows/rfc-governance.yml`
- `.github/workflows/conformance.yml`
