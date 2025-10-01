# Prep Research Dossier – gpt-5-codex (prep-research)

## Scope view
- Repository root currently only contains `.gitignore` and `README.md`; there are no source, workflow, or script directories present. 【F:.gitignore†L1-L21】【18e456†L1-L2】
- No `.github/` directory exists yet, so there are no workflows, composite actions, or problem matchers checked into the repo. 【0bda2f†L1-L2】
- Attempting to invoke the expected smoke helper under `scripts/` fails because the directory (and script) has not been created. 【9f4286†L1-L2】

## Inputs / Outputs
- Because the `.github/workflows` tree is absent, there are no declared workflow inputs, environment variables, or artifacts defined for validator runs today. 【0bda2f†L1-L2】
- The missing `scripts/hhfab-smoke.sh` helper means there is currently no local entry point that would emit JSON summaries or other artifacts for smoke validation. 【9f4286†L1-L2】

## Local runs
- `actionlint -color never` exits with `command not found`, confirming the validator tool is not yet installed in the environment; no workflow syntax could be checked locally. 【9fe699†L1-L2】
- Running `bash scripts/hhfab-smoke.sh || true` reports `No such file or directory`, so the smoke harness is not available for dry-runs. 【9f4286†L1-L2】

## CI guardrails & gaps
- With no `.github/workflows` defined, there are currently no pinned GitHub Actions, container digest enforcement, or rootless/RO job settings in place. 【0bda2f†L1-L2】
- The absence of the smoke script also means there is no local enforcement of no-network, digest-pinned containers, or other guardrails described in HH FAB standards. 【9f4286†L1-L2】

## Minimal change plan (pending implementation phase)
1. `feat: bootstrap hhfab validator action` – add `.github/actions/hhfab-validate/action.yml` implementing the composite action expected by the workflows. 【0bda2f†L1-L2】
2. `ci: add review-kit workflow scaffolding` – introduce `.github/workflows/review-kit.yml` (and related jobs) with pinned action SHAs and strict container flags. 【0bda2f†L1-L2】
3. `ci: add smoke validation script` – create `scripts/hhfab-smoke.sh` to run validators locally with documented outputs. 【9f4286†L1-L2】

## Risks / Open questions
- Required validator behavior, environment variables, and artifact formats remain unspecified because no prior implementation exists in the repo; additional product guidance is needed. 【18e456†L1-L2】
- Local tooling such as `actionlint` is not installed in the container image, so we will need to vendor a binary or document installation steps before running checks. 【9fe699†L1-L2】
- Without existing workflows, we have no examples of the expected problem matcher wiring or summary outputs to match, increasing the risk of mismatched formatting. 【0bda2f†L1-L2】
