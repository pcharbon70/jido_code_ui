# ADR-0001: Control-Plane Authority

## Status

Accepted

## Context

`jido_code_ui` spans UI composition, transport validation, runtime orchestration, and session-state management. Without explicit authority boundaries, DSL/IUR/render behavior can drift between modules and produce non-deterministic outcomes.

## Decision

1. UI-plane authority: owns UI composition intent, IUR render contract projection, and browser-facing presentation adapters.
2. Transport-plane authority: owns ingress validation, envelope normalization, correlation continuity, and request trust propagation.
3. Runtime/domain authority: owns command orchestration, server-authoritative DSL->IUR transformation semantics, policy-gated mutations, and session-state transitions.
4. Non-authoritative extension seams: custom widgets, telemetry sinks, and compile plugins MAY extend behavior but MUST NOT bypass runtime authority for state-changing decisions.
5. Custom DSL node types are allowed only when enabled by versioned feature-flag policy under runtime authority.
6. Session snapshots are in-memory only for v1 and are not part of external persistence guarantees.

## Consequences

- Ownership boundaries are explicit and reviewable.
- DSL->IUR->render invariants can be enforced consistently across docs and tests.
- Transport cannot silently mutate runtime/session state.
- Compile authority remains centralized on the server runtime surface.
- Feature-flag policy becomes a release gate for custom DSL extensions.
- Governance checks can fail fast on control-plane drift.

## Related Requirements

- `REQ-CP-001` through `REQ-CP-005`
- `REQ-SVC-001` through `REQ-SVC-005`
- `REQ-OBS-001` through `REQ-OBS-005`
- `REQ-SEC-001` through `REQ-SEC-005`
- `REQ-DATA-001` through `REQ-DATA-005`
