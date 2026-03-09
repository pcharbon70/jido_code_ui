# Scenario Catalog

Canonical validation scenarios for the `unified-ui DSL -> unified-iur -> web-ui` runtime pipeline.

| Scenario ID | Name | Summary |
|---|---|---|
| `SCN-001` | Control-plane ownership consistency | Runtime modules map to one canonical plane without conflicts. |
| `SCN-002` | Ingress validation behavior | Malformed event/command envelopes fail closed before orchestration. |
| `SCN-003` | Correlation continuity | `correlation_id`/`request_id` persist across compile, session, and render flows. |
| `SCN-004` | Typed error normalization | Compile/render/session failures return normalized typed errors. |
| `SCN-005` | Observability minimum baseline | Required compile/render telemetry families are emitted. |
| `SCN-006` | Authorization enforcement | Unauthorized mutating commands are denied with auditable outcomes. |
| `SCN-007` | Sensitive data redaction | Telemetry/log outputs do not leak sensitive prompt/code/token fields. |
| `SCN-008` | DSL/IUR schema compatibility | Versioned DSL and IUR payloads satisfy validation rules, including feature-flag policy for custom nodes. |
