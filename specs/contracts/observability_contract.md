# Observability Contract

## Requirement Set

- `REQ-OBS-001`: Runtime operations MUST emit structured events for success and failure paths.
- `REQ-OBS-002`: Events MUST include join keys (`correlation_id`, `request_id`, `session_id`) where applicable.
- `REQ-OBS-003`: Error events MUST carry typed error metadata and pipeline stage.
- `REQ-OBS-004`: Metrics families MUST cover compile latency, render latency, throughput, and failures.
- `REQ-OBS-005`: Observability schemas MUST be versioned.

## Required Event Families

- `ui.command.received.v1`
- `ui.policy.denied.v1`
- `ui.dsl.compile.started.v1`
- `ui.dsl.compile.completed.v1`
- `ui.dsl.compile.failed.v1`
- `ui.iur.render.started.v1`
- `ui.iur.render.completed.v1`
- `ui.iur.render.failed.v1`
