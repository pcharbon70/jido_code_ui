# Observability Contract

## Requirement Set

- `REQ-OBS-001`: Runtime operations MUST emit structured events for success and failure paths.
- `REQ-OBS-002`: Events MUST include join keys (`correlation_id`, `request_id`) where applicable.
- `REQ-OBS-003`: Error events MUST carry typed error metadata.
- `REQ-OBS-004`: Metrics families MUST cover latency, throughput, and failures.
- `REQ-OBS-005`: Observability schemas MUST be versioned.

## Required Event Families

- `runtime.operation.started.v1`
- `runtime.operation.completed.v1`
- `runtime.operation.failed.v1`
