# Phase 5 - IUR Renderer and Web UI Event Projection Loop

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoCodeUi.Services.IurRenderer.render/2`
- `JidoCodeUi.Services.UiOrchestrator.execute/2`
- `JidoCodeUi.Runtime.Substrate.admit/1`
- `JidoCodeUi.Observability.Telemetry`

## Relevant Assumptions / Defaults
- Renderer consumes canonical IUR output from compiler paths.
- Render responses are projected for `web-ui` and preserve continuity metadata.
- Browser events re-enter runtime through validated substrate admission.
- Phase SCN focus: `SCN-003`, `SCN-004`, `SCN-005`.

[x] 5 Phase 5 - IUR Renderer and Web UI Event Projection Loop
  Implement deterministic IUR rendering to `web-ui` contracts and close the projection loop from browser events back into runtime admission.

  [x] 5.1 Section - Canonical IUR-to-Web UI Rendering
    Implement render adapter behavior for converting canonical IUR documents into web-ui projection payloads.

    [x] 5.1.1 Task - Implement renderer input and projection contract
      Consume `UnifiedIurDocument` and produce deterministic web-ui payloads through `JidoCodeUi.Services.IurRenderer.render/2`.

      [x] 5.1.1.1 Subtask - Implement renderer validation for required IUR document fields and versions.
      [x] 5.1.1.2 Subtask - Implement deterministic projection mapping from IUR nodes to web-ui output structures.
      [x] 5.1.1.3 Subtask - Implement continuity metadata propagation into render outputs.

    [x] 5.1.2 Task - Implement render error normalization
      Normalize render failures into typed error outcomes compatible with orchestrator contracts.

      [x] 5.1.2.1 Subtask - Define typed error categories for invalid IUR, adapter failure, and timeout outcomes.
      [x] 5.1.2.2 Subtask - Implement render-stage `TypedError` normalization with stage metadata.
      [x] 5.1.2.3 Subtask - Emit render failure telemetry with continuity IDs and error classification.

  [x] 5.2 Section - Event Projection Loop Back to Runtime
    Implement browser interaction event projection back through substrate admission and orchestration.

    [x] 5.2.1 Task - Implement web-ui event envelope projection contract
      Define and enforce the event envelope shape used by browser interactions entering runtime.

      [x] 5.2.1.1 Subtask - Implement projection contract for widget event payloads into `WidgetUiEventEnvelope`.
      [x] 5.2.1.2 Subtask - Implement event correlation continuity linking render outputs to follow-on events.
      [x] 5.2.1.3 Subtask - Implement typed projection errors for invalid event envelope conversion.

    [x] 5.2.2 Task - Implement round-trip orchestration continuity
      Ensure render outputs and projected events re-enter deterministic orchestrator execution paths.

      [x] 5.2.2.1 Subtask - Implement event admission handshake from renderer outputs to substrate `admit/1`.
      [x] 5.2.2.2 Subtask - Implement orchestrator compatibility for projected event command semantics.
      [x] 5.2.2.3 Subtask - Implement round-trip outcome telemetry for render-event cycles.

  [x] 5.3 Section - Render Observability and Performance Baseline
    Implement render lifecycle telemetry and performance baselines.

    [x] 5.3.1 Task - Implement render lifecycle events
      Emit required started/completed/failed render events with typed metadata.

      [x] 5.3.1.1 Subtask - Emit `ui.iur.render.started.v1` on render initiation.
      [x] 5.3.1.2 Subtask - Emit `ui.iur.render.completed.v1` for successful render outcomes.
      [x] 5.3.1.3 Subtask - Emit `ui.iur.render.failed.v1` with normalized render errors.

    [x] 5.3.2 Task - Implement render metrics baseline
      Emit render latency, throughput, and failure metrics for runtime monitoring.

      [x] 5.3.2.1 Subtask - Implement render latency histogram by payload class.
      [x] 5.3.2.2 Subtask - Implement render success/failure counters by outcome category.
      [x] 5.3.2.3 Subtask - Implement round-trip latency metric across compile-render-event loop boundaries.

  [x] 5.4 Section - Phase 5 Integration Tests
    Validate render projection, event loop continuity, and typed render failure handling end-to-end.

    [x] 5.4.1 Task - Compile-render-event round-trip integration scenarios
      Verify canonical render outputs project browser events that re-enter runtime deterministically.

      [x] 5.4.1.1 Subtask - Verify canonical IUR outputs map to deterministic web-ui projection payloads.
      [x] 5.4.1.2 Subtask - Verify projected browser events are admitted and routed through orchestrator paths.
      [x] 5.4.1.3 Subtask - Verify continuity metadata is preserved across the full round-trip cycle.

    [x] 5.4.2 Task - Render failure and telemetry integration scenarios
      Verify render-stage failures normalize into typed outcomes and emit required telemetry.

      [x] 5.4.2.1 Subtask - Verify invalid IUR inputs fail with stage-tagged typed render errors.
      [x] 5.4.2.2 Subtask - Verify render lifecycle events are emitted for success and failure outcomes.
      [x] 5.4.2.3 Subtask - Verify render metrics and round-trip latency telemetry coverage.
