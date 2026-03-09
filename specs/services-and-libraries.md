# Services and Libraries

## Planned Runtime Modules

| Module | Responsibility | Ownership |
|---|---|---|
| `JidoCodeUi.Application` | Boot supervision tree and runtime service wiring. | `ui` |
| `JidoCodeUi.Runtime.Substrate` | Ingress envelope validation and transport normalization. | `transport` |
| `JidoCodeUi.Services.UiOrchestrator` | Deterministic command routing and policy-aware dispatch. | `runtime` |
| `JidoCodeUi.Services.DslCompiler` | Server-authoritative compile of `unified-ui` DSL into canonical `unified-iur`. | `runtime` |
| `JidoCodeUi.Services.IurRenderer` | Adapt `unified-iur` documents for `web-ui` rendering contracts. | `ui` |
| `JidoCodeUi.Session.RuntimeAgent` | Session-scoped state transitions and replay invariants. | `runtime` |
| `JidoCodeUi.Security.Policy` | Runtime authorization and feature-flag policy checks for mutating actions and custom DSL nodes. | `runtime` |
| `JidoCodeUi.Observability.Telemetry` | Structured events/metrics for compile, render, and policy flows. | `transport` |

## External Libraries

| Library | Role |
|---|---|
| `unified-ui` | Authoring/runtime DSL for declarative interface definitions. |
| `unified-iur` | Canonical intermediate UI representation emitted by compiler workflows. |
| `web-ui` | Rendering runtime that consumes IUR and emits typed widget events. |

## Contract Alignment

The planned runtime modules MUST align with:

- [contracts/control_plane_ownership_matrix.md](contracts/control_plane_ownership_matrix.md)
- [contracts/service_contract.md](contracts/service_contract.md)
- [contracts/observability_contract.md](contracts/observability_contract.md)
- [contracts/security_contract.md](contracts/security_contract.md)
- [contracts/data_contract.md](contracts/data_contract.md)
