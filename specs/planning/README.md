# Jido Code UI Architecture Execution Plan Index

This directory contains a phased implementation plan for executing the current `jido_code_ui` architecture and topology baseline.

The plan aligns to:
- `specs/topology.md`
- `specs/design.md`
- `specs/contracts/*`
- `specs/conformance/*`

## Phase Files
1. [Phase 1 - Core Runtime Backbone and Supervision Boot](./phase-01-core-runtime-backbone-and-supervision-boot.md): implement OTP boot ordering, supervision wiring, and control-plane boundary enforcement.
2. [Phase 2 - Runtime Ingress Substrate and Envelope Validation](./phase-02-runtime-ingress-substrate-and-envelope-validation.md): implement ingress envelope validation, normalization, and continuity propagation.
3. [Phase 3 - Policy Governance and Orchestrator Control Flow](./phase-03-policy-governance-and-orchestrator-control-flow.md): implement policy authority and deterministic orchestrator routing behavior.
4. [Phase 4 - DSL Compiler and IUR Canonicalization](./phase-04-dsl-compiler-and-iur-canonicalization.md): implement deterministic, server-authoritative DSL compilation into canonical IUR.
5. [Phase 5 - IUR Renderer and Web UI Event Projection Loop](./phase-05-iur-renderer-and-web-ui-event-projection-loop.md): implement IUR rendering and browser event projection loop contracts.
6. [Phase 6 - Session Runtime In-Memory State and Replay Control](./phase-06-session-runtime-in-memory-state-and-replay-control.md): implement in-memory session state authority and replay/hash-parity controls.
7. [Phase 7 - Observability Typed Errors and Redaction Baseline](./phase-07-observability-typed-errors-and-redaction-baseline.md): implement telemetry, metrics, typed error normalization, and sensitive data redaction.
8. [Phase 8 - Conformance Governance Gates and Release Readiness](./phase-08-conformance-governance-gates-and-release-readiness.md): implement full SCN conformance, governance gate hardening, and release-readiness automation.

## Shared Conventions
- Numbering:
  - Phases: `N`
  - Sections: `N.M`
  - Tasks: `N.M.K`
  - Subtasks: `N.M.K.L`
- Tracking:
  - Every phase, section, task, and subtask uses Markdown checkboxes (`[ ]`).
- Description requirement:
  - Every phase, section, and task starts with a short description paragraph.
- Integration-test requirement:
  - Each phase ends with a final integration-testing section.

## Shared Assumptions and Defaults
- `jido_code_ui` runtime remains the canonical authority for server-side orchestration and compile behavior.
- DSL-to-IUR compilation is server-authoritative and deterministic for identical inputs.
- Custom DSL node execution is allowed only through policy-versioned feature flags.
- Session snapshots are in-memory only for v1 runtime scope.
- Contract and conformance docs define normative behavior for implementation and review.
