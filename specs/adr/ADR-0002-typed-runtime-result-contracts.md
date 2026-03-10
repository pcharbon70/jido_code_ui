# ADR-0002: Typed Runtime Result Contracts

## Status

Accepted

## Context

Runtime services currently expose rich success payloads at core boundaries:

- `JidoCodeUi.Services.IurRenderer.render/2` returns the canonical render payload consumed by event projection and session retention flows.
- `JidoCodeUi.Services.UiOrchestrator.execute/2` returns the canonical pipeline outcome consumed by integration, conformance, and governance verification paths.

These payloads must remain stable and explicit to preserve cross-service determinism, telemetry continuity, and contract-level testing.

## Decision

1. Introduce typed success-output contracts for runtime service boundaries:
   - `JidoCodeUi.Contracts.RenderResult`
   - `JidoCodeUi.Contracts.OrchestratorResult`
2. Require renderer success outcomes to be emitted as `RenderResult`.
3. Require orchestrator success outcomes to be emitted as `OrchestratorResult`.
4. Keep `CompileResult` and `UiSessionSnapshot` as canonical nested contracts within orchestrator success outputs.
5. Treat these contract types as governance-tracked baseline artifacts under `REQ-SVC-*` and `REQ-DATA-*`.

## Consequences

- Service API shape is explicit, typed, and easier to verify in tests.
- Downstream consumers avoid map-shape drift and implicit field assumptions.
- Governance checks can enforce conformance updates whenever service/data contract surfaces change.

## Related Requirements

- `REQ-SVC-001` through `REQ-SVC-005`
- `REQ-DATA-001` through `REQ-DATA-005`
