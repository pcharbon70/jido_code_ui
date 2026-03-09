# Security Contract

## Requirement Set

- `REQ-SEC-001`: Authentication state MUST be validated at trusted ingress boundaries.
- `REQ-SEC-002`: Authorization decisions MUST be explicit, auditable, and policy-versioned.
- `REQ-SEC-003`: Sensitive fields (prompt fragments, code payloads, tokens) MUST be redacted from logs and telemetry.
- `REQ-SEC-004`: Security-relevant failures MUST fail closed by default.
- `REQ-SEC-005`: Custom DSL node types MUST execute only when explicitly enabled by policy-versioned feature flags; otherwise they MUST be rejected before compile.

## Notes

Primary threat areas for v1:

- forged/malformed widget event envelopes
- unauthorized mutating commands
- unauthorized custom DSL extension execution
- exfiltration via telemetry/log pipelines
