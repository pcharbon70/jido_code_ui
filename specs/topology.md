# Topology

## Runtime Surfaces

| Surface | Responsibility | Notes |
|---|---|---|
| `DSL Authoring Surface` | Produce `unified-ui` DSL documents from feature intent. | Includes server-provided and generated UI specs. |
| `Ingress/Transport Surface` | Validate envelopes, auth context, and correlation metadata. | No session mutation authority. |
| `Orchestration Surface` | Route commands/events to compile, session, and render flows. | Applies policy and emits typed outcomes. |
| `Transform Surface` | Compile DSL into canonical `unified-iur` representation. | Deterministic, version-aware, and server-authoritative. |
| `Render Surface` | Adapt `unified-iur` into `web-ui` render responses. | Emits widget events for next cycle. |
| `Session Surface` | Own session-level UI state transitions and replayability. | Runtime authority for state changes. |

## Data/Control Flow

```mermaid
flowchart LR
  A[Unified UI DSL] --> B[Ingress Validation]
  B --> C[UI Orchestrator]
  C --> D[DSL Compiler]
  D --> E[Unified IUR]
  E --> F[Web UI Adapter]
  F --> G[Browser Interaction Events]
  G --> B
  C --> H[Session Runtime Agent]
  H --> C
```

Directionality rules:

- Transport forwards validated envelopes to orchestration only.
- Client/browser surfaces MUST NOT act as authoritative DSL->IUR compilers.
- Compile/render services do not bypass orchestration for mutating operations.
- Session state transitions are authoritative only in the session surface.
