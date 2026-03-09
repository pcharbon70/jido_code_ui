# Targets

## Product/Runtime Targets

| Target | Description | Measurement |
|---|---|---|
| `TGT-001` | Deterministic, server-authoritative DSL->IUR compile parity for identical inputs. | 100% hash parity in deterministic compile test suite. |
| `TGT-002` | Interactive compile performance for standard coding-interface views. | P95 compile latency <= 60ms for baseline view payload size. |
| `TGT-003` | End-to-end render responsiveness after accepted command/event. | P95 command-to-render latency <= 120ms (excluding network RTT). |
| `TGT-004` | Typed failure diagnosability across pipeline stages. | 100% failures include `correlation_id`, `request_id`, and stage code. |
| `TGT-005` | Governance traceability for architecture and acceptance changes. | No governance validator failures in CI release gates. |
| `TGT-006` | Session runtime behavior is correct with in-memory-only snapshots in v1. | Deterministic replay tests pass without external persistence dependency. |

## Non-Targets

- Reproducing the exact business logic behavior of other internal apps.
- Supporting arbitrary unversioned DSL node extensions in v1.
- Persisting session snapshots to external storage in v1.
- Solving offline-first synchronization in the initial release.
