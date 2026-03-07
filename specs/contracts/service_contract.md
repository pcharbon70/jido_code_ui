# Service Contract

## Requirement Set

- `REQ-SVC-001`: Runtime modules MUST expose explicit responsibilities and stable API surfaces.
- `REQ-SVC-002`: Ingress/egress operations MUST preserve correlation continuity.
- `REQ-SVC-003`: Ingress payloads MUST be validated before dispatch.
- `REQ-SVC-004`: Runtime failures MUST return typed errors.
- `REQ-SVC-005`: Service operations MUST emit required observability events.

## Key Types

```text
RuntimeContext { correlation_id: string, request_id: string, ... }
TypedError { error_code: string, category: string, retryable: boolean, details?: map }
```

## ADR References

- [../adr/ADR-0001-control-plane-authority.md](../adr/ADR-0001-control-plane-authority.md)
