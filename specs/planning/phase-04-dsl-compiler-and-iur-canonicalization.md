# Phase 4 - DSL Compiler and IUR Canonicalization

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoCodeUi.Services.DslCompiler.compile/2`
- `JidoCodeUi.Services.UiOrchestrator.execute/2`
- `JidoCodeUi.Security.Policy.authorize/2`
- `JidoCodeUi.Observability.Telemetry`

## Relevant Assumptions / Defaults
- Compile authority is server-only in v1.
- Determinism requires stable schema validation and canonical output ordering.
- Custom node handling must honor feature-flag policy decisions.
- Phase SCN focus: `SCN-004`, `SCN-008`.

[x] 4 Phase 4 - DSL Compiler and IUR Canonicalization
  Implement DSL schema validation and deterministic server-authoritative compilation into canonical `UnifiedIurDocument` outputs.

  [x] 4.1 Section - DSL Schema Validation and Compatibility
    Implement compile-time validation for DSL inputs and compatibility constraints.

    [x] 4.1.1 Task - Implement DSL input contract validation
      Validate `UnifiedUiDslDocument` payloads prior to compile execution.

      [x] 4.1.1.1 Subtask - Implement required schema fields and structural validation for DSL documents.
      [x] 4.1.1.2 Subtask - Implement schema version compatibility checks for supported DSL versions.
      [x] 4.1.1.3 Subtask - Implement typed validation failures with schema-path diagnostics.

    [x] 4.1.2 Task - Implement custom-node compatibility rules
      Apply feature-flag and compatibility checks for custom DSL node inclusion.

      [x] 4.1.2.1 Subtask - Implement policy-verified custom-node allowlist checks before compile.
      [x] 4.1.2.2 Subtask - Implement compatibility diagnostics for unsupported custom-node combinations.
      [x] 4.1.2.3 Subtask - Implement typed reject outcomes for disallowed custom-node payloads.

  [x] 4.2 Section - Deterministic Server-Authoritative Compilation
    Implement canonical compile behavior through `JidoCodeUi.Services.DslCompiler.compile/2`.

    [x] 4.2.1 Task - Implement canonical compilation and output ordering
      Compile validated DSL into deterministic `UnifiedIurDocument` outputs with stable ordering and hash semantics.

      [x] 4.2.1.1 Subtask - Implement canonical output ordering for IUR nodes and attributes.
      [x] 4.2.1.2 Subtask - Implement stable IUR hash generation for equivalent compile inputs.
      [x] 4.2.1.3 Subtask - Implement deterministic diagnostics ordering for compile outcomes.

    [x] 4.2.2 Task - Implement compile result contract with server authority markers
      Return `CompileResult` with compile authority and version metadata.

      [x] 4.2.2.1 Subtask - Implement `CompileResult` fields for `dsl_version`, `iur_version`, `iur_hash`, and diagnostics.
      [x] 4.2.2.2 Subtask - Implement `compile_authority: "server"` enforcement in all successful compile outcomes.
      [x] 4.2.2.3 Subtask - Implement typed compile failure outcomes with stage metadata.

  [x] 4.3 Section - Compiler Telemetry and Failure Normalization
    Implement observability coverage for compile lifecycle and failures.

    [x] 4.3.1 Task - Implement compile lifecycle event emission
      Emit required compile started/completed/failed events with continuity metadata.

      [x] 4.3.1.1 Subtask - Emit `ui.dsl.compile.started.v1` before compile execution.
      [x] 4.3.1.2 Subtask - Emit `ui.dsl.compile.completed.v1` for successful compile outcomes.
      [x] 4.3.1.3 Subtask - Emit `ui.dsl.compile.failed.v1` with typed error metadata.

    [x] 4.3.2 Task - Implement compile metrics baseline
      Emit compile latency, throughput, and failure metrics for conformance visibility.

      [x] 4.3.2.1 Subtask - Implement compile latency metrics by schema version and node complexity class.
      [x] 4.3.2.2 Subtask - Implement compile success/failure counters with error category labels.
      [x] 4.3.2.3 Subtask - Implement compile determinism parity diagnostics for repeated input runs.

  [x] 4.4 Section - Phase 4 Integration Tests
    Validate schema compatibility, deterministic compile parity, and typed compile failure behavior.

    [x] 4.4.1 Task - Hash parity and version compatibility integration scenarios
      Verify compile determinism and schema compatibility across equivalent and incompatible inputs.

      [x] 4.4.1.1 Subtask - Verify repeated equivalent DSL inputs produce identical IUR hash outputs.
      [x] 4.4.1.2 Subtask - Verify unsupported DSL schema versions fail with typed compatibility errors.
      [x] 4.4.1.3 Subtask - Verify allowed custom nodes compile only when feature flags are enabled.

    [x] 4.4.2 Task - Compile failure and observability integration scenarios
      Verify compile failures normalize into typed outcomes and emit required telemetry.

      [x] 4.4.2.1 Subtask - Verify compile failures include stage-tagged `TypedError` metadata.
      [x] 4.4.2.2 Subtask - Verify compile lifecycle events are emitted for success and failure paths.
      [x] 4.4.2.3 Subtask - Verify compile metrics coverage for latency and failure families.
