# Phase 6 - Session Runtime In-Memory State and Replay Control

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoCodeUi.Session.RuntimeAgent.create_session/1`
- `JidoCodeUi.Session.RuntimeAgent.update_session/2`
- `JidoCodeUi.Session.RuntimeAgent.replay_session/2`
- `JidoCodeUi.Session.RuntimeAgent.current_snapshot/1`
- `JidoCodeUi.Services.UiOrchestrator.execute/2`

## Relevant Assumptions / Defaults
- Session runtime is authoritative for session state transitions.
- `UiSessionSnapshot` is in-memory only for v1.
- Replay determinism is validated through command/event stream and IUR hash parity.
- Phase SCN focus: `SCN-001`, `SCN-003`, `SCN-004`, `SCN-008`.

[x] 6 Phase 6 - Session Runtime In-Memory State and Replay Control
  Implement session runtime authority, in-memory snapshot management, and replay controls that preserve deterministic state and hash parity.

  [x] 6.1 Section - Session Runtime Authority and Snapshot Contracts
    Implement canonical session APIs and in-memory snapshot authority semantics.

    [x] 6.1.1 Task - Implement session lifecycle APIs
      Implement `create_session/1`, `update_session/2`, `replay_session/2`, and `current_snapshot/1` under runtime authority.

      [x] 6.1.1.1 Subtask - Implement session creation semantics with deterministic initial snapshot state.
      [x] 6.1.1.2 Subtask - Implement session update semantics for accepted compile/render pipeline outcomes.
      [x] 6.1.1.3 Subtask - Implement current snapshot query semantics with continuity metadata.

    [x] 6.1.2 Task - Implement in-memory `UiSessionSnapshot` contract
      Define and enforce in-memory snapshot structure, ownership, and lifecycle rules.

      [x] 6.1.2.1 Subtask - Define `UiSessionSnapshot` fields for active IUR hash, schema versions, and session metadata.
      [x] 6.1.2.2 Subtask - Implement in-memory storage and retrieval with no external persistence dependencies.
      [x] 6.1.2.3 Subtask - Implement typed errors for missing, invalid, or stale snapshot operations.

  [x] 6.2 Section - Last-Known-Good and Failure Retention Behavior
    Implement snapshot retention controls for compile/render failure paths.

    [x] 6.2.1 Task - Implement last-known-good snapshot retention
      Preserve prior good session projection when compile/render stages fail.

      [x] 6.2.1.1 Subtask - Implement retention policy for failed compile outcomes.
      [x] 6.2.1.2 Subtask - Implement retention policy for failed render outcomes.
      [x] 6.2.1.3 Subtask - Implement explicit rollback marker metadata in retained snapshots.

    [x] 6.2.2 Task - Implement session failure typed outcomes
      Normalize session-stage failures into typed errors with continuity metadata.

      [x] 6.2.2.1 Subtask - Define session failure error categories for transition, replay, and retention violations.
      [x] 6.2.2.2 Subtask - Implement session-stage typed error mapping and normalization.
      [x] 6.2.2.3 Subtask - Emit session failure events with replay and snapshot diagnostics.

  [x] 6.3 Section - Replay Determinism and Hash Parity Controls
    Implement deterministic replay behavior for command/event streams against in-memory snapshots.

    [x] 6.3.1 Task - Implement replay stream evaluation semantics
      Replay admitted command/event streams to reconstruct deterministic session state and IUR outputs.

      [x] 6.3.1.1 Subtask - Implement replay admission filters for only valid, policy-accepted events.
      [x] 6.3.1.2 Subtask - Implement deterministic replay ordering semantics.
      [x] 6.3.1.3 Subtask - Implement replay completion outcomes with typed status metadata.

    [x] 6.3.2 Task - Implement replay hash parity verification
      Verify replayed output reproduces expected active IUR hash values.

      [x] 6.3.2.1 Subtask - Implement replay-time IUR hash computation and comparison contract.
      [x] 6.3.2.2 Subtask - Implement parity mismatch typed errors and diagnostics.
      [x] 6.3.2.3 Subtask - Emit replay parity telemetry and mismatch counters.

  [x] 6.4 Section - Phase 6 Integration Tests
    Validate in-memory session authority, retention behavior, and replay determinism end-to-end.

    [x] 6.4.1 Task - Session transition and retention integration scenarios
      Verify session lifecycle behavior and last-known-good retention semantics.

      [x] 6.4.1.1 Subtask - Verify session create/update/current snapshot APIs operate under runtime authority.
      [x] 6.4.1.2 Subtask - Verify failed compile/render outcomes retain last-known-good projection.
      [x] 6.4.1.3 Subtask - Verify session operations run without external persistence dependencies.

    [x] 6.4.2 Task - Replay and parity integration scenarios
      Verify deterministic replay and hash parity outcomes from in-memory snapshots.

      [x] 6.4.2.1 Subtask - Verify replayed command/event streams produce deterministic state transitions.
      [x] 6.4.2.2 Subtask - Verify replay reconstructs expected active IUR hash parity.
      [x] 6.4.2.3 Subtask - Verify replay mismatches produce typed errors and telemetry diagnostics.
