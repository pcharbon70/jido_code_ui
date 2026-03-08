# Specs Index

This directory defines the architecture and governance specification system for `jido_code_ui`.

Normative language in this directory uses RFC-2119 terms: **MUST**, **MUST NOT**, **SHOULD**, **SHOULD NOT**, and **MAY**.

## How The Specs System Works

This specs system has five layers:

1. Baseline architecture docs define intent and boundaries:
   - [design.md](design.md)
   - [topology.md](topology.md)
   - [boundaries.md](boundaries.md)
   - [control_planes.md](control_planes.md)
   - [services-and-libraries.md](services-and-libraries.md)
   - [targets.md](targets.md)
2. Contracts define enforceable requirement families (`REQ-*`) using normative language.
3. ADRs capture architectural authority and decision history.
4. Conformance maps requirement families to testable scenarios (`SCN-*`).
5. Operations/planning docs govern rollout and execution sequencing.

## Traceability Model

- Contracts define requirement IDs: `REQ-CP-*`, `REQ-SVC-*`, `REQ-OBS-*`, `REQ-SEC-*`, `REQ-DATA-*`.
- Conformance defines scenario IDs: `SCN-*`.
- Component specs (added later) define acceptance criteria IDs: `AC-*`.
- Every `AC-*` MUST map to at least one `REQ-*` and at least one `SCN-*`.

## Governance Model

Expected change policy:

1. Architecture or contract baseline changes require an ADR update in the same change set.
2. Contract changes require conformance matrix updates in the same change set.
3. AC-bearing component spec changes require:
   - contract updates when behavior changes
   - conformance matrix updates when AC shape changes

## Canonical Baselines

- [design.md](design.md)
- [topology.md](topology.md)
- [boundaries.md](boundaries.md)
- [control_planes.md](control_planes.md)
- [targets.md](targets.md)
- [services-and-libraries.md](services-and-libraries.md)

## Contract Layer

- [contracts/control_plane_ownership_matrix.md](contracts/control_plane_ownership_matrix.md)
- [contracts/service_contract.md](contracts/service_contract.md)
- [contracts/observability_contract.md](contracts/observability_contract.md)
- [contracts/security_contract.md](contracts/security_contract.md)
- [contracts/data_contract.md](contracts/data_contract.md)

## ADRs

- [adr/ADR-0001-control-plane-authority.md](adr/ADR-0001-control-plane-authority.md)

## Conformance

- [conformance/spec_conformance_matrix.md](conformance/spec_conformance_matrix.md)
- [conformance/scenario_catalog.md](conformance/scenario_catalog.md)

## Events

- [events/README.md](events/README.md)
- [events/event_type_catalog.md](events/event_type_catalog.md)
- [events/widget_event_matrix.md](events/widget_event_matrix.md)
- [events/elm_binding_examples.md](events/elm_binding_examples.md)

## Operations

- [operations/README.md](operations/README.md)

## Planning

- [planning/README.md](planning/README.md)

## Governance Validation

Run the docs governance gate locally:

```bash
./scripts/validate_specs_governance.sh
```

Run the executable conformance harness locally:

```bash
./scripts/run_conformance.sh
```

or:

```bash
mix conformance
```

CI runs the same checks in:

- `.github/workflows/specs-governance.yml`
- `.github/workflows/conformance.yml`
- `.github/workflows/guides-governance.yml`

Related governance siblings:

- `rfcs/` for proposal lifecycle and spec creation plans.
- `guides/` for user/developer guide governance and compliance.

## Existing Component Indexes

- [core/README.md](core/README.md)
- [services/README.md](services/README.md)
- [session/README.md](session/README.md)
- [infrastructure/README.md](infrastructure/README.md)

## Start Here

- [getting-started.md](getting-started.md)
