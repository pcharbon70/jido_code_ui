# Spec Conformance Matrix

This matrix maps requirement families to owning contracts and canonical baseline scenarios.

| Requirement Family | Owning Contract | Primary Runtime Modules | Scenario Coverage |
|---|---|---|---|
| `REQ-CP-001`..`REQ-CP-005` | [../contracts/control_plane_ownership_matrix.md](../contracts/control_plane_ownership_matrix.md) | `JidoCodeUi.Application`, `JidoCodeUi.Runtime.Substrate`, `JidoCodeUi.Services.UiOrchestrator`, `JidoCodeUi.Services.DslCompiler`, `JidoCodeUi.Services.IurRenderer`, `JidoCodeUi.Session.RuntimeAgent` | `SCN-001` |
| `REQ-SVC-001`..`REQ-SVC-005` | [../contracts/service_contract.md](../contracts/service_contract.md) | `JidoCodeUi.Services.UiOrchestrator`, `JidoCodeUi.Services.DslCompiler`, `JidoCodeUi.Services.IurRenderer` | `SCN-002`, `SCN-003`, `SCN-004`, `SCN-008` |
| `REQ-OBS-001`..`REQ-OBS-005` | [../contracts/observability_contract.md](../contracts/observability_contract.md) | `JidoCodeUi.Observability.Telemetry`, `JidoCodeUi.Services.UiOrchestrator` | `SCN-003`, `SCN-005` |
| `REQ-SEC-001`..`REQ-SEC-005` | [../contracts/security_contract.md](../contracts/security_contract.md) | `JidoCodeUi.Runtime.Substrate`, `JidoCodeUi.Security.Policy`, `JidoCodeUi.Services.UiOrchestrator` | `SCN-006`, `SCN-007`, `SCN-008` |
| `REQ-DATA-001`..`REQ-DATA-005` | [../contracts/data_contract.md](../contracts/data_contract.md) | `JidoCodeUi.Services.DslCompiler`, `JidoCodeUi.Session.RuntimeAgent`, `JidoCodeUi.Services.IurRenderer` | `SCN-008` |

## Acceptance Mapping Rule

Every future AC-bearing component spec MUST map to at least one `REQ-*` family and one `SCN-*` scenario.

## Component AC Coverage

| Component Spec | AC Scope | Requirement Families | Scenario Coverage |
|---|---|---|---|
| `specs/core/ui_application.md` | `AC-*` | `REQ-CP-*`, `REQ-SVC-*`, `REQ-OBS-*` | `SCN-001`, `SCN-003`, `SCN-004`, `SCN-005` |
| `specs/infrastructure/ui_runtime_substrate.md` | `AC-*` | `REQ-CP-*`, `REQ-SVC-*`, `REQ-SEC-*`, `REQ-DATA-*` | `SCN-001`, `SCN-002`, `SCN-003`, `SCN-006`, `SCN-008` |
| `specs/services/ui_orchestrator_service.md` | `AC-*` | `REQ-SVC-*`, `REQ-SEC-*`, `REQ-OBS-*`, `REQ-DATA-*` | `SCN-002`, `SCN-003`, `SCN-004`, `SCN-005`, `SCN-006`, `SCN-007`, `SCN-008` |
| `specs/session/ui_session_runtime_agent.md` | `AC-*` | `REQ-CP-*`, `REQ-SVC-*`, `REQ-DATA-*` | `SCN-001`, `SCN-003`, `SCN-004`, `SCN-008` |
| `specs/operations/rfc_intake_governance.md` | `AC-*` | `REQ-CP-*`, `REQ-OBS-*` | `SCN-001`, `SCN-006` |
