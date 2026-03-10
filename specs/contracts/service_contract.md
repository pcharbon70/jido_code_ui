# Service Contract

## Requirement Set

- `REQ-SVC-001`: Runtime modules MUST expose explicit responsibilities and stable API surfaces.
- `REQ-SVC-002`: Ingress/egress operations MUST preserve `correlation_id` and `request_id` continuity.
- `REQ-SVC-003`: DSL commands/events MUST be validated before dispatch and compilation.
- `REQ-SVC-004`: Runtime failures MUST return typed errors that include pipeline stage metadata.
- `REQ-SVC-005`: DSL->IUR compilation MUST be deterministic and server-authoritative for identical input, schema version, and compile profile.

## Key Types

```text
UiCommand {
  command_type: string,
  session_id: string,
  correlation_id: string,
  request_id: string,
  payload: map
}

CompileResult {
  compile_authority: string,
  dsl_version: string,
  iur_version: string,
  iur_document: map,
  iur_hash: string,
  diagnostics: list
}

RenderResult {
  rendered: boolean,
  projection: map,
  continuity: map,
  event_projection: map,
  render_metadata: map
}

OrchestratorResult {
  status: atom,
  route_key: string,
  stage_trace: list,
  envelope_kind: atom,
  continuity: map,
  policy: map,
  compile: CompileResult,
  session: map,
  render: RenderResult
}

TypedError {
  error_code: string,
  category: string,
  stage: string,
  retryable: boolean,
  details?: map
}
```

`CompileResult.compile_authority` MUST be `server` in v1.

## ADR References

- [../adr/ADR-0001-control-plane-authority.md](../adr/ADR-0001-control-plane-authority.md)
- [../adr/ADR-0002-typed-runtime-result-contracts.md](../adr/ADR-0002-typed-runtime-result-contracts.md)
