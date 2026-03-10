# RFC Intake Governance

## Purpose

`RFC Intake Governance` is introduced by [RFC-0001](../../rfcs/RFC-0001-rfc-governance-and-spec-intake.md) and defines runtime behavior for this component surface.

## Control Plane

Primary control-plane ownership: **Product Plane**.

## Topology Context

- [Topology](../topology.md)

## Governance Mapping

### Requirement Families

- `REQ-CP-*`
- `REQ-OBS-*`

### Scenario Coverage

- `SCN-001`
- `SCN-006`

### Source RFC

- [RFC-0001](../../rfcs/RFC-0001-rfc-governance-and-spec-intake.md)

## Acceptance Criteria

| Acceptance ID (AC-XX) | Criterion | Verification |
|---|---|---|
| `AC-01` | RFC metadata and index registration MUST remain consistent (`RFC ID`, status, and index row) before merge. | `./scripts/validate_rfc_governance.sh` checks metadata format, status validity, and index row parity. |
| `AC-02` | RFC governance mappings MUST reference known `REQ-*` families, known `SCN-*` scenarios, and valid contract paths with actionable spec-plan rows. | `./scripts/validate_rfc_governance.sh` validates REQ/SCN references, contract paths, and `Spec Creation Plan` row shape. |
| `AC-03` | RFC lifecycle transitions MUST follow allowed status transitions, and accepted/implemented RFC changes MUST be coupled with spec updates. | `./scripts/validate_rfc_governance.sh` enforces status-transition rules, index coupling, and required `specs/*.md` changes. |

## Normative Contracts

- [control_plane_ownership_matrix.md](../contracts/control_plane_ownership_matrix.md)
- [observability_contract.md](../contracts/observability_contract.md)

## Control Plane ADR

- [ADR-0001-control-plane-authority.md](../adr/ADR-0001-control-plane-authority.md)
