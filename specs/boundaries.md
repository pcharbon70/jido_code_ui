# Boundaries

## Inbound Boundaries

- Browser/widget interaction events from `web-ui` into ingress transport.
- Session commands from coding-assistance workflows into orchestration.
- DSL authoring payloads entering compile workflows.

## Outbound Boundaries

- Render payloads exported to `web-ui` adapters.
- Typed operation outcomes returned to calling runtime surfaces.
- Structured telemetry/events emitted to observability sinks.
- Session snapshots are retained in-memory for v1 and are not emitted to external persistence stores.

## Trust/Failure Boundaries

- Authentication and request envelope trust are established at ingress.
- Authorization trust is enforced in orchestration before mutating operations.
- Custom DSL node execution trust is enforced through feature-flag policy allowlists.
- Compile and render failures MUST produce typed errors; no untyped failure leakage.
- Sensitive prompt/code payloads MUST be redacted before logging/telemetry emission.
