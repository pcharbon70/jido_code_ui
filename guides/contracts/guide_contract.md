# Guide Contract

This contract defines canonical authoring requirements for all guide documents under `guides/user` and `guides/developer`.

## Requirement Set

### `REQ-GUIDE-001` Metadata Completeness

Every guide MUST include:

- `Guide ID`
- `Audience`
- `Status`
- `Owners`
- `Last Reviewed`
- `Diagram Required`

### `REQ-GUIDE-002` Audience Segregation

User-oriented workflows MUST be documented in `guides/user` (`UG-*`).
Developer architecture guides MUST be documented in `guides/developer` (`DG-*`).

### `REQ-GUIDE-003` User Workflow Orientation

User guides MUST document end-to-end usage workflows, prerequisites, expected outcomes, and typed failure outcomes where applicable.

### `REQ-GUIDE-004` Developer Architecture Orientation

Developer guides MUST document component boundaries, lifecycle interactions, and contract dependencies.

### `REQ-GUIDE-005` Canonical Reference Integrity

Every guide MUST reference canonical sources under `specs/` and MUST avoid introducing contradictory behavioral claims.

### `REQ-GUIDE-006` Diagram Format Rule (Mermaid)

When a guide requires a diagram for understanding (`Diagram Required: yes`), the primary diagram MUST be authored as a Mermaid fenced block (` ```mermaid `).

### `REQ-GUIDE-007` Diagram Presence Rule

Guides marked `Diagram Required: yes` MUST include at least one Mermaid diagram in the same document.

### `REQ-GUIDE-008` Traceable Governance Mapping

Every guide MUST map to at least one `REQ-*` family and one scenario identifier (`SCN-*` and/or `GSCN-*`).

### `REQ-GUIDE-009` Review Freshness

`Last Reviewed` MUST be present and in `YYYY-MM-DD` format.

### `REQ-GUIDE-010` Template Compliance

New guides SHOULD be authored from canonical templates in `guides/templates` to preserve metadata and section consistency.
