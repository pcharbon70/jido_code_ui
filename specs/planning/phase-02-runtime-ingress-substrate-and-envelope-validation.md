# Phase 2 - Runtime Ingress Substrate and Envelope Validation

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoCodeUi.Runtime.Substrate.admit/1`
- `JidoCodeUi.Security.Policy.authorize/2`
- `JidoCodeUi.Services.UiOrchestrator.execute/2`
- `JidoCodeUi.Observability.Telemetry`

## Relevant Assumptions / Defaults
- Ingress validation executes before orchestration dispatch.
- Envelope continuity metadata must persist through runtime dispatch.
- Auth context propagation is required for policy-authority decisions.
- Phase SCN focus: `SCN-002`, `SCN-003`, `SCN-006`, `SCN-008`.

[ ] 2 Phase 2 - Runtime Ingress Substrate and Envelope Validation
  Implement ingress substrate behavior for envelope validation, normalization, continuity propagation, and typed reject outcomes.

  [ ] 2.1 Section - Envelope Schema Validation and Normalization
    Implement canonical envelope schema handling for `UiCommand` and `WidgetUiEventEnvelope` paths.

    [ ] 2.1.1 Task - Implement admission schema validation in substrate
      Validate ingress request shapes before any orchestration or compile path execution.

      [ ] 2.1.1.1 Subtask - Implement `UiCommand` schema validation in `JidoCodeUi.Runtime.Substrate.admit/1`.
      [ ] 2.1.1.2 Subtask - Implement `WidgetUiEventEnvelope` schema validation in `JidoCodeUi.Runtime.Substrate.admit/1`.
      [ ] 2.1.1.3 Subtask - Emit schema-path diagnostics in typed validation failures.

    [ ] 2.1.2 Task - Implement canonical envelope normalization
      Normalize validated payloads into runtime-consumable shapes with stable field semantics.

      [ ] 2.1.2.1 Subtask - Implement canonical key mapping and normalization for command and widget event payloads.
      [ ] 2.1.2.2 Subtask - Implement required default-field handling for runtime dispatch compatibility.
      [ ] 2.1.2.3 Subtask - Emit normalization result telemetry including validation outcome markers.

  [ ] 2.2 Section - Continuity and Auth Propagation
    Implement continuity and auth propagation needed by policy and orchestration layers.

    [ ] 2.2.1 Task - Implement correlation continuity propagation
      Preserve and propagate `correlation_id` and `request_id` through substrate admission and dispatch.

      [ ] 2.2.1.1 Subtask - Validate continuity IDs are required and well-formed at ingress.
      [ ] 2.2.1.2 Subtask - Propagate continuity IDs to orchestrator dispatch envelopes.
      [ ] 2.2.1.3 Subtask - Emit continuity-check telemetry for success and reject paths.

    [ ] 2.2.2 Task - Implement auth context propagation to policy layer
      Attach trusted auth context in substrate output for deterministic policy decisions.

      [ ] 2.2.2.1 Subtask - Normalize inbound auth context into policy-consumable shape.
      [ ] 2.2.2.2 Subtask - Attach propagated auth context to orchestrator request envelopes.
      [ ] 2.2.2.3 Subtask - Emit auth-propagation deny diagnostics for missing or invalid state.

  [ ] 2.3 Section - Typed Ingress Error Contracts
    Implement typed error contracts for ingress denials and malformed envelope outcomes.

    [ ] 2.3.1 Task - Implement substrate typed reject outcomes
      Normalize malformed envelope and invalid-admission outcomes into `TypedError` responses.

      [ ] 2.3.1.1 Subtask - Define ingress error codes for schema, auth, and continuity violations.
      [ ] 2.3.1.2 Subtask - Implement `TypedError` mapping for all substrate reject branches.
      [ ] 2.3.1.3 Subtask - Validate reject outcomes include stage metadata and continuity IDs when available.

    [ ] 2.3.2 Task - Implement ingress telemetry and audit events
      Emit required ingress observability events for accepted and denied admission attempts.

      [ ] 2.3.2.1 Subtask - Emit `ui.command.received.v1` for accepted admissions.
      [ ] 2.3.2.2 Subtask - Emit denied admission events with reason and policy context.
      [ ] 2.3.2.3 Subtask - Emit ingress failure metrics for malformed and unauthorized attempts.

  [ ] 2.4 Section - Phase 2 Integration Tests
    Validate ingress schema behavior, continuity propagation, and typed reject outcomes end-to-end.

    [ ] 2.4.1 Task - Malformed payload and rejection integration scenarios
      Verify malformed and invalid ingress envelopes are denied before orchestration dispatch.

      [ ] 2.4.1.1 Subtask - Verify malformed `UiCommand` payloads fail with typed schema errors.
      [ ] 2.4.1.2 Subtask - Verify malformed `WidgetUiEventEnvelope` payloads fail with typed schema errors.
      [ ] 2.4.1.3 Subtask - Verify denied paths emit required ingress telemetry and diagnostics.

    [ ] 2.4.2 Task - Continuity and auth propagation integration scenarios
      Verify admitted envelopes preserve continuity and auth data into orchestrator inputs.

      [ ] 2.4.2.1 Subtask - Verify continuity IDs propagate unchanged into orchestrator execution inputs.
      [ ] 2.4.2.2 Subtask - Verify auth context propagation supports downstream policy calls.
      [ ] 2.4.2.3 Subtask - Verify admit outcomes satisfy SCN continuity and authorization expectations.
