# Data Contract

## Requirement Set

- `REQ-DATA-001`: DSL, IUR, and session snapshot schemas MUST be explicit and versioned.
- `REQ-DATA-002`: DSL->IUR transformations MUST produce canonical ordering and stable hashes.
- `REQ-DATA-003`: Validation failures MUST return typed errors with schema-path diagnostics.
- `REQ-DATA-004`: Session-state ownership and mutation authority MUST remain in runtime/session modules.
- `REQ-DATA-005`: In v1, session snapshots MUST be in-memory only; if persistence is introduced later, persisted or replayable artifacts MUST carry schema version and integrity checksum metadata.

## Schema Inventory

| Schema | Version | Owner | Notes |
|---|---|---|---|
| `UnifiedUiDslDocument` | `v1` | `JidoCodeUi.Services.DslCompiler` | Declarative UI input model for compile stage. |
| `UnifiedIurDocument` | `v1` | `JidoCodeUi.Services.DslCompiler` | Canonical compile output consumed by renderer. |
| `RenderResult` | `v1` | `JidoCodeUi.Services.IurRenderer` | Canonical render payload with projection, continuity, and event projection metadata. |
| `UiSessionSnapshot` | `v1` | `JidoCodeUi.Session.RuntimeAgent` | In-memory session state + active IUR hash and compile metadata. |
| `OrchestratorResult` | `v1` | `JidoCodeUi.Services.UiOrchestrator` | Canonical orchestrator success payload composed of policy, compile, session, and render outputs. |
| `WidgetUiEventEnvelope` | `v1` | `JidoCodeUi.Runtime.Substrate` | Validated ingress envelope for UI interactions. |
