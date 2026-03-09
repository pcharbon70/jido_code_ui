# Phase 1 - Core Runtime Backbone and Supervision Boot

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoCodeUi.Application.start/2`
- `JidoCodeUi.Runtime.Substrate.admit/1`
- `JidoCodeUi.Services.UiOrchestrator.execute/2`
- `JidoCodeUi.Services.DslCompiler.compile/2`
- `JidoCodeUi.Services.IurRenderer.render/2`
- `JidoCodeUi.Session.RuntimeAgent`

## Relevant Assumptions / Defaults
- Runtime startup ordering is deterministic and contract-governed.
- Root supervision wiring enforces control-plane ownership boundaries.
- Ingress admission remains blocked until required runtime children are ready.
- Phase SCN focus: `SCN-001`, `SCN-003`, `SCN-004`.

[x] 1 Phase 1 - Core Runtime Backbone and Supervision Boot
  Implement OTP startup and supervision ordering so runtime services initialize in deterministic order and preserve control-plane boundaries.

  [x] 1.1 Section - Application and Root Supervisor Boot
    Implement root startup contracts for `JidoCodeUi.Application` and runtime child composition.

    [x] 1.1.1 Task - Implement deterministic root child startup ordering
      Define and enforce child-spec startup order for substrate, policy, orchestrator, compiler, renderer, and session runtime services.

      [x] 1.1.1.1 Subtask - Implement explicit child-spec order in `JidoCodeUi.Application.start/2`.
      [x] 1.1.1.2 Subtask - Implement readiness gate that blocks ingress before required services start.
      [x] 1.1.1.3 Subtask - Emit startup lifecycle outcomes with `correlation_id` and `request_id`.

    [x] 1.1.2 Task - Implement root restart and fault semantics
      Define restart strategy and escalation behavior that preserves service isolation boundaries.

      [x] 1.1.2.1 Subtask - Configure root supervisor strategy, intensity, and restart policy defaults.
      [x] 1.1.2.2 Subtask - Implement typed error propagation for startup and dependency failures.
      [x] 1.1.2.3 Subtask - Emit restart and escalation telemetry for recovery visibility.

  [x] 1.2 Section - Runtime Wiring and Control-Plane Boundary Enforcement
    Implement canonical wiring for runtime modules while enforcing ownership boundaries in the startup graph.

    [x] 1.2.1 Task - Implement runtime module child-spec wiring
      Wire `JidoCodeUi.Runtime.Substrate`, `JidoCodeUi.Security.Policy`, `JidoCodeUi.Services.UiOrchestrator`, `JidoCodeUi.Services.DslCompiler`, `JidoCodeUi.Services.IurRenderer`, and `JidoCodeUi.Session.RuntimeAgent` into the supervision tree.

      [x] 1.2.1.1 Subtask - Register substrate and policy services before orchestration and compile services.
      [x] 1.2.1.2 Subtask - Register compiler and renderer services with deterministic dependency ordering.
      [x] 1.2.1.3 Subtask - Register session runtime authority as a required runtime child.

    [x] 1.2.2 Task - Implement control-plane boundary startup checks
      Enforce that transport modules do not own session mutation and runtime modules own state-changing semantics.

      [x] 1.2.2.1 Subtask - Implement startup assertions against control-plane ownership matrix mappings.
      [x] 1.2.2.2 Subtask - Implement guardrails that deny alternate ownership for session mutation paths.
      [x] 1.2.2.3 Subtask - Emit denied-boundary diagnostics as typed startup errors.

  [x] 1.3 Section - Startup Contracts and Typed Outcome Baseline
    Implement baseline startup contracts and typed outcomes needed by downstream phases.

    [x] 1.3.1 Task - Implement startup contract interfaces for downstream runtime calls
      Ensure startup and readiness expose required interfaces for admission, orchestration, compile, render, and session control.

      [x] 1.3.1.1 Subtask - Define startup availability contract for `JidoCodeUi.Runtime.Substrate.admit/1`.
      [x] 1.3.1.2 Subtask - Define startup availability contract for `JidoCodeUi.Services.UiOrchestrator.execute/2`.
      [x] 1.3.1.3 Subtask - Define startup availability contracts for `compile/2`, `render/2`, and session runtime APIs.

    [x] 1.3.2 Task - Implement root typed error normalization
      Normalize startup failures into typed error outcomes that preserve continuity metadata.

      [x] 1.3.2.1 Subtask - Define startup `TypedError` categories for dependency, timeout, and boundary failures.
      [x] 1.3.2.2 Subtask - Normalize root startup failure envelopes with stage metadata.
      [x] 1.3.2.3 Subtask - Validate `TypedError` shape compatibility with conformance scenarios.

  [x] 1.4 Section - Phase 1 Integration Tests
    Validate startup ordering, boundary enforcement, and typed startup outcomes end-to-end.

    [x] 1.4.1 Task - Startup ordering and readiness integration scenarios
      Verify deterministic startup ordering and readiness gate behavior.

      [x] 1.4.1.1 Subtask - Verify required runtime children start in canonical order.
      [x] 1.4.1.2 Subtask - Verify ingress admission is denied before readiness and allowed after readiness.
      [x] 1.4.1.3 Subtask - Verify continuity metadata appears on startup lifecycle outcomes.

    [x] 1.4.2 Task - Boundary and failure-path integration scenarios
      Verify root fault semantics, ownership boundary enforcement, and typed startup errors.

      [x] 1.4.2.1 Subtask - Verify transport modules cannot assume session authority at startup.
      [x] 1.4.2.2 Subtask - Verify startup dependency faults produce normalized typed errors.
      [x] 1.4.2.3 Subtask - Verify restart and escalation telemetry is emitted for failure paths.
