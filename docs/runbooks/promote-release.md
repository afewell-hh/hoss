# Promote Release Runbook

Operational guide for the `promote-release` workflow: safe, immutable, server-side promotion of digest-pinned images to semantic versioned tags.

## Quick Reference

- **Workflow:** `.github/workflows/promote-release.yml`
- **Default Image:** `ghcr.io/afewell-hh/hoss/hhfab`
- **Tag Policy:** `vX.Y.Z`, `stable`, or `latest` (SemVer enforced)
- **Approval Required:** Yes (protected `production` environment)
- **Immutability:** Enforced (cannot overwrite existing tags)

## When to Use

Promote a **verified, digest-pinned image** to a **semantic version tag** when:

- You've completed testing on a specific digest (from CI/nightly builds)
- You want to make a release available to downstream consumers
- You need a stable, human-readable reference (e.g., `v1.2.3`) instead of `sha256:abc123...`

**Do not use this workflow for:**
- Building new images (use `publish-hhfab.yml` or `digest-rotate.yml` instead)
- Hotfixes or patches (create a new build with the fix first, then promote)
- Experimental/testing tags (unless using `allow_non_semver: true`)

## Inputs

| Input | Required | Description | Example |
|-------|----------|-------------|---------|
| `image` | Yes | OCI repository path | `ghcr.io/afewell-hh/hoss/hhfab` |
| `digest` | Yes | SHA256 digest (64 hex chars, **no** `sha256:` prefix) | `a1b2c3d4e5f6...` |
| `tag` | Yes | Target tag (must match SemVer policy) | `v1.0.0`, `stable`, `latest` |
| `allow_non_semver` | No | Bypass SemVer policy (emergency use only) | `true` or `false` (default: `false`) |

### Digest Format

**Correct:** `a1b2c3d4e5f6789012345678901234567890abcdef1234567890abcdef123456` (64 hex chars)
**Incorrect:** `sha256:a1b2c3d4...` (prefixed - will fail validation)

To extract digest from a full reference:
```bash
# From full reference
FULL_REF="ghcr.io/afewell-hh/hoss/hhfab@sha256:a1b2c3d4..."
DIGEST64=$(echo "$FULL_REF" | sed 's|^.*@sha256:||')
echo "$DIGEST64"
```

## Tag Policy

### Allowed Patterns (Default)

- **Semantic Versioning:** `v1.2.3`, `v1.0.0-rc.1`, `v2.3.4-beta.2`
- **Stable Channels:** `stable`, `latest`

### Disallowed Patterns (Unless Opted-Out)

- Custom tags: `my-feature`, `test`, `prod-candidate`
- Non-semantic versions: `v1.2`, `1.0.0` (missing `v` prefix or patch version)
- Arbitrary strings: `release-2024`, `hotfix-friday`

### Bypassing the Policy

For emergency situations requiring non-SemVer tags:

```bash
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$DIGEST64" \
  -f tag=emergency-hotfix-2024-01-15 \
  -f allow_non_semver=true
```

**IMPORTANT:** Document the bypass in an issue with `release` and `non-semver` labels. Include:
- Reason for bypass
- Workflow run URL
- Plan to migrate to proper SemVer tag

## Workflow Stages

### 1. Preflight Validation (Fast-Fail)

Runs **before** environment approval to catch errors early.

**Checks performed:**
- ✅ Input regex validation (digest: 64 hex, image: `ghcr.io/owner/name`, tag: alphanumeric)
- ✅ Tag policy enforcement (SemVer or opt-out)
- ✅ Tag immutability (fails if tag already exists in registry)
- ✅ Source digest reachability (verifies digest exists)

**Expected duration:** ~30 seconds

**Common failures:**
| Error | Cause | Fix |
|-------|-------|-----|
| `Digest must be 64 hex characters` | Digest includes `sha256:` prefix | Remove prefix, use only the 64 hex chars |
| `Image must be ghcr.io/<owner>/<name>` | Incorrect registry or format | Use full GHCR path |
| `Tag contains invalid characters` | Special chars in tag | Use only alphanumeric, dots, dashes, underscores |
| `Tag does not match required patterns` | Non-SemVer tag | Use `vX.Y.Z` or set `allow_non_semver: true` |
| `Tag already exists` | Attempting to overwrite | Use a different tag (immutability enforced) |
| `Source digest not found` | Digest doesn't exist in registry | Verify digest is correct and pushed to GHCR |

### 2. Approval Gate

After preflight passes, the workflow waits for manual approval via the **production** environment.

**Who can approve:**
- Repository admins
- Users listed in the `production` environment reviewers

**What to verify before approving:**
1. Check the preflight summary in the workflow run
2. Confirm the digest is from a trusted build (review-kit passed, signed)
3. Verify the tag follows your release process
4. Ensure release notes are ready (if applicable)

**Expected duration:** Variable (depends on approver availability)

### 3. Promote and Sign

Runs **after** approval is granted.

**Operations performed:**
1. **Server-side promotion:** `docker buildx imagetools create --tag <dst> <src>`
   - No local pull/push (fast, efficient)
   - Preserves multi-arch manifest
   - Atomic operation
2. **Keyless cosign signing:** Signs the promoted tag with GitHub Actions OIDC identity
3. **Double verification:** Verifies signatures on both tag **and** digest references
4. **Post-promotion sanity check:** Runs offline smoke test (`hhfab version`) inside the promoted image
5. **GitHub Release creation:** Auto-creates/updates release with verification instructions

**Expected duration:** ~1-2 minutes

**Common failures:**
| Error | Cause | Fix |
|-------|-------|-----|
| `manifest unknown` | GHCR authentication failed | Check `GITHUB_TOKEN` permissions |
| `cosign sign failed` | OIDC token issue | Re-run workflow (transient issue) |
| `cosign verify failed` | Image not signed or invalid cert | Verify source digest was signed by publish workflow |
| `Sanity check failed` | Promoted image is broken | Investigate source digest; rollback if needed |
| `gh release create failed` | Tag already has release | Expected behavior; release will be updated instead |

## Standard Promotion Workflow

### Step 1: Collect Digest

```bash
# Use the digest collection script
./scripts/collect-digests.sh --json-out .artifacts/digests.json

# Extract the digest for the image you want to promote
DIGEST64=$(jq -r '.engine // .runtime // .hhfab' .artifacts/digests.json | sed 's|^.*@sha256:||')

# Verify digest is valid (should be 64 hex chars)
echo "$DIGEST64" | grep -E '^[0-9a-f]{64}$' && echo "Valid" || echo "Invalid"
```

### Step 2: Trigger Promotion

```bash
# Promote to a semantic version
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$DIGEST64" \
  -f tag=v1.0.0

# Monitor the run
gh run list --workflow=promote-release.yml --limit 1
```

### Step 3: Approve in GitHub UI

1. Navigate to the workflow run in GitHub Actions
2. Review preflight checks (should be ✅ green)
3. Click "Review deployments" → "production" → "Approve and deploy"

### Step 4: Verify Release

```bash
# Wait for promotion to complete
gh run watch

# Verify the tag exists
docker buildx imagetools inspect ghcr.io/afewell-hh/hoss/hhfab:v1.0.0

# Verify cosign signature
cosign verify ghcr.io/afewell-hh/hoss/hhfab:v1.0.0 \
  --certificate-identity-regexp="^https://github.com/.+/.+@" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com

# Pull and test locally
docker pull ghcr.io/afewell-hh/hoss/hhfab:v1.0.0
docker run --rm ghcr.io/afewell-hh/hoss/hhfab:v1.0.0 hhfab version
```

### Step 5: Update Downstream References

```bash
# Update the review-kit workflow to use the new tag (if desired)
gh api -X PATCH repos/afewell-hh/hoss/actions/variables/HHFAB_IMAGE_DIGEST \
  -f value="$(docker buildx imagetools inspect ghcr.io/afewell-hh/hoss/hhfab:v1.0.0 --format '{{.Name}}@{{.Digest}}')"

# Trigger review-kit to verify the update
gh workflow run review-kit.yml --ref main
```

## Rollback Procedures

### Scenario 1: Promoted Wrong Digest

**Problem:** Promoted a digest that later failed downstream tests.

**Solution:** Promote a new tag with the correct digest (old tag remains immutable).

```bash
# Find the last known good digest
LAST_GOOD_DIGEST="abc123def456..."

# Promote to a new patch version
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$LAST_GOOD_DIGEST" \
  -f tag=v1.0.1  # Increment patch version
```

### Scenario 2: Need to Rollback Deployment

**Problem:** Deployed `v1.0.0` tag is causing issues in production.

**Solution:** Deploy previous stable tag or create a new hotfix tag.

```bash
# Option A: Deploy previous tag (if still available)
kubectl set image deployment/myapp container=ghcr.io/afewell-hh/hoss/hhfab:v0.9.9

# Option B: Promote last-good digest to a new tag
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$LAST_GOOD_DIGEST" \
  -f tag=v1.0.1-hotfix.1
```

### Scenario 3: Tag Immutability Conflict

**Problem:** Accidentally tried to promote to an existing tag.

**Solution:** Preflight will fail with "Tag already exists" error. Use a different tag.

```bash
# If you intended to update the tag, you CANNOT (by design)
# Instead, create a new version
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$NEW_DIGEST" \
  -f tag=v1.0.1  # Increment version
```

**To forcibly replace a tag (NOT RECOMMENDED):**

1. Delete the existing tag from GHCR (manual operation)
2. Delete the GitHub Release (if auto-created)
3. Re-run the promotion workflow
4. **Document the override** in an issue with the `release` and `override` labels

## Concurrency & Race Conditions

The workflow enforces concurrency control to prevent racing promotions:

```yaml
concurrency:
  group: promote-release-<image>-<tag>
  cancel-in-progress: false
```

**Behavior:**
- Multiple promotions to the **same tag** are queued (not canceled)
- Second promotion will fail in preflight (tag already exists)
- Multiple promotions to **different tags** run in parallel

**Example:**
```bash
# These will run in parallel (different tags)
gh workflow run promote-release.yml -f tag=v1.0.0 -f digest="$DIGEST1" &
gh workflow run promote-release.yml -f tag=v1.0.1 -f digest="$DIGEST2" &

# These will queue (same tag, second will fail in preflight)
gh workflow run promote-release.yml -f tag=v1.0.0 -f digest="$DIGEST1" &
gh workflow run promote-release.yml -f tag=v1.0.0 -f digest="$DIGEST2" &
```

## Security & Permissions

### Workflow-Level Permissions

**Default:** `permissions: {}` (no permissions at workflow level)

**Preflight job:**
```yaml
permissions:
  contents: read    # Read repo contents (for checkout if needed)
  packages: read    # Read GHCR to check tag/digest existence
```

**Promote job:**
```yaml
permissions:
  contents: write   # Create/update GitHub Releases
  packages: write   # Push promoted tag to GHCR
  id-token: write   # OIDC token for keyless cosign signing
```

### Cosign Verification

All promoted tags are:
1. **Signed** with GitHub Actions OIDC identity (keyless)
2. **Verified** against both tag and digest references
3. **Anchored** to the repository's OIDC issuer/subject

**Verification policy:**
```bash
cosign verify <IMAGE>:<TAG> \
  --certificate-identity-regexp="^https://github.com/.+/.+@" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

**Expected certificate subject pattern:** `https://github.com/afewell-hh/hoss/.github/workflows/promote-release.yml@refs/heads/main`

### Post-Promotion Sanity Check

Before creating the release, the workflow runs an offline smoke test:

```bash
docker run --rm \
  --network=none \
  --read-only \
  --tmpfs /tmp:rw \
  -e TMPDIR=/tmp \
  <IMAGE>:<TAG> sh -lc 'hhfab version'
```

**Isolation guarantees:**
- No network access (`--network=none`)
- Immutable filesystem (`--read-only`)
- Minimal writable temp (`--tmpfs /tmp:rw`)

**Failure conditions:**
- Binary not found or not executable
- Version command exits non-zero
- No output produced

## GitHub Release Notes

Auto-generated release notes include:

### 1. Release Information
- Image reference (tag + digest)
- Workflow run URL (audit trail)

### 2. Manifest Details
- Multi-arch platform support
- Layer digests
- Total size
- *(Collapsed by default for readability)*

### 3. Verification Instructions
- Cosign verification command (copy-paste ready)
- Docker pull command

### 4. Deployment Guidance
- Example YAML snippet for Kubernetes/Docker Compose

**Example:**
```markdown
## Release Information

**Image**: `ghcr.io/afewell-hh/hoss/hhfab:v1.0.0`
**Digest**: `sha256:a1b2c3d4...`
**Workflow Run**: [12345678](https://github.com/afewell-hh/hoss/actions/runs/12345678)

### Manifest Details

<details>
<summary>Click to view multi-arch manifest</summary>

```
Name:      ghcr.io/afewell-hh/hoss/hhfab:v1.0.0
MediaType: application/vnd.docker.distribution.manifest.list.v2+json
Digest:    sha256:a1b2c3d4...

Manifests:
  Name:      ghcr.io/afewell-hh/hoss/hhfab@sha256:...
  MediaType: application/vnd.docker.distribution.manifest.v2+json
  Platform:  linux/amd64
...
```

</details>

### Verification

```bash
cosign verify ghcr.io/afewell-hh/hoss/hhfab:v1.0.0
docker pull ghcr.io/afewell-hh/hoss/hhfab:v1.0.0
```
```

## Common Workflows

### Promoting a Nightly Build

```bash
# 1. Find the digest from last successful nightly review-kit run
gh run list --workflow=review-kit.yml --status=success --limit=1
LATEST_RUN=$(gh run list --workflow=review-kit.yml --status=success --limit=1 --json databaseId --jq '.[0].databaseId')

# 2. Extract digest from run logs
gh run view $LATEST_RUN --log | grep "image.digest" | head -1
# Example output: "image.digest": "ghcr.io/afewell-hh/hoss/hhfab@sha256:abc123..."

DIGEST64="abc123def456..."  # Extract the 64 hex chars

# 3. Promote to stable
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$DIGEST64" \
  -f tag=stable
```

### Promoting a Release Candidate

```bash
# Promote to a pre-release tag
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$DIGEST64" \
  -f tag=v2.0.0-rc.1

# After testing, promote to final release
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$DIGEST64" \
  -f tag=v2.0.0
```

### Promoting Multiple Variants

```bash
# Promote different images to coordinated versions
for IMAGE in hhfab runtime engine; do
  DIGEST=$(jq -r ".$IMAGE" .artifacts/digests.json | sed 's|^.*@sha256:||')
  gh workflow run promote-release.yml --ref main \
    -f image="ghcr.io/afewell-hh/hoss/$IMAGE" \
    -f digest="$DIGEST" \
    -f tag=v1.5.0
done
```

## Troubleshooting

### "Invalid digest format" Error

**Symptoms:** Preflight fails with `Digest must be 64 hex characters`

**Cause:** Digest includes `sha256:` prefix or is not 64 characters

**Fix:**
```bash
# Wrong
DIGEST="sha256:abc123..."
# Right
DIGEST="abc123def456..."  # 64 hex chars only

# Extract from full reference
FULL="ghcr.io/afewell-hh/hoss/hhfab@sha256:abc123..."
DIGEST=$(echo "$FULL" | sed 's|^.*@sha256:||')
```

### "Tag policy violation" Error

**Symptoms:** Preflight fails with `Tag does not match required patterns`

**Cause:** Tag is not SemVer, `stable`, or `latest`

**Fix (Option A - Use SemVer):**
```bash
# Wrong
-f tag=my-release

# Right
-f tag=v1.0.0
```

**Fix (Option B - Bypass Policy):**
```bash
gh workflow run promote-release.yml --ref main \
  -f tag=my-custom-tag \
  -f allow_non_semver=true \
  -f ...
```

### "Tag already exists" Error

**Symptoms:** Preflight fails with `Tag already exists: <image>:<tag>`

**Cause:** Attempting to overwrite an existing tag (immutability protection)

**Fix:**
```bash
# Option 1: Use a different tag (recommended)
-f tag=v1.0.1  # Increment version

# Option 2: Delete existing tag from GHCR (not recommended, breaks immutability)
# Requires manual intervention via GHCR UI or API
```

### Approval Stuck/Timeout

**Symptoms:** Workflow waiting for approval indefinitely

**Cause:** No reviewers configured for `production` environment

**Fix:**
1. Go to Settings → Environments → production
2. Add required reviewers
3. Save and re-run the workflow

### Sanity Check Failure

**Symptoms:** Post-promotion sanity check fails with `hhfab version produced no output`

**Cause:** Promoted image is broken or `hhfab` binary is not in PATH

**Fix:**
```bash
# Debug locally
docker run --rm ghcr.io/afewell-hh/hoss/hhfab:v1.0.0 sh -lc 'which hhfab'
docker run --rm ghcr.io/afewell-hh/hoss/hhfab:v1.0.0 sh -lc 'hhfab version'

# If broken, DO NOT use this digest for releases
# Investigate source build and fix
```

## Break-Glass Procedures

### Emergency Non-SemVer Tag

**When to use:** Critical hotfix requiring immediate deployment with custom tag.

```bash
# 1. Promote with bypass flag
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$HOTFIX_DIGEST" \
  -f tag=emergency-hotfix-$(date +%Y%m%d-%H%M) \
  -f allow_non_semver=true

# 2. Document in issue tracker
gh issue create \
  --title "Emergency non-SemVer tag: emergency-hotfix-20240115-1430" \
  --label "release,non-semver,hotfix" \
  --body "$(cat <<EOF
**Reason:** Critical security patch required immediate deployment
**Tag:** emergency-hotfix-20240115-1430
**Digest:** sha256:$HOTFIX_DIGEST
**Workflow Run:** [Link to run]
**Follow-up:** Promote to v1.0.1 after verification
EOF
)"

# 3. Migrate to SemVer ASAP
gh workflow run promote-release.yml --ref main \
  -f digest="$HOTFIX_DIGEST" \
  -f tag=v1.0.1
```

### Bypassing Immutability (Absolute Last Resort)

**⚠️ WARNING:** This breaks the immutability guarantee and should only be used in exceptional circumstances.

**Prerequisites:**
- Must have admin access to GHCR
- Must document in incident report
- Must get approval from security/release team

**Procedure:**
```bash
# 1. Delete the existing tag from GHCR
# (Manual operation via GHCR UI or API)

# 2. Delete the GitHub Release
gh release delete v1.0.0 --yes

# 3. Re-run the promotion
gh workflow run promote-release.yml --ref main \
  -f digest="$NEW_DIGEST" \
  -f tag=v1.0.0

# 4. Create incident report
gh issue create \
  --title "INCIDENT: Tag immutability override for v1.0.0" \
  --label "security,incident,release" \
  --assignee @me \
  --body "$(cat <<EOF
**Date:** $(date -u)
**Tag:** v1.0.0
**Old Digest:** sha256:$OLD_DIGEST
**New Digest:** sha256:$NEW_DIGEST
**Reason:** [REQUIRED - FILL IN]
**Approvers:** [REQUIRED - FILL IN]
**Workflow Run:** [Link to new promotion run]
**Impact Assessment:** [REQUIRED - FILL IN]
**Remediation:** [REQUIRED - FILL IN]
EOF
)"
```

## Automation & Integration

### Post-Promotion CI Trigger

Update the digest variable and trigger review-kit validation:

```bash
# After promotion, update the CI variable
TAG="v1.0.0"
NEW_DIGEST=$(docker buildx imagetools inspect "ghcr.io/afewell-hh/hoss/hhfab:$TAG" --format '{{.Name}}@{{.Digest}}')

gh api -X PATCH repos/afewell-hh/hoss/actions/variables/HHFAB_IMAGE_DIGEST \
  -f value="$NEW_DIGEST"

# Trigger review-kit to validate
gh workflow run review-kit.yml --ref main
```

### Slack/Email Notifications

To add notifications on successful promotions:

```yaml
- name: Notify on success
  if: success()
  run: |
    curl -X POST "${{ secrets.SLACK_WEBHOOK_URL }}" \
      -H 'Content-Type: application/json' \
      -d '{
        "text": "🚀 Release promoted: ${{ inputs.tag }}",
        "blocks": [
          {
            "type": "section",
            "text": {
              "type": "mrkdwn",
              "text": "*Image:* `${{ inputs.image }}:${{ inputs.tag }}`\n*Digest:* `sha256:${{ inputs.digest }}`\n*Release:* <https://github.com/${{ github.repository }}/releases/tag/${{ inputs.tag }}|View Release>"
            }
          }
        ]
      }'
```

## Metrics & Observability

### Key Metrics to Track

- **Promotion frequency:** How often promotions occur
- **Preflight failure rate:** % of promotions failing before approval
- **Approval wait time:** Time between preflight pass and approval
- **End-to-end duration:** Time from trigger to release creation
- **Immutability conflicts:** # of attempts to overwrite existing tags
- **Non-SemVer bypass usage:** # of times `allow_non_semver=true` is used

### Audit Trail

All promotions are auditable via:

1. **Workflow runs:** Complete logs in GitHub Actions
2. **GitHub Releases:** Auto-created releases with metadata
3. **GHCR package history:** Tag creation timestamps
4. **Cosign transparency log:** Public ledger of signatures

Query recent promotions:

```bash
# List recent promotion runs
gh run list --workflow=promote-release.yml --limit 10

# List recent releases
gh release list --limit 10

# View specific release
gh release view v1.0.0
```

## FAQ

**Q: Can I promote the same digest to multiple tags?**
A: Yes. Run the workflow multiple times with the same digest but different tags.

**Q: Can I promote a tag without approval?**
A: No. The `production` environment requires manual approval by design.

**Q: What happens if I cancel during promotion?**
A: The workflow stops immediately. Partial promotions are not possible (server-side imagetools operation is atomic).

**Q: How do I verify a promoted tag?**
A: Use `cosign verify` with the OIDC issuer/identity matching GitHub Actions.

**Q: Can I promote images from other registries?**
A: Not currently. The workflow is hardcoded to `ghcr.io` for input validation.

**Q: What if the sanity check fails?**
A: The workflow fails before creating the release. Do not use that digest for production.

**Q: How long are promoted tags retained?**
A: Indefinitely (unless manually deleted from GHCR). Tags are immutable once created.

**Q: Can I automate promotions?**
A: Yes, but you must configure the `production` environment to allow automated approvals (not recommended for production releases).

## References

- [Docker Buildx Imagetools Documentation](https://docs.docker.com/engine/reference/commandline/buildx_imagetools/)
- [Cosign Keyless Signing](https://docs.sigstore.dev/cosign/keyless/)
- [GitHub Actions Environments](https://docs.github.com/en/actions/deployment/targeting-different-environments/using-environments-for-deployment)
- [Semantic Versioning Specification](https://semver.org/)
- [OCI Image Spec](https://github.com/opencontainers/image-spec/blob/main/spec.md)
