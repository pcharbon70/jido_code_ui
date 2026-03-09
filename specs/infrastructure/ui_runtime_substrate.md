# Ui Runtime Substrate (`JidoCodeUi.Runtime.Substrate`)

## Purpose

Defines shared infrastructure boundaries for ingress from `web-ui` interactions and command envelopes, including validation, normalization, and continuity metadata propagation.

## Control Plane

Primary control-plane ownership: **Transport Plane**.

## Workflow Diagram

```mermaid
flowchart LR
  A[Widget Event or UiCommand] --> B[Ingress Validation]
  B --> C[Envelope Normalization]
  C --> D[Auth Context Attachment]
  D --> E[Runtime Dispatch]
```

### Acceptance Criteria

| Acceptance ID (AC-XX) | Criterion | Verification |
|---|---|---|
| `AC-01` | Ingress payloads are validated before runtime dispatch. | Validation tests over malformed and valid envelopes. |
| `AC-02` | Unsupported event/command shapes fail closed with typed errors. | Negative-path tests on schema and policy rejects. |
| `AC-03` | Correlation and request IDs are preserved and attached to downstream runtime dispatch. | End-to-end envelope continuity assertions. |
| `AC-04` | Substrate remains non-authoritative for session/runtime state mutation. | Boundary tests and control-plane ownership checks. |

## Governance Mapping

### Requirement Families

- `REQ-CP-*`
- `REQ-SVC-*`
- `REQ-SEC-*`
- `REQ-DATA-*`

### Scenario Coverage

- `SCN-001`
- `SCN-002`
- `SCN-003`
- `SCN-006`
- `SCN-008`

## Normative Contracts

- [control_plane_ownership_matrix.md](../contracts/control_plane_ownership_matrix.md)
- [service_contract.md](../contracts/service_contract.md)
- [security_contract.md](../contracts/security_contract.md)
- [data_contract.md](../contracts/data_contract.md)

## Control Plane ADR

- [ADR-0001-control-plane-authority.md](../adr/ADR-0001-control-plane-authority.md)
