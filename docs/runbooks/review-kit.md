# Review Kit Runbook

Operational guide for the `review-kit` workflow: smoke-local (best-effort) and strict (digest-pinned) validation.

## Quick Reference

- **Workflow:** `.github/workflows/review-kit.yml`
- **Container:** `ghcr.io/afewell-hh/hoss/hhfab@sha256:...`
- **Minimum hhfab:** `v0.4.0`
- **Warning budget:** `0` (strict enforcement)

## Rotating the hhfab Digest

When a new hhfab release is available or security patches require a rebuild:

```bash
# 1. Build and push new image
docker build -f Dockerfile.tools.hhfab -t ghcr.io/afewell-hh/hoss/hhfab:latest .
docker push ghcr.io/afewell-hh/hoss/hhfab:latest

# 2. Capture the digest
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/afewell-hh/hoss/hhfab:latest)
echo "New digest: $DIGEST"

# 3. Update repository variable
gh api -X PATCH "/repos/afewell-hh/hoss/actions/variables/HHFAB_IMAGE_DIGEST" \
  -f value="$DIGEST"

# 4. Verify with a test run
gh workflow run review-kit.yml --ref main
gh run list --workflow review-kit.yml --limit 1
gh run view --log
```

**Verification checklist:**
- [ ] Summary JSON shows `status: "ok"`
- [ ] `image.digest` matches new `$DIGEST`
- [ ] `hhfab.version` meets minimum (≥ v0.4.0)
- [ ] `counts.warnings` == 0
- [ ] All enforcement gates pass

## Failure Triage

### 1. Get the Summary Artifact

```bash
# List recent runs
gh run list --workflow review-kit.yml --limit 5

# Download summary from a specific run
gh run view <RUN_ID> --log | grep '{"status"' | head -1

# Or download the artifact (if upload succeeded)
#   smoke-local artifact: review-kit-summary-<RUN_ID>-<ATTEMPT>.json
RUN_ID=<RUN_ID>
RUN_ATTEMPT=<ATTEMPT>
gh run download "$RUN_ID" --name "review-kit-summary-${RUN_ID}-${RUN_ATTEMPT}"
#   strict artifact: review-kit-summary-strict.json
gh run download <RUN_ID> --name review-kit-summary-strict.json
```

### 2. Common Failure Causes

| Error | Cause | Fix |
|-------|-------|-----|
| `manifest unknown` | GHCR authentication failed or package is private | Check `GHCR_TOKEN` secret; verify package linked to repo |
| `read-only file system` | hhfab cache not configured | Ensure `HHFAB_CACHE_DIR=/tmp/.hhfab-cache` |
| `status: "error"` | hhfab validation failed | Check `.artifacts/review-kit/hhfab-validate.log` in container |
| `warnings exceed budget` | New warnings introduced | Review `summary.warnings` and update code |
| `version below minimum` | Old hhfab binary | Rotate digest to newer hhfab version |
| `empty matrix` | No targets in matrix.txt | Add valid sample files to `.github/review-kit/matrix.txt` |

### 3. Re-running Failed Jobs

```bash
# Re-run just the failed jobs
gh run rerun <RUN_ID> --failed

# Re-run the entire workflow
gh run rerun <RUN_ID>

# Trigger fresh run (workflow_dispatch)
gh workflow run review-kit.yml --ref <BRANCH>
```

### 4. Debugging Locally

Reproduce strict validation without GitHub Actions:

```bash
# Set the digest variable
export HHFAB_IMAGE_DIGEST="ghcr.io/afewell-hh/hoss/hhfab@sha256:..."

# Run the exact container command
docker run --rm \
  --network=none \
  --user "$(id -u):$(id -g)" \
  --security-opt=no-new-privileges \
  --read-only \
  --tmpfs /tmp:rw \
  -e TMPDIR=/tmp \
  -e HHFAB_CACHE_DIR=/tmp/.hhfab-cache \
  -e HHFAB_MATRIX="$(cat .github/review-kit/matrix.txt)" \
  -v "$PWD:/workspace:ro" \
  -v "$PWD/.artifacts:/workspace/.artifacts" \
  -w /workspace \
  "$HHFAB_IMAGE_DIGEST" \
  'set -Eeuo pipefail; scripts/hhfab-validate.sh'

# Check the summary
cat .artifacts/review-kit/summary-smoke-latest.json | jq .

# Strict runs write: summary-strict-<RUN>.json (latest pointer: summary-strict-latest.json)
```

## Minimum hhfab Version Policy

**Current minimum:** `v0.4.0`

**Enforcement:** `.github/workflows/review-kit.yml:220-239` (Enforce hhfab minimum version step)

**Updating the minimum:**
1. Update `HHFAB_MIN_SEMVER` in the workflow
2. Rotate digest to ensure new minimum is met
3. Document the change in release notes

**Compatibility matrix:**
| hhfab Version | Status | Notes |
|---------------|--------|-------|
| v0.41.3+ | ✅ Current | Canonical installer from i.hhdev.io |
| v0.4.0-v0.41.2 | ✅ Supported | Meets minimum requirement |
| < v0.4.0 | ❌ Rejected | Fails version gate |

## Branch Protection Configuration

**Required status checks:**
- `smoke-local` (best-effort, informational)
- `review-kit (strict)` (blocking)
- `actionlint` (blocking)

**Updating branch protection:**

```bash
# View current protection
gh api "/repos/afewell-hh/hoss/branches/main/protection" | jq .

# Add/update required checks via web UI:
# Settings → Branches → main → Edit
# Or via API (requires admin token):
gh api -X PUT "/repos/afewell-hh/hoss/branches/main/protection/required_status_checks" \
  -f contexts[]='smoke-local' \
  -f contexts[]='review-kit (strict)' \
  -f contexts[]='actionlint' \
  -f strict=true
```

**Optional protections:**
- ✅ Dismiss stale approvals on new commits
- ✅ Require linear history (no merge commits)
- ⚠️ Enforce for administrators (use cautiously)

## Nightly Run Failures

Nightly runs (cron: `17 3 * * *`) validate against the latest changes on a schedule.

**If nightly fails:**
1. Check for upstream hhfab regressions
2. Verify sample files are still valid
3. Review recent commits for accidental changes to sensitive paths:
   - `samples/**`
   - `contracts/**`
   - `.github/review-kit/**`
   - `scripts/hhfab-*.sh`

**Auto-issue creation:**
Future enhancement: nightly failures will auto-create GitHub issues with summary artifacts attached.

## Matrix Management

**Matrix file:** `.github/review-kit/matrix.txt`

**Adding targets:**
```bash
# Add a new sample file
echo "samples/new-topology.yaml" >> .github/review-kit/matrix.txt

# Validate locally before committing
HHFAB_MATRIX="$(cat .github/review-kit/matrix.txt)" bash scripts/hhfab-validate.sh
```

**Target requirements:**
- Must be valid YAML/JSON files
- Must pass hhfab validation (if `fab.yaml` present)
- Must not be in `samples/invalid/` (those are for negative tests)

Note: Comment lines starting with `#` and blank lines are ignored when computing the HHFAB_MATRIX count and matrix list.

**Removing invalid targets:**
If a sample becomes invalid, either fix it or remove it from the matrix. The strict job will fail if any target is invalid.

## Security Hardening

The strict job runs with maximum isolation:

- `--network=none` (no network access)
- `--read-only` (immutable filesystem)
- `--security-opt=no-new-privileges` (no privilege escalation)
- `--user "$(id -u):$(id -g)"` (non-root)
- `--tmpfs /tmp:rw` (writable temp only)

**Container provenance (optional):**
Add cosign verification before running:
```yaml
- name: Verify container signature
  run: |
    cosign verify --certificate-identity-regexp '.*' \
      --certificate-oidc-issuer-regexp '.*' \
      ${{ env.HHFAB_IMAGE_DIGEST }}
```

## Escalation

**For blocking issues:**
1. Check #infrastructure or #ci-cd Slack channels
2. Create issue with `ci-failure` label
3. Tag @ci-owners for urgent review

**For non-blocking issues:**
1. Create issue with `enhancement` or `documentation` label
2. Submit PR with proposed fix
3. Request review from recent contributors

## References

- [GitHub Actions Workflow Syntax](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [GHCR Authentication](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry)
- [Digest Pinning Best Practices](https://docs.docker.com/engine/reference/commandline/pull/#pull-an-image-by-digest-immutable-identifier)
