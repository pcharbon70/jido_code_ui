# Control Plane Ownership Matrix

## Requirement Set

- `REQ-CP-001`: Every covered module MUST map to exactly one primary control plane.
- `REQ-CP-002`: Ownership conflicts across docs MUST resolve in favor of this matrix and ADR-0001.
- `REQ-CP-003`: Transport modules MUST NOT become domain-state authorities.
- `REQ-CP-004`: Ownership changes MUST update this matrix in the same change set.
- `REQ-CP-005`: New runtime modules MUST be assigned before merge.

## Ownership Matrix

| Runtime Module | Primary Plane | Notes |
|---|---|---|
| `TODO.Module` | `TODO` | `TODO` |

## ADR References

- [../adr/ADR-0001-control-plane-authority.md](../adr/ADR-0001-control-plane-authority.md)
