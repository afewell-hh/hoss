# GitHub Tag Protection Ruleset

This document explains how to configure GitHub tag protection for SemVer release tags created by the `promote-release` workflow.

## Overview

Tag protection ensures that release tags (`v*.*.*`) are:
- **Immutable**: Cannot be deleted after creation
- **Provenance-verified**: Can only be created by GitHub Actions (promote-release workflow)
- **Audit-trailed**: All tag creation is logged and attributable

## Ruleset Configuration

The ruleset in `github-tag-protection-ruleset.json` enforces:

1. **Deletion protection**: SemVer tags cannot be deleted
2. **Creation restriction**: Only GitHub Actions can create tags matching `v*.*.*`
3. **Linear history**: Prevents force-push scenarios (tags are immutable by nature)
4. **Bypass for admins**: Repository admins can bypass in emergencies

## How to Apply

### Option 1: Via GitHub UI (Recommended)

1. Navigate to **Settings** → **Rules** → **Rulesets**
2. Click **New ruleset** → **New tag ruleset**
3. Configure the ruleset:
   - **Name:** `Protect SemVer Release Tags`
   - **Enforcement status:** Active
   - **Target tags:** `refs/tags/v[0-9]*.[0-9]*.[0-9]*` (regex pattern)
   - **Rules:**
     - ✅ Restrict deletions
     - ✅ Restrict creations (allow only GitHub Actions)
   - **Bypass list:**
     - Add repository admins (for emergency override)
4. Click **Create**

### Option 2: Via GitHub API

```bash
# Create the ruleset via API
gh api -X POST repos/afewell-hh/hoss/rulesets \
  --input docs/github-tag-protection-ruleset.json

# Verify the ruleset was created
gh api repos/afewell-hh/hoss/rulesets | jq '.[] | select(.name == "Protect SemVer Release Tags")'
```

### Option 3: Manual JSON Import

1. Go to **Settings** → **Rules** → **Rulesets** → **New tag ruleset**
2. Switch to the **JSON** tab
3. Paste the contents of `github-tag-protection-ruleset.json`
4. Click **Create**

## What This Protects

### Protected Tag Pattern

The ruleset matches tags following Semantic Versioning:
- `v1.0.0` ✅ Protected
- `v2.3.4` ✅ Protected
- `v1.0.0-rc.1` ✅ Protected
- `v10.20.30-beta.2` ✅ Protected

### Not Protected

The following tags are **not** protected (can be created/deleted manually):
- `stable` ❌ Not protected (use with caution)
- `latest` ❌ Not protected (use with caution)
- `my-feature` ❌ Not protected
- `test-v1.0.0` ❌ Not protected (doesn't match pattern)

**Note:** If you want to protect `stable` and `latest` tags, add them to the `include` list:
```json
"include": [
  "refs/tags/v[0-9]*.[0-9]*.[0-9]*",
  "refs/tags/stable",
  "refs/tags/latest"
]
```

## How It Works With promote-release Workflow

### Normal Flow (Allowed)

1. Developer triggers `promote-release` workflow via `workflow_dispatch`
2. Workflow authenticates with `GITHUB_TOKEN`
3. GitHub recognizes the workflow as `github-actions` app
4. Tag creation is allowed by the ruleset
5. Tag is created with full audit trail

### Manual Tag Creation (Blocked)

```bash
# This will be rejected by the ruleset
git tag v1.0.0
git push origin v1.0.0
# Error: GH013: Tag creation not allowed (ruleset violation)
```

### Admin Override (Emergency)

If a repository admin needs to bypass the ruleset:

1. Navigate to **Settings** → **Rules** → **Rulesets**
2. Edit the ruleset → **Bypass list**
3. Confirm admin is listed
4. Use admin account to create/delete the tag
5. **Document the override** in an issue with the `security` label

## Benefits

### Provenance

Every SemVer tag is guaranteed to come from the promote-release workflow:
- Verified preflight checks (input validation, immutability, reachability)
- Manual approval gate (production environment)
- Cosign signature (keyless OIDC)
- Promotion receipt (JSON artifact with full metadata)
- GitHub Release (auto-generated with verification instructions)

### Immutability

Tags cannot be deleted or overwritten:
- Prevents accidental or malicious tag deletion
- Ensures `v1.0.0` always points to the same digest
- Audit trail is preserved

### Compliance

Meets supply chain security requirements:
- SLSA Level 3 provenance (GitHub Actions with attestation)
- Sigstore transparency log (cosign signatures)
- Immutable references (digest-pinned + tag-protected)

## Verification

### Check Ruleset Status

```bash
# List all rulesets
gh api repos/afewell-hh/hoss/rulesets | jq '.[] | {name, enforcement}'

# Get specific ruleset details
gh api repos/afewell-hh/hoss/rulesets | \
  jq '.[] | select(.name == "Protect SemVer Release Tags")'
```

### Test Protection

```bash
# Try to create a tag manually (should fail)
git tag v99.99.99
git push origin v99.99.99
# Expected: Error message about ruleset violation

# Try to delete a protected tag (should fail)
git push --delete origin v1.0.0
# Expected: Error message about deletion protection
```

### Audit Trail

View tag creation events:

```bash
# List tags with creation details
gh api repos/afewell-hh/hoss/git/refs/tags | \
  jq '.[] | select(.ref | startswith("refs/tags/v")) | {ref, sha: .object.sha}'

# Check specific tag
gh api repos/afewell-hh/hoss/git/refs/tags/v1.0.0
```

## Rollback Procedure

If you need to remove or modify the ruleset:

1. **Disable** (non-destructive):
   ```bash
   # Via UI: Settings → Rules → Rulesets → Edit → Enforcement: Disabled
   # Via API:
   RULESET_ID=$(gh api repos/afewell-hh/hoss/rulesets | jq '.[] | select(.name == "Protect SemVer Release Tags") | .id')
   gh api -X PUT repos/afewell-hh/hoss/rulesets/$RULESET_ID \
     -f enforcement=disabled
   ```

2. **Delete** (permanent):
   ```bash
   RULESET_ID=$(gh api repos/afewell-hh/hoss/rulesets | jq '.[] | select(.name == "Protect SemVer Release Tags") | .id')
   gh api -X DELETE repos/afewell-hh/hoss/rulesets/$RULESET_ID
   ```

## Troubleshooting

### "Ruleset creation failed"

**Cause:** Insufficient permissions or invalid JSON

**Fix:**
- Ensure you have admin access to the repository
- Validate JSON syntax: `jq . docs/github-tag-protection-ruleset.json`
- Check for typos in the `target` field (must be `"tag"`)

### "Tag creation blocked by ruleset"

**Cause:** Trying to create tag manually instead of via workflow

**Fix:**
- Use `promote-release` workflow to create tags
- Or add your user/team to the bypass list (not recommended for production)

### "Cannot delete protected tag"

**Cause:** Deletion protection is working as intended

**Fix:**
- Tags are immutable by design; create a new version instead
- If deletion is truly necessary, admin can bypass via UI or disable ruleset temporarily

## References

- [GitHub Rulesets Documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [Tag Protection API](https://docs.github.com/en/rest/repos/rules)
- [Promote Release Runbook](./runbooks/promote-release.md)
- [SLSA Provenance Levels](https://slsa.dev/spec/v1.0/levels)
