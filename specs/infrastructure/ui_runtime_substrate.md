# Ui Runtime Substrate (`JidoCodeUi.Runtime.Substrate`)

## Purpose

Defines shared infrastructure boundaries for event transport, ingress validation, and envelope handling without taking domain-state authority.

## Control Plane

Primary control-plane ownership: **Transport Plane**.

## Workflow Diagram

```mermaid
flowchart LR
  A[Inbound Event] --> B[Ingress Validation]
  B --> C[Envelope Normalization]
  C --> D[Runtime Dispatch]
```

### Acceptance Criteria

| Acceptance ID (AC-XX) | Criterion | Verification |
|---|---|---|
| `AC-01` | Ingress payloads are validated before runtime dispatch. | Validation tests over malformed and valid payload shapes. |
| `AC-02` | Substrate remains non-authoritative for domain state mutation. | Boundary tests and control-plane contract review. |
| `AC-03` | Envelope normalization preserves correlation/request continuity. | End-to-end envelope assertions across dispatch flow. |

## Governance Mapping

### Requirement Families

- `REQ-CP-*`
- `REQ-SVC-*`
- `REQ-DATA-*`

### Scenario Coverage

- `SCN-001`
- `SCN-002`
- `SCN-003`
- `SCN-008`

## Normative Contracts

- [control_plane_ownership_matrix.md](../contracts/control_plane_ownership_matrix.md)
- [service_contract.md](../contracts/service_contract.md)
- [data_contract.md](../contracts/data_contract.md)

## Control Plane ADR

- [ADR-0001-control-plane-authority.md](../adr/ADR-0001-control-plane-authority.md)
