# Specs Getting Started

This guide bootstraps a new project using the specs architecture.

## 1) Confirm Baseline Intent

Fill these docs first with concise, high-signal content:

- `design.md`
- `topology.md`
- `boundaries.md`
- `control_planes.md`
- `services-and-libraries.md`
- `targets.md`

Goal: define ownership, major runtime surfaces, and target outcomes before detailed requirements.

## 2) Lock Authority With ADR-0001

Update `adr/ADR-0001-control-plane-authority.md` with:

- authority boundaries
- non-authoritative extension seams
- payload or protocol invariants

This is the architectural tie-breaker when docs conflict.

## 3) Define Initial Contracts

Populate contract requirement sets:

- `contracts/control_plane_ownership_matrix.md`
- `contracts/service_contract.md`
- `contracts/observability_contract.md`
- `contracts/security_contract.md`
- `contracts/data_contract.md`

Use stable IDs (`REQ-*`) and normative statements (`MUST`, `MUST NOT`, `SHOULD`).

## 4) Define Conformance Baseline

Populate:

- `conformance/scenario_catalog.md` with `SCN-*` scenarios
- `conformance/spec_conformance_matrix.md` with mapping:
  - requirement families -> owning contracts -> runtime modules -> scenarios

## 5) Define Event Handling Surface

If the project includes interactive UI surfaces, define:

- `events/event_type_catalog.md`
- `events/widget_event_matrix.md`
- `events/elm_binding_examples.md`

Use Elm handler APIs (`Html.Events`, `Browser.Events`) as the baseline trigger model.

## 6) Add Component Specs Later

When implementation starts, add component specs with acceptance criteria IDs (`AC-*`) and map them to:

- one or more `REQ-*` families
- one or more `SCN-*` scenarios

## 7) Introduce Governance Automation

Add scripts/workflows/hooks to enforce change policy in CI:

- governance validation script
- conformance runner
- PR/push workflows
- pre-commit and pre-push hooks

If you already have those, wire them to fail fast on traceability drift.

## Suggested First Week Sequence

1. Complete baseline docs and ADR-0001.
2. Draft 3-5 requirement families in contracts.
3. Draft event catalog and widget-to-event matrix.
4. Draft 8-12 conformance scenarios.
5. Add governance checks in CI.
6. Start component specs and implementation in parallel.
