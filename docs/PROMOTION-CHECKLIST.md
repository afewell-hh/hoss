# Promotion Operations Checklist

Quick reference for promoting container images to release tags.

## One-Time Setup

### 1. Apply Tag Protection Ruleset

Protect `v*.*.*` tags from deletion and unauthorized creation:

```bash
# Via GitHub API
gh api -X POST repos/afewell-hh/hoss/rulesets \
  --input docs/github-tag-protection-ruleset.json

# Verify
gh api repos/afewell-hh/hoss/rulesets | \
  jq '.[] | select(.name == "Protect SemVer Release Tags") | {name, enforcement}'
```

**Or via UI:** Settings → Rules → Rulesets → New tag ruleset (see `docs/TAG-PROTECTION-RULESET.md`)

**Expected output:**
```json
{
  "name": "Protect SemVer Release Tags",
  "enforcement": "active"
}
```

### 2. Configure Branch Protection

Ensure required status checks include:
- `smoke-local` (informational)
- `review-kit (strict)` (blocking)
- `actionlint` (blocking)
- `validate-pins` (blocking)

**Via UI:** Settings → Branches → main → Edit → Required status checks

### 3. Optional: Enable Notifications

Uncomment notification steps in `.github/workflows/promote-release.yml`:

**For Slack:**
```yaml
# 1. Add SLACK_WEBHOOK_URL secret
gh secret set SLACK_WEBHOOK_URL --body "https://hooks.slack.com/services/..."

# 2. Uncomment "Notify release (Slack)" step in promote-release.yml
```

**For GitHub Discussions:**
```yaml
# 1. Get category ID
gh api graphql -f query='
  query {
    repository(owner: "afewell-hh", name: "hoss") {
      discussionCategories(first: 10) {
        nodes { id name }
      }
    }
  }' | jq '.data.repository.discussionCategories.nodes[] | select(.name == "Announcements")'

# 2. Update categoryId in the commented step
# 3. Uncomment "Post to GitHub Discussions" step
```

## Per-Release Operations

### Step 1: Collect Digest

```bash
# Run digest collection with verification
./scripts/collect-digests.sh --json-out .artifacts/digests.json

# Extract the specific digest you want to promote
DIGEST64=$(jq -r '.engine' .artifacts/digests.json | sed 's|^.*@sha256:||')

# Verify it's valid (should be 64 hex chars)
echo "$DIGEST64" | grep -E '^[0-9a-f]{64}$' && echo "✅ Valid" || echo "❌ Invalid"

# Confirm cosign signature (auto on main branch)
IMAGE="ghcr.io/afewell-hh/hoss/hhfab"
cosign verify "${IMAGE}@sha256:${DIGEST64}" \
  --certificate-identity-regexp="^https://github.com/.+/.+@" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

**Expected:** Cosign verification passes with certificate details.

### Step 2: Trigger Promotion

```bash
# Promote to a new semantic version
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$DIGEST64" \
  -f tag=v1.2.3

# Monitor the workflow
gh run list --workflow=promote-release.yml --limit 1
gh run watch
```

**Expected:** Workflow starts, preflight checks pass (~30s), then waits for approval.

### Step 3: Approve Environment

1. Navigate to the workflow run in GitHub Actions
2. Review preflight summary:
   - ✅ Input validation passed
   - ✅ Tag policy check passed
   - ✅ Tag is available (immutability)
   - ✅ Source digest verified
3. Click **Review deployments** → **production** → **Approve and deploy**

**Expected:** Promotion job starts immediately after approval.

### Step 4: Watch Double-Verify + Smoke Test

Monitor the promotion steps:
- Server-side imagetools promotion
- Cosign signing
- Double verification (tag + digest)
- **Offline smoke test:** `hhfab version` in isolated container
- Promotion receipt generation
- GitHub Release creation
- Receipt attachment

**Expected:** All steps pass in ~1-2 minutes.

### Step 5: Verify Release Artifacts

```bash
TAG="v1.2.3"
IMAGE="ghcr.io/afewell-hh/hoss/hhfab"

# 1. Check GitHub Release
gh release view "$TAG"

# 2. Download promotion receipt
gh release download "$TAG" --pattern "receipt-${TAG}.json"
cat "receipt-${TAG}.json" | jq .

# 3. Verify signatures (copy from release notes)
cosign verify "${IMAGE}:${TAG}" \
  --certificate-identity-regexp="^https://github.com/.+/.+@" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com

# 4. Inspect manifest
docker buildx imagetools inspect "${IMAGE}:${TAG}"

# 5. Pull and test
docker pull "${IMAGE}:${TAG}"
docker run --rm "${IMAGE}:${TAG}" hhfab version
```

**Expected:** All verifications pass, hhfab version prints correctly.

### Step 6: Confirm Auto-Close

If there was a previous promotion failure for this tag:

```bash
# Check for auto-closed issues
gh issue list --label promotion-failure --state closed | grep "$TAG"
```

**Expected:** Any open `promotion-failure` issues for this tag are now closed with a success comment.

### Step 7: Optional - Update CI Variable

If you want review-kit to use the new tag:

```bash
# Get the promoted digest
NEW_DIGEST=$(docker buildx imagetools inspect "${IMAGE}:${TAG}" --format '{{.Name}}@{{.Digest}}')

# Update CI variable
gh api -X PATCH repos/afewell-hh/hoss/actions/variables/HHFAB_IMAGE_DIGEST \
  -f value="$NEW_DIGEST"

# Trigger review-kit validation
gh workflow run review-kit.yml --ref main

# Monitor
gh run watch
```

**Expected:** Review-kit passes with the new digest, status: "ok", warnings: 0.

## Self-Tests (Validation)

Run these tests to exercise all guards:

### Test 1: SemVer Policy (Should Fail)

```bash
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest=$(printf '%064d' 0) \
  -f tag=not-semver

# Expected: Preflight fails (tag policy violation)
# Auto-issue created with label: promotion-failure
```

### Test 2: Digest Reachability (Should Fail)

```bash
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest=$(printf '%064d' 0) \
  -f tag=v9.9.9

# Expected: Preflight fails (source digest not found)
```

### Test 3: Tag Immutability (Should Fail on 2nd Run)

```bash
# First run (should succeed)
DIGEST64=$(./scripts/collect-digests.sh --json-out .artifacts/d.json >/dev/null; \
           jq -r '.engine' .artifacts/d.json | sed 's|^.*@sha256:||')

gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$DIGEST64" \
  -f tag=v1.0.0

# Wait for completion, then retry same tag
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$DIGEST64" \
  -f tag=v1.0.0

# Expected: Preflight fails (tag already exists)
```

### Test 4: Happy Path (Full Flow)

```bash
DIGEST64=$(./scripts/collect-digests.sh --json-out .artifacts/d.json >/dev/null; \
           jq -r '.engine' .artifacts/d.json | sed 's|^.*@sha256:||')

gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$DIGEST64" \
  -f tag=v1.0.1

# Expected:
# 1. Preflight passes (~30s)
# 2. Approval gate (manual review)
# 3. After approval:
#    - Promote, sign, double-verify
#    - Offline smoke test passes
#    - Receipt generated: receipt-v1.0.1.json
#    - GitHub Release created
#    - Receipt attached to release
#    - Any open promotion-failure issues auto-closed
```

## Common Operations

### Promoting a Nightly Build

```bash
# Find last successful nightly run
LATEST_RUN=$(gh run list --workflow=review-kit.yml --status=success --limit=1 --json databaseId --jq '.[0].databaseId')

# Extract digest from logs
gh run view $LATEST_RUN --log | grep "image.digest"

# Extract 64 hex chars and promote
DIGEST64="abc123..."  # From logs
gh workflow run promote-release.yml --ref main \
  -f image=ghcr.io/afewell-hh/hoss/hhfab \
  -f digest="$DIGEST64" \
  -f tag=stable
```

### Promoting a Release Candidate

```bash
# Promote to RC tag
gh workflow run promote-release.yml --ref main \
  -f digest="$DIGEST64" \
  -f tag=v2.0.0-rc.1

# After testing, promote same digest to final release
gh workflow run promote-release.yml --ref main \
  -f digest="$DIGEST64" \
  -f tag=v2.0.0
```

### Emergency Non-SemVer Tag

```bash
# Bypass SemVer policy for emergency
gh workflow run promote-release.yml --ref main \
  -f digest="$HOTFIX_DIGEST" \
  -f tag=emergency-$(date +%Y%m%d-%H%M) \
  -f allow_non_semver=true

# Document in issue tracker
gh issue create \
  --title "Emergency non-SemVer tag: emergency-20240115-1430" \
  --label "release,non-semver,hotfix" \
  --body "Reason: [FILL IN]\nWorkflow: [RUN_URL]\nFollow-up: Promote to proper SemVer ASAP"
```

## Audit & Observability

### View Promotion History

```bash
# List all promotions
gh run list --workflow=promote-release.yml --limit 20

# List all releases
gh release list --limit 20

# Download receipts for a specific release
gh release download v1.0.0 --pattern "receipt-*.json"
```

### Verify Provenance

```bash
TAG="v1.0.0"
RECEIPT="receipt-${TAG}.json"

# Download receipt
gh release download "$TAG" --pattern "$RECEIPT"

# Extract key metadata
jq '{
  timestamp: .promotion.timestamp,
  triggered_by: .promotion.triggered_by,
  digest: .inputs.digest,
  cosign_verified: .verification.cosign_verified,
  sanity_passed: .sanity_check.passed
}' "$RECEIPT"
```

### Query Tag Protection

```bash
# Verify tag protection is active
gh api repos/afewell-hh/hoss/rulesets | \
  jq '.[] | select(.target == "tag") | {name, enforcement, rules: [.rules[].type]}'

# Test protection (should fail)
git tag v99.99.99
git push origin v99.99.99
# Expected: Error about ruleset violation
```

## Break-Glass Procedures

### Rollback to Previous Release

```bash
# Option 1: Deploy previous tag
kubectl set image deployment/app container=ghcr.io/afewell-hh/hoss/hhfab:v0.9.0

# Option 2: Promote last-good digest to new hotfix tag
LAST_GOOD_DIGEST="abc123..."
gh workflow run promote-release.yml --ref main \
  -f digest="$LAST_GOOD_DIGEST" \
  -f tag=v1.0.1-hotfix.1
```

### Bypass Tag Immutability (Last Resort)

**⚠️ WARNING:** Breaks immutability guarantee. Document in incident report.

```bash
# 1. Delete tag from GHCR (manual, via UI or API)
# 2. Delete GitHub Release
gh release delete v1.0.0 --yes

# 3. Re-run promotion with new digest
gh workflow run promote-release.yml --ref main \
  -f digest="$NEW_DIGEST" \
  -f tag=v1.0.0

# 4. REQUIRED: Create incident report
gh issue create \
  --title "INCIDENT: Tag immutability override for v1.0.0" \
  --label "security,incident,release" \
  --body "Date: $(date -u)\nReason: [REQUIRED]\nApprovers: [REQUIRED]\nImpact: [REQUIRED]"
```

## Troubleshooting

### Preflight Failures

See `docs/runbooks/promote-release.md` → Troubleshooting section.

Common fixes:
- **Invalid digest format:** Remove `sha256:` prefix, use only 64 hex chars
- **Tag policy violation:** Use `vX.Y.Z` or set `allow_non_semver: true`
- **Tag already exists:** Use different tag (immutability enforced)
- **Digest not found:** Verify digest exists in GHCR

### Approval Timeout

If approval is pending for too long:
1. Check Settings → Environments → production → Required reviewers
2. Ensure reviewers are notified
3. Consider adding more reviewers

### Sanity Check Failure

If offline smoke test fails:
- DO NOT promote this digest
- Investigate source build
- Review build logs for errors
- Test locally: `docker run --rm <IMAGE>@sha256:<DIGEST> hhfab version`

## SLO Targets

**Promotion Time-to-Availability (Approval → Release):**
- **Target:** ≤ 5 minutes
- **Tracking:** Check workflow run duration from approval to completion
- **Alert:** If exceeded consistently, investigate runner performance

**Success Rate:**
- **Target:** ≥ 95% (preflight + promote combined)
- **Tracking:** `gh run list --workflow=promote-release.yml --status=success --limit=100 | wc -l`

## References

- [Promote Release Runbook](./runbooks/promote-release.md) - Detailed operational guide
- [Tag Protection Ruleset](./TAG-PROTECTION-RULESET.md) - GitHub tag protection setup
- [Review Kit Runbook](./runbooks/review-kit.md) - CI/CD validation procedures
- [Digest Collection Script](../scripts/collect-digests.sh) - Digest extraction tool
