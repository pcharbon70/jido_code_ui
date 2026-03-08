# Guide Conformance Matrix

This matrix maps guide requirements to contracts, guide sets, and validation scenarios.

| Requirement Family | Owning Contract | Primary Guide Sets | Scenario Coverage |
|---|---|---|---|
| `REQ-GUIDE-001`..`REQ-GUIDE-010` | [guide_contract.md](../contracts/guide_contract.md) | all `UG-*` and `DG-*` guides | `GSCN-001`, `GSCN-002`, `GSCN-006`, `GSCN-008`, `GSCN-009` |
| `REQ-GTRACE-001`..`REQ-GTRACE-006` | [guide_traceability_contract.md](../contracts/guide_traceability_contract.md) | all `UG-*` and `DG-*` guides | `GSCN-003`, `GSCN-004`, `GSCN-005`, `GSCN-007`, `GSCN-010` |

## Guide Coverage Matrix

| Guide Path | Guide ID | Audience | Requirement Families | Scenario Coverage |
|---|---|---|---|---|
| `guides/user/UG-0001-getting-started.md` | `UG-0001` | `User` | `REQ-GUIDE-*`, `REQ-GTRACE-*`, `REQ-SVC-*`, `REQ-SEC-*`, `REQ-OBS-*` | `SCN-002`, `SCN-003`, `SCN-004`, `SCN-005`, `SCN-006`, `GSCN-001`, `GSCN-003`, `GSCN-004`, `GSCN-005`, `GSCN-007` |
| `guides/developer/DG-0001-runtime-topology-and-control-planes.md` | `DG-0001` | `Developer` | `REQ-GUIDE-*`, `REQ-GTRACE-*`, `REQ-CP-*`, `REQ-SVC-*`, `REQ-OBS-*`, `REQ-DATA-*` | `SCN-001`, `SCN-003`, `SCN-004`, `SCN-005`, `SCN-008`, `GSCN-001`, `GSCN-006`, `GSCN-007` |
