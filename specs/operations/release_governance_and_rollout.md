# Release Governance And Rollout

## Purpose

Define release gates tied to contracts, conformance, and ADR updates.

## Release Gates

1. Contract deltas reviewed and traceability updated.
2. Conformance matrix/scenarios aligned.
3. ADR updates included for baseline authority shifts.
4. Governance validators, conformance harness, and release-readiness gate all pass in deterministic mode.

## Rollout Checklist

- Run `./scripts/run_governance_gates.sh` and confirm specs/guides/RFC governance checks pass.
- Run `./scripts/run_conformance.sh --report-only --skip-governance` and confirm `CONFORMANCE_ALIGNMENT=PASS`.
- Run `./scripts/check_release_gate_regressions.sh` and confirm required scripts, hooks, and workflows are present.
- Run `./scripts/run_release_readiness.sh --report-only` and confirm all stage markers emit `:pass` or expected skip states plus `RELEASE_GATE_RESULT=PASS`.
- When contract, conformance, or control-plane baseline docs change, include an ADR update in the same change set.
