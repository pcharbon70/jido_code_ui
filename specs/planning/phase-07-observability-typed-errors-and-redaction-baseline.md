# Phase 7 - Observability Typed Errors and Redaction Baseline

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoCodeUi.Observability.Telemetry.emit/2`
- `JidoCodeUi.Services.UiOrchestrator.execute/2`
- `JidoCodeUi.Services.DslCompiler.compile/2`
- `JidoCodeUi.Services.IurRenderer.render/2`
- `JidoCodeUi.Runtime.Substrate.admit/1`

## Relevant Assumptions / Defaults
- Required event families are mandatory across success and failure paths.
- Typed error normalization applies uniformly across all runtime stages.
- Sensitive prompt/code/token fields must be redacted in logs and telemetry.
- Phase SCN focus: `SCN-005`, `SCN-007`.

[x] 7 Phase 7 - Observability Typed Errors and Redaction Baseline
  Implement observability event families, metrics baselines, typed error normalization, and redaction controls across the full runtime pipeline.

  [x] 7.1 Section - Required Event Family Coverage
    Implement required lifecycle event coverage for ingest, policy, compile, render, and failure paths.

    [x] 7.1.1 Task - Implement structured event emission contracts
      Emit required observability events with continuity keys and stage metadata.

      [x] 7.1.1.1 Subtask - Implement event schema contracts for command, policy, compile, and render lifecycle families.
      [x] 7.1.1.2 Subtask - Implement event emission from substrate, orchestrator, compiler, and renderer paths.
      [x] 7.1.1.3 Subtask - Implement event versioning markers for schema governance.

    [x] 7.1.2 Task - Implement event continuity and join-key enforcement
      Enforce presence of `correlation_id`, `request_id`, and `session_id` in applicable telemetry events.

      [x] 7.1.2.1 Subtask - Implement event validation checks for required join keys.
      [x] 7.1.2.2 Subtask - Implement fallback handling for missing continuity metadata.
      [x] 7.1.2.3 Subtask - Emit telemetry validation failures as typed observability diagnostics.

  [x] 7.2 Section - Typed Error Normalization Baseline
    Implement consistent typed error normalization across runtime stages.

    [x] 7.2.1 Task - Implement cross-stage typed error mapping
      Normalize errors from ingest, policy, compile, render, and session paths into canonical `TypedError` shape.

      [x] 7.2.1.1 Subtask - Define canonical error category and stage mapping table.
      [x] 7.2.1.2 Subtask - Implement mapping adapters in each runtime stage.
      [x] 7.2.1.3 Subtask - Implement typed error conformance checks against contract requirements.

    [x] 7.2.2 Task - Implement failure telemetry with typed metadata
      Emit failure telemetry that includes typed error fields and stage context.

      [x] 7.2.2.1 Subtask - Emit typed error fields on failed compile and render events.
      [x] 7.2.2.2 Subtask - Emit typed error fields on policy denied and substrate reject events.
      [x] 7.2.2.3 Subtask - Emit typed error counters by category and stage for metrics baselines.

  [x] 7.3 Section - Sensitive Data Redaction Controls
    Implement redaction rules for sensitive payload fields in logs and telemetry streams.

    [x] 7.3.1 Task - Implement runtime redaction policy execution
      Enforce sensitive field redaction for prompt fragments, code payloads, and token material.

      [x] 7.3.1.1 Subtask - Define redaction patterns and field classification for sensitive inputs.
      [x] 7.3.1.2 Subtask - Implement redaction transforms prior to telemetry emission.
      [x] 7.3.1.3 Subtask - Implement redaction coverage checks for denied and failure paths.

    [x] 7.3.2 Task - Implement redaction observability diagnostics
      Emit diagnostics for redaction execution and redaction policy misses.

      [x] 7.3.2.1 Subtask - Emit redaction-applied indicators in relevant telemetry events.
      [x] 7.3.2.2 Subtask - Emit redaction-miss alerts for unsafe field leakage attempts.
      [x] 7.3.2.3 Subtask - Emit policy-version metadata for redaction rule governance.

  [x] 7.4 Section - Phase 7 Integration Tests
    Validate telemetry coverage, typed error normalization, and redaction behavior end-to-end.

    [x] 7.4.1 Task - Telemetry completeness integration scenarios
      Verify required event families and metrics are emitted across success and failure flows.

      [x] 7.4.1.1 Subtask - Verify compile/render lifecycle event family coverage.
      [x] 7.4.1.2 Subtask - Verify policy denied and substrate reject telemetry coverage.
      [x] 7.4.1.3 Subtask - Verify continuity join keys are present in required events.

    [x] 7.4.2 Task - Redaction and typed error integration scenarios
      Verify sensitive data redaction and typed error metadata in failure telemetry.

      [x] 7.4.2.1 Subtask - Verify sensitive prompt/code/token fields are redacted in emitted telemetry.
      [x] 7.4.2.2 Subtask - Verify typed errors include category and stage metadata across failures.
      [x] 7.4.2.3 Subtask - Verify redaction misses and telemetry policy violations emit diagnostics.
