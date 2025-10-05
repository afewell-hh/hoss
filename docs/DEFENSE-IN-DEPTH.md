# Defense-in-Depth Protection Stack

Complete reference for the layered security controls protecting container image promotions.

## Overview

The promotion pipeline implements multiple, overlapping security controls across three phases:

1. **Pre-Promotion Guards** - Prevent bad promotions before they start
2. **Promotion-Time Validation** - Ensure integrity during the promotion flow
3. **Post-Promotion Monitoring** - Detect drift and violations after promotion

## Pre-Promotion Guards

### 1. SHA-Pinned Actions Enforcement

**Workflow:** `.github/workflows/validate-action-pins.yml`
**Runs:** On PR + push to main
**Scope:** All workflow files

**What it checks:**
- Scans all `uses:` statements in workflows
- Fails if any action uses `@vX` instead of `@<sha>`
- Pairs with Dependabot to keep pins updated

**Example failure:**
```yaml
# ❌ Will fail
uses: actions/checkout@v4

# ✅ Will pass
uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
```

**Bypass:** Not allowed. All actions must be SHA-pinned.

---

### 2. Main Branch Validation Check

**Workflow:** `.github/workflows/promote-release.yml` (preflight job)
**Runs:** During preflight, before approval
**Scope:** Last completed runs on main branch

**What it checks:**
- `review-kit (strict)` must be green on main
- `smoke-local` must be green on main
- Fails if either workflow is missing or failed

**Why:** Ensures promotions only happen from a known-good baseline.

**Example failure:**
```
❌ Main branch validation not green:
  - review-kit (strict): Last run failure (https://github.com/...)
  - smoke-local: Last run success

Ensure all required workflows pass on main before promoting.
```

**Bypass:** Not allowed. Fix the failing workflows on main first.

---

### 3. Digest Drift Detection

**Workflow:** `.github/workflows/digest-drift-watcher.yml`
**Runs:** Nightly at 4:00 AM UTC
**Scope:** All digest-pinned images in bundle

**What it checks:**
- Compares current digests against expected bundle
- Detects upstream image updates without rotation
- Auto-creates issue on drift

**Auto-remediation:** None (manual triage required)

---

### 4. Tag Protection Ruleset (Optional)

**Setup:** `docs/TAG-PROTECTION-RULESET.md`
**Applies to:** `refs/tags/v[0-9]*.[0-9]*.[0-9]*`
**Enforcement:** GitHub-native

**What it enforces:**
- Tags cannot be deleted
- Tags can only be created by GitHub Actions
- Manual tag creation is blocked

**To enable:**
```bash
gh api -X POST repos/afewell-hh/hoss/rulesets \
  --input docs/github-tag-protection-ruleset.json
```

## Promotion-Time Validation

### 5. Input Validation (Regex)

**Phase:** Preflight
**Validations:**
- Digest: Must be 64 hex chars (no `sha256:` prefix)
- Image: Must match `ghcr.io/<owner>/<name>`
- Tag: Alphanumeric + dots/dashes/underscores only

**Example failures:**
```bash
# ❌ Digest includes prefix
digest: "sha256:abc123..."
# Should be: "abc123..."

# ❌ Wrong registry
image: "docker.io/myimage"
# Should be: "ghcr.io/afewell-hh/hoss/hhfab"
```

---

### 6. SemVer Tag Policy Enforcement

**Phase:** Preflight
**Policy:** Tags must match `vX.Y.Z`, `stable`, or `latest`
**Bypass:** `allow_non_semver: true` (requires documentation)

**Allowed patterns:**
- `v1.0.0` ✅
- `v2.3.4-rc.1` ✅
- `stable` ✅
- `latest` ✅

**Disallowed patterns:**
- `my-feature` ❌ (unless bypassed)
- `test` ❌
- `1.0.0` ❌ (missing `v` prefix)

**Emergency bypass:**
```bash
gh workflow run promote-release.yml \
  -f tag=emergency-hotfix \
  -f allow_non_semver=true

# REQUIRED: Document in issue tracker
gh issue create --title "Non-SemVer tag: emergency-hotfix" \
  --body "Reason: [FILL IN]\nFollow-up: Migrate to vX.Y.Z ASAP"
```

---

### 7. Tag Immutability Check

**Phase:** Preflight
**Check:** Verifies tag doesn't already exist in registry
**Purpose:** Prevent overwrites (enforce immutability)

**Failure:**
```
❌ Tag already exists: ghcr.io/afewell-hh/hoss/hhfab:v1.0.0
This workflow enforces tag immutability. Use a different tag or delete the existing one first.
```

**Remediation:** Use a new tag (e.g., increment patch version)

---

### 8. Source Digest Reachability

**Phase:** Preflight
**Check:** Verifies source digest exists in GHCR
**Purpose:** Prevent promoting non-existent images

**Failure:**
```
❌ Source digest not found: ghcr.io/afewell-hh/hoss/hhfab@sha256:abc123...
Ensure the digest exists in the registry before promoting
```

**Remediation:** Verify digest is correct, or build/push the image first

---

### 9. Manual Approval Gate

**Phase:** Between preflight and promote
**Environment:** `production`
**Reviewers:** Configured in Settings → Environments

**What to verify before approving:**
1. Preflight summary shows all checks passed
2. Digest is from a trusted build (review-kit passed)
3. Tag follows release process (SemVer)
4. Main branch validations are green

**Timeout:** No automatic timeout (waits indefinitely)

---

### 10. Server-Side Manifest Promotion

**Phase:** Promote job
**Command:** `docker buildx imagetools create --tag <dst> <src>`
**Benefits:**
- No local pull/push (faster, efficient)
- Atomic operation (no partial states)
- Preserves multi-arch manifests

**vs. Traditional approach:**
```bash
# ❌ Old way (slow, heavyweight)
docker pull <image>@<digest>
docker tag <image>@<digest> <image>:<tag>
docker push <image>:<tag>

# ✅ New way (fast, server-side)
docker buildx imagetools create --tag <image>:<tag> <image>@<digest>
```

---

### 11. Keyless Cosign Signing

**Phase:** Promote job
**Method:** OIDC-based keyless signing
**Transparency:** Sigstore Rekor (public ledger)

**Certificate attributes:**
- Subject: `https://github.com/afewell-hh/hoss/.github/workflows/promote-release.yml@refs/heads/main`
- Issuer: `https://token.actions.githubusercontent.com`

**Verification:**
```bash
cosign verify ghcr.io/afewell-hh/hoss/hhfab:v1.0.0 \
  --certificate-identity-regexp="^https://github.com/.+/.+@" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

---

### 12. Double Cosign Verification

**Phase:** Promote job
**Checks:** Both tag AND digest references
**Purpose:** Ensure promotion integrity

**What gets verified:**
1. Tag reference: `ghcr.io/afewell-hh/hoss/hhfab:v1.0.0`
2. Digest reference: `ghcr.io/afewell-hh/hoss/hhfab@sha256:abc123...`

**Why both:** Protects against tag re-pointing and ensures both references have valid signatures.

---

### 13. Post-Promotion Sanity Check

**Phase:** Promote job (after signing)
**Test:** Offline `hhfab version` smoke test
**Isolation:**
- `--network=none` (no network access)
- `--read-only` (immutable filesystem)
- `--tmpfs /tmp:rw` (minimal writable temp)

**Failure criteria:**
- Binary not found or not executable
- Command exits non-zero
- No output produced

**Purpose:** Catch broken images before release creation

---

### 14. Promotion Receipt Generation

**Phase:** Promote job
**Format:** JSON artifact (90-day retention + permanent release asset)
**Schema:** `docs/receipt.schema.json`

**Contents:**
```json
{
  "promotion": {
    "timestamp": "2024-01-15T14:30:00Z",
    "workflow_run": "https://github.com/...",
    "triggered_by": "afewell-hh"
  },
  "inputs": { "image": "...", "digest": "...", "tag": "..." },
  "outputs": { "tag_reference": "...", "digest_reference": "..." },
  "verification": { "cosign_verified": true, "certificate_info": "..." },
  "sanity_check": { "passed": true, "output": "..." }
}
```

**Validation:**
```bash
# Core invariants check
jq -e '
  .promotion.workflow_run and
  (.inputs.digest | test("^[0-9a-f]{64}$")) and
  .verification.cosign_verified == true and
  .sanity_check.passed == true
' receipt-v1.0.0.json
```

---

### 15. Receipt Integrity Validation

**Phase:** Promote job (after receipt generation)
**Validates:**
- All required fields present
- Digest format (64 hex chars)
- References include proper prefixes (`:` for tag, `@sha256:` for digest)
- Cosign verified = true
- Sanity check passed = true
- Input digest matches receipt digest

**Failure:** Promotion fails before release creation

---

### 16. GitHub Release Creation

**Phase:** Promote job
**Auto-generated:**
- Release notes with manifest details
- Copy-paste verification snippet
- Deployment instructions

**Attached assets:**
- `receipt-<tag>.json` (permanent audit artifact)

---

### 17. Auto-Close Resolved Failures

**Phase:** Promote job (on success)
**Action:** Closes any open `promotion-failure` issues for the tag
**Comment:** Links to successful run + release + receipt

**Purpose:** Zero-maintenance issue lifecycle

## Post-Promotion Monitoring

### 18. Tag Drift Watcher

**Workflow:** `.github/workflows/tag-drift-watcher.yml`
**Runs:** Nightly at 4:17 AM UTC
**Scope:** Last 10 releases with receipts

**What it detects:**
- Tags re-pointed to different digests
- Tags deleted from registry
- Mismatches between receipt and current state

**Example drift:**
```
Receipt says: v1.0.0 → sha256:abc123...
Registry says: v1.0.0 → sha256:def456...

❌ DRIFT DETECTED
```

**Auto-remediation:** Creates issue with `tag-drift` label

**Common causes:**
- Manual tag manipulation
- Registry corruption
- Accidental force-push
- Security incident

---

### 19. Dependabot Auto-Updates

**Config:** `.github/dependabot.yml`
**Frequency:** Weekly (Mondays at 04:00 UTC)
**Scope:** GitHub Actions SHA pins
**PR limit:** 5 concurrent PRs

**How it works:**
1. Dependabot updates SHA pins weekly
2. `validate-action-pins.yml` ensures new PRs are properly pinned
3. Maintainer reviews and merges
4. Keeps protection up-to-date automatically

---

### 20. Branch Protection (Required Checks)

**Setup:** Settings → Branches → main
**Required status checks:**
- `smoke-local` (best-effort)
- `review-kit (strict)` (blocking)
- `actionlint` (blocking)
- `validate-pins` (blocking)

**Prevents:**
- Merging PRs with failing strict validation
- Merging PRs with unpinned actions
- Merging PRs with workflow syntax errors

## Protection Matrix

| Control | Phase | Bypass Allowed? | Auto-Remediate? | Issue on Fail? |
|---------|-------|-----------------|-----------------|----------------|
| SHA-Pinned Actions | Pre | ❌ No | ❌ No | ✅ Yes (PR check) |
| Main is Green | Pre | ❌ No | ❌ No | ✅ Yes (auto-issue) |
| Digest Drift | Pre | ❌ No | ❌ No | ✅ Yes (nightly) |
| Tag Protection | Pre | ⚠️ Admin only | ❌ No | ❌ No |
| Input Validation | Preflight | ❌ No | ❌ No | ✅ Yes (auto-issue) |
| SemVer Policy | Preflight | ✅ Yes (flag) | ❌ No | ✅ Yes (auto-issue) |
| Tag Immutability | Preflight | ⚠️ Manual delete | ❌ No | ✅ Yes (auto-issue) |
| Digest Reachability | Preflight | ❌ No | ❌ No | ✅ Yes (auto-issue) |
| Approval Gate | Between | ⚠️ Env config | ❌ No | ❌ No |
| Manifest Promotion | Promote | ❌ No | ❌ No | ✅ Yes (auto-issue) |
| Cosign Signing | Promote | ❌ No | ❌ No | ✅ Yes (auto-issue) |
| Double Verification | Promote | ❌ No | ❌ No | ✅ Yes (auto-issue) |
| Sanity Check | Promote | ❌ No | ❌ No | ✅ Yes (auto-issue) |
| Receipt Generation | Promote | ❌ No | ❌ No | ✅ Yes (auto-issue) |
| Receipt Validation | Promote | ❌ No | ❌ No | ✅ Yes (auto-issue) |
| Release Creation | Promote | ❌ No | ❌ No | ✅ Yes (auto-issue) |
| Auto-Close Issues | Promote | ❌ No | ✅ Yes | ❌ No |
| Tag Drift Watcher | Post | ❌ No | ❌ No | ✅ Yes (nightly) |
| Dependabot | Post | ❌ No | ⚠️ PRs only | ❌ No |
| Branch Protection | Post | ⚠️ Admin only | ❌ No | ❌ No |

## Failure Modes & Recovery

### Preflight Failure

**What happens:**
- Workflow fails before approval
- Auto-issue created with diagnostics
- No state changes (safe to retry)

**Recovery:**
1. Review auto-issue for root cause
2. Fix the issue (update inputs, verify digest, etc.)
3. Re-run the workflow

---

### Promote Failure

**What happens:**
- Workflow fails after approval
- Auto-issue created with diagnostics
- Partial state possible (tag may or may not exist)

**Recovery:**
1. Review auto-issue and logs
2. Check if tag was created: `docker buildx imagetools inspect <image>:<tag>`
3. If tag exists and correct: Close issue, done
4. If tag doesn't exist: Fix issue, re-run workflow
5. If tag exists but wrong: Use different tag (immutability enforced)

---

### Tag Drift Detected

**What happens:**
- Nightly watcher detects tag re-pointing
- Auto-issue created with drift details
- Tag remains in drifted state (no auto-fix)

**Recovery:**
1. Review drift details in issue
2. Investigate why tag was re-pointed:
   - Check GHCR audit logs
   - Review recent workflow runs
   - Check for unauthorized access
3. Decide on remediation:
   - **If intentional:** Document in issue, update receipt
   - **If accidental:** Re-promote from last-good digest
   - **If suspicious:** Escalate to security incident

---

### Receipt Validation Failure

**What happens:**
- Receipt generated but fails validation
- Workflow fails before release creation
- Receipt artifact still uploaded (for debugging)

**Recovery:**
1. Download receipt artifact from workflow run
2. Validate manually: `jq . receipt-<tag>.json`
3. Identify which invariant failed
4. Fix the root cause (likely a code bug)
5. Re-run the workflow

## Compliance Mapping

| Standard | Controls | Evidence |
|----------|----------|----------|
| **SLSA Level 3** | Hermetic builds, provenance | Receipt + cosign cert |
| **Supply Chain Levels** | Non-falsifiable provenance | Cosign transparency log |
| **Immutable Artifacts** | Tag protection, drift watcher | Tag ruleset + nightly scans |
| **Least Privilege** | Split job permissions | Preflight=read, Promote=write |
| **Defense in Depth** | 20 layered controls | This document |
| **Audit Trail** | Receipt + release + logs | 90-day artifacts + permanent release assets |

## Testing the Stack

Run these tests to exercise all controls:

```bash
# 1. SemVer policy
gh workflow run promote-release.yml --ref main \
  -f digest=$(printf '%064d' 0) \
  -f tag=not-semver
# Expected: Preflight fails, auto-issue created

# 2. Digest reachability
gh workflow run promote-release.yml --ref main \
  -f digest=$(printf '%064d' 0) \
  -f tag=v9.9.9
# Expected: Preflight fails, auto-issue created

# 3. Tag immutability (run twice)
DIGEST=$(./scripts/collect-digests.sh --json-out .artifacts/d.json >/dev/null; \
         jq -r '.engine' .artifacts/d.json | sed 's|^.*@sha256:||')
gh workflow run promote-release.yml --ref main \
  -f digest="$DIGEST" \
  -f tag=v1.0.0
# Second run: Expected to fail

# 4. Happy path
gh workflow run promote-release.yml --ref main \
  -f digest="$DIGEST" \
  -f tag=v1.0.1
# Expected: All guards pass, release created
```

## References

- [Promote Release Runbook](./runbooks/promote-release.md)
- [Tag Protection Setup](./TAG-PROTECTION-RULESET.md)
- [Promotion Checklist](./PROMOTION-CHECKLIST.md)
- [Receipt Schema](./receipt.schema.json)
- [Review Kit Runbook](./runbooks/review-kit.md)
