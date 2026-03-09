# Control Plane Ownership Matrix

## Requirement Set

- `REQ-CP-001`: Every covered module MUST map to exactly one primary control plane.
- `REQ-CP-002`: Ownership conflicts across docs MUST resolve in favor of this matrix and ADR-0001.
- `REQ-CP-003`: Transport modules MUST NOT become domain-state authorities.
- `REQ-CP-004`: Ownership changes MUST update this matrix in the same change set.
- `REQ-CP-005`: New runtime modules MUST be assigned before merge.

## Ownership Matrix

| Runtime Module | Primary Plane | Notes |
|---|---|---|
| `JidoCodeUi.Application` | `UI Runtime Plane` | Bootstraps supervisors and runtime wiring only. |
| `JidoCodeUi.Runtime.Substrate` | `Transport Plane` | Validates ingress envelope and continuity fields. |
| `JidoCodeUi.Services.UiOrchestrator` | `Runtime Authority Plane` | Routes commands/events to compile/session/render flows. |
| `JidoCodeUi.Services.DslCompiler` | `Runtime Authority Plane` | Owns deterministic, server-authoritative DSL->IUR transformation semantics. |
| `JidoCodeUi.Services.IurRenderer` | `UI Runtime Plane` | Converts IUR to `web-ui` render projection payloads. |
| `JidoCodeUi.Session.RuntimeAgent` | `Runtime Authority Plane` | Owns in-memory session state transitions and replay behavior. |
| `JidoCodeUi.Security.Policy` | `Runtime Authority Plane` | Enforces authorization and feature-flag policy for DSL extensions. |
| `JidoCodeUi.Observability.Telemetry` | `Transport Plane` | Emits structured event/metric envelopes only. |

## ADR References

- [../adr/ADR-0001-control-plane-authority.md](../adr/ADR-0001-control-plane-authority.md)
