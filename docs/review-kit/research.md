# Review Kit Research Note – gpt-5-codex

- Samples to validate: repo currently lacks `samples/` or `contracts/`; plan to seed a tiny `samples/` tree with representative YAML/JSON fixtures for validation. 【4ebfe1†L2-L3】
- hhfab availability: assume optional local install; workflows will support local binaries when present and fall back to containerized strict runs for determinism. 【a87040†L1-L36】
- Container image: TODO to pin official hhfab validator image (placeholder `ghcr.io/example/hhfab@sha256:TODO` until registry provides digest). 【a87040†L31-L36】
- Minimal CI matrix: start with two high-signal fixtures (`samples/topology-min.yaml`, `samples/contract-min.json`) covering topology + contract parsing once added. 【4ebfe1†L2-L3】
- Network needs: validator expected to work fully offline; strict mode will enforce `--network=none` in container runs. 【a87040†L31-L36】
- Outputs: continue emitting compact `.artifacts/review-kit/summary.json` capturing mode, status, counts, and duration for CI surfaces. 【c455f0†L1-L1】【a87040†L9-L24】
- Local workflows: maintain existing smoke script for quick checks while introducing `hhfab-validate.sh` as the real entry point. 【ce7f03†L1-L8】
- CI guardrails: reuse pinned action pattern established previously and expand composite action to enforce digest pinning, read-only mounts, and rootless execution. 【ce7f03†L1-L8】【a87040†L24-L30】
- Next steps: add validator script, extend composite for strict container mode, wire review-kit workflow matrix/jobs, create hhfab-sensitive labeler, and document run instructions. 【a87040†L24-L36】

- Artifact handling: keep summaries under `.artifacts/review-kit/` so composite output wiring stays stable across jobs. 【a87040†L9-L24】
