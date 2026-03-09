# Design

## Purpose

`jido_code_ui` defines a coding interface runtime where product UI is authored in `unified-ui` DSL, transformed into `unified-iur`, and rendered through `web-ui`. The system MUST keep this pipeline deterministic so the same DSL input and runtime context produce the same IUR and user-visible behavior.

## Core Model

The runtime model has four stages:

1. Intake: user/session commands and widget events enter through a validated ingress envelope.
2. Orchestration: runtime service resolves command intent, policy checks, and compile/render work.
3. Transformation: DSL documents are compiled into canonical `unified-iur` documents.
4. Presentation: `web-ui` adapters render IUR and emit typed interaction events back to intake.

Each stage MUST preserve `correlation_id` and `request_id` for traceability.

## Key Constraints

- The DSL to IUR transform MUST be deterministic for identical DSL input, schema version, and compile context.
- DSL to IUR transformation authority is server-side only.
- Ingress transport MUST NOT own session/domain state mutation authority.
- Runtime failures MUST surface typed error payloads with pipeline stage metadata.
- DSL and IUR schemas MUST be versioned and compatibility-checked.
- Authorization MUST gate mutating commands before compile/render side effects.
- Custom DSL node types MAY execute only when explicitly enabled by feature-flag policy.
- Session snapshots are in-memory only in v1 runtime scope.

## Open Questions

- Should compile caches key by full DSL hash only, or by DSL hash plus policy/runtime profile?
- What operational limits should govern feature-flagged custom node rollout (per tenant, per project, or global)?
