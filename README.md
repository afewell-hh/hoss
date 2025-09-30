# hoss

[![review-kit](../../actions/workflows/review-kit.yml/badge.svg)](../../actions/workflows/review-kit.yml)

## Review Kit

Run the validator locally (falls back to strict container in CI):

```bash
MATRIX=$'samples/topology-min.yaml\nsamples/contract-min.json' bash scripts/hhfab-validate.sh || echo "local fallback"
```

The `review-kit` workflow executes two jobs:

- `smoke-local` reuses any available `hhfab` binary on the runner, emits `.artifacts/review-kit/summary.json`, and is allowed to fail without blocking CI. 【F:.github/workflows/review-kit.yml†L23-L43】【F:scripts/hhfab-validate.sh†L1-L61】
- `strict` launches the validator inside a digest-pinned, no-network, read-only container and uploads the summary artifact for reviewers. 【F:.github/workflows/review-kit.yml†L44-L70】【F:.github/actions/hhfab-validate/action.yml†L1-L79】

Sample fixtures live under `samples/` and are included in the default matrix for both jobs. 【F:samples/topology-min.yaml†L1-L5】【F:samples/contract-min.json†L1-L5】
