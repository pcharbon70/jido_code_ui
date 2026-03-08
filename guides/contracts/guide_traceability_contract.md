# Guide Traceability Contract

This contract defines traceability and compliance requirements for guide governance.

## Requirement Set

### `REQ-GTRACE-001` Guide-to-Spec Mapping

Every guide MUST reference one or more canonical `specs/*.md` sources for the behavior it documents.

### `REQ-GTRACE-002` Guide-to-Requirement Mapping

Every guide MUST reference at least one requirement family from:

- `REQ-*` families defined in `specs/conformance/spec_conformance_matrix.md`
- `REQ-GUIDE-*` and `REQ-GTRACE-*` defined under `guides/contracts`

### `REQ-GTRACE-003` Guide-to-Scenario Mapping

Every guide MUST reference at least one scenario identifier from:

- `SCN-*` in `specs/conformance/scenario_catalog.md`
- `GSCN-*` in `guides/conformance/guide_scenario_catalog.md`

### `REQ-GTRACE-004` Conformance Matrix Coverage

Every guide MUST have a row in `guides/conformance/guide_conformance_matrix.md` including:

- guide path
- guide id
- audience
- requirement families
- scenario coverage

### `REQ-GTRACE-005` Change-Set Consistency

Changes to guide content SHOULD update guide conformance mappings in the same change set when requirement or scenario mappings change.

### `REQ-GTRACE-006` Conflict Resolution

When a guide conflicts with contracts/specs, contracts under `specs/contracts` and `guides/contracts` MUST take precedence.
