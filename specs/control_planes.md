# Control Planes

| Plane | Authority | Non-Authority |
|---|---|---|
| `ui` | UI composition intent, view-state projection, IUR-to-visual rendering contracts. | Domain/session mutation authority; auth policy decisions; authoritative DSL->IUR compilation. |
| `transport` | Envelope validation, auth context propagation, correlation continuity, rate/control guards. | DSL semantics, compile decisions, session state transitions. |
| `runtime` | Command orchestration, server-authoritative DSL->IUR transformation, session state transitions, typed outcome policy. | Browser-local presentation concerns not persisted as runtime state. |

Cross-plane invariants:

- Every runtime module MUST map to one primary plane in `contracts/control_plane_ownership_matrix.md`.
- Transport plane modules MUST NOT mutate canonical session state.
- Runtime plane modules MUST own and version state-changing semantics.
- Feature-flag policy checks for custom DSL nodes execute under runtime-plane authority.
