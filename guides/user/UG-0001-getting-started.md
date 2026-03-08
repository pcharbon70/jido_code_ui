# UG-0001: Getting Started with JidoCodeUi Runtime Flows

## Metadata

- Guide ID: `UG-0001`
- Audience: `User`
- Status: `Active`
- Owners: `@jido-code-ui`
- Last Reviewed: `2026-03-08`
- Diagram Required: `no`

## Purpose

Provide a minimal path to submit UI runtime events with valid metadata and interpret typed outcomes.

## Prerequisites

- Access to a running `jido_code_ui` runtime.
- A caller identity authorized for target operations.
- Familiarity with correlation fields (`correlation_id`, `request_id`) and typed error shapes.

## Workflow

1. Build a widget event payload with required fields (`type`, `widget_id`, `widget_kind`, `data`).
2. Submit the payload through the runtime ingress boundary.
3. Validate typed outcomes and error categories (`validation`, `authorization`, `protocol`, `internal`).
4. Use correlation metadata to trace events and metrics across runtime surfaces.

## Expected Outcomes

- Valid requests return deterministic typed envelopes.
- Invalid or unauthorized requests fail closed with typed errors.
- Observability fields are present for tracing.

## Failure Cases

- Missing required fields (`type`, `widget_id`, `widget_kind`, `data`) produce typed validation errors.
- Unauthorized operations produce auditable authorization failures.
- Schema/version incompatibilities produce typed data contract errors.

## Governance Mapping

### Spec Refs

- [service_contract.md](../../specs/contracts/service_contract.md)
- [security_contract.md](../../specs/contracts/security_contract.md)
- [observability_contract.md](../../specs/contracts/observability_contract.md)
- [event_type_catalog.md](../../specs/events/event_type_catalog.md)

### REQ Refs

- `REQ-GUIDE-*`
- `REQ-GTRACE-*`
- `REQ-SVC-*`
- `REQ-SEC-*`
- `REQ-OBS-*`

### Scenario Refs

- `SCN-002`
- `SCN-003`
- `SCN-004`
- `SCN-005`
- `SCN-006`
- `GSCN-001`
- `GSCN-003`
- `GSCN-004`
- `GSCN-005`
