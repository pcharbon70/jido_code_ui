# Guide Scenario Catalog

Canonical validation scenarios for guide-governance compliance.

| Scenario ID | Name | Summary |
|---|---|---|
| `GSCN-001` | Metadata completeness | Guide includes all required machine-readable metadata fields. |
| `GSCN-002` | Audience and path parity | `UG-*` guides live under `guides/user`, `DG-*` guides live under `guides/developer`. |
| `GSCN-003` | Spec traceability | Guide references one or more canonical `specs/*.md` sources. |
| `GSCN-004` | Requirement traceability | Guide maps to at least one valid `REQ-*` family. |
| `GSCN-005` | Scenario traceability | Guide maps to at least one valid scenario id (`SCN-*` or `GSCN-*`). |
| `GSCN-006` | Mermaid-required diagram compliance | `Diagram Required: yes` guides include at least one Mermaid diagram block. |
| `GSCN-007` | Conformance matrix row coverage | Every guide has a corresponding row in guide conformance matrix. |
| `GSCN-008` | Template policy compliance | User/developer templates include required metadata and Mermaid diagram section. |
| `GSCN-009` | Review date format validity | `Last Reviewed` values follow `YYYY-MM-DD`. |
| `GSCN-010` | Matrix reference integrity | Matrix REQ/SCN references resolve against known requirement and scenario catalogs. |
