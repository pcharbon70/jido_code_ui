# jido_code_ui

Elixir service scaffold with:

- Specs governance system (`specs/`)
- RFC governance + intake system (`rfcs/`)
- Conformance and release-readiness gates (`scripts/`, `.github/workflows/`)

## Core Commands

```bash
# Specs governance
./scripts/validate_specs_governance.sh

# RFC governance
./scripts/validate_rfc_governance.sh

# Conformance
./scripts/run_conformance.sh
./scripts/run_conformance.sh --report-only

# Release-readiness
./scripts/run_release_readiness.sh
./scripts/run_release_readiness.sh --report-only
```

Make aliases:

```bash
make conformance
make conformance-report
make rfc-governance
make rfc-governance-debt-scan
make release-readiness
make release-readiness-report
```

## RFC-to-Spec Workflow

```bash
# Validate an RFC
./scripts/validate_rfc_governance.sh

# Preview generated spec stubs from RFC plan rows
./scripts/gen_specs_from_rfc.sh --rfc rfcs/RFC-0001-rfc-governance-and-spec-intake.md --dry-run

# Generate stubs
make rfc-specs-generate RFC=rfcs/RFC-0001-rfc-governance-and-spec-intake.md
```
