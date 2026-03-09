# Phase 3 - Policy Governance and Orchestrator Control Flow

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `JidoCodeUi.Security.Policy.authorize/2`
- `JidoCodeUi.Services.UiOrchestrator.execute/2`
- `JidoCodeUi.Services.DslCompiler.compile/2`
- `JidoCodeUi.Session.RuntimeAgent`
- `JidoCodeUi.Services.IurRenderer.render/2`

## Relevant Assumptions / Defaults
- Policy checks execute before compile or state-changing operations.
- Feature-flag governance is the authority boundary for custom DSL nodes.
- Orchestrator routing is deterministic for equivalent validated inputs.
- Phase SCN focus: `SCN-002`, `SCN-006`, `SCN-007`, `SCN-008`.

[ ] 3 Phase 3 - Policy Governance and Orchestrator Control Flow
  Implement deterministic orchestrator execution with explicit policy governance, deny behavior, and feature-flag custom-node controls.

  [ ] 3.1 Section - Policy Authority and Feature-Flag Governance
    Implement canonical policy evaluation behavior and feature-flag decisions for DSL node execution.

    [ ] 3.1.1 Task - Implement authorization and policy-version evaluation
      Enforce policy decisions through `JidoCodeUi.Security.Policy.authorize/2` before compile and session mutation paths.

      [ ] 3.1.1.1 Subtask - Implement policy decision request shape including actor, command, and context metadata.
      [ ] 3.1.1.2 Subtask - Implement policy-version tagging in allow and deny outcomes.
      [ ] 3.1.1.3 Subtask - Implement typed deny outcomes for unauthorized mutating requests.

    [ ] 3.1.2 Task - Implement custom-node feature-flag gating
      Enforce that custom DSL nodes execute only when allowed by policy-versioned feature flags.

      [ ] 3.1.2.1 Subtask - Implement feature-flag lookup contract bound to policy context.
      [ ] 3.1.2.2 Subtask - Implement deny behavior for unsupported or disabled custom node usage.
      [ ] 3.1.2.3 Subtask - Emit policy telemetry for custom-node allow/deny decisions.

  [ ] 3.2 Section - Deterministic Orchestrator Routing
    Implement orchestrator routing from validated ingress to compile, session, and render flow.

    [ ] 3.2.1 Task - Implement canonical execute pipeline ordering
      Enforce `validate -> policy -> compile -> session -> render` in `JidoCodeUi.Services.UiOrchestrator.execute/2`.

      [ ] 3.2.1.1 Subtask - Implement deterministic route-key derivation for equivalent request inputs.
      [ ] 3.2.1.2 Subtask - Implement explicit stage-order guards preventing out-of-order execution.
      [ ] 3.2.1.3 Subtask - Implement typed orchestration failures with stage metadata.

    [ ] 3.2.2 Task - Implement denied-path and redaction-safe behavior
      Ensure denied paths fail closed and avoid sensitive data leakage in diagnostics.

      [ ] 3.2.2.1 Subtask - Implement fail-closed denied outcomes for auth and feature-flag failures.
      [ ] 3.2.2.2 Subtask - Implement redaction for sensitive prompt/code fields in denied telemetry.
      [ ] 3.2.2.3 Subtask - Implement denied-path observability events with continuity IDs.

  [ ] 3.3 Section - Orchestrator Contracts and Type Alignment
    Implement orchestration type compatibility with downstream compile, session, and render services.

    [ ] 3.3.1 Task - Implement orchestration request/response type contracts
      Define stable orchestrator input/output types compatible with compile and render service contracts.

      [ ] 3.3.1.1 Subtask - Define `UiCommand` and admitted event envelope contracts consumed by `execute/2`.
      [ ] 3.3.1.2 Subtask - Define typed success output contract passed into session and renderer flows.
      [ ] 3.3.1.3 Subtask - Define typed failure output contract for stage-specific orchestration errors.

    [ ] 3.3.2 Task - Implement orchestration telemetry contract alignment
      Emit required event families for accepted, denied, and failed orchestration outcomes.

      [ ] 3.3.2.1 Subtask - Emit command-received and policy-denied events with policy version metadata.
      [ ] 3.3.2.2 Subtask - Emit stage transition events covering compile, session, and render stages.
      [ ] 3.3.2.3 Subtask - Emit orchestrator outcome metrics for success, deny, and failure branches.

  [ ] 3.4 Section - Phase 3 Integration Tests
    Validate policy gating, deterministic orchestration flow, and denied-path behavior end-to-end.

    [ ] 3.4.1 Task - Policy allow/deny integration scenarios
      Verify policy decisions and feature flags deterministically gate orchestrator execution.

      [ ] 3.4.1.1 Subtask - Verify authorized commands pass to compile stage with policy metadata.
      [ ] 3.4.1.2 Subtask - Verify unauthorized commands fail closed before compile or session mutation.
      [ ] 3.4.1.3 Subtask - Verify custom-node commands are allowed only with enabled feature flags.

    [ ] 3.4.2 Task - Orchestrator routing and denied-path integration scenarios
      Verify deterministic stage ordering and redaction-safe denied telemetry.

      [ ] 3.4.2.1 Subtask - Verify equivalent inputs produce identical `execute/2` routing outcomes.
      [ ] 3.4.2.2 Subtask - Verify denied-path failures emit typed errors and required audit events.
      [ ] 3.4.2.3 Subtask - Verify denied-path telemetry redacts sensitive command payload fields.
