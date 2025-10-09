# HOSS App Pack - Integration Test Scenarios

**Target:** Day 7 Joint Integration Session with Demon Team
**Version:** App Pack v0.1
**Date:** Sprint Wave A - Mid-Sprint

## Overview

This document defines integration test scenarios for validating HOSS App Pack v0.1 against the Demon platform's App Pack infrastructure.

## Quick Start

For a minimal validation test:

```bash
# 1. Install app pack
DEMON_APP_HOME=/tmp/app-home demonctl app install ./app-pack

# 2. Create a simple matrix file (optional)
cat > /tmp/matrix.txt <<EOF
samples/topology-min.yaml
EOF

# 3. Run validation with hossctl
export HHFAB_MATRIX=$(cat /tmp/matrix.txt)
DEMON_APP_HOME=/tmp/app-home DEMON_CONTAINER_USER=1000:1000 \
  hossctl validate samples/topology-min.yaml

# Expected output:
# {
#   "result": {
#     "success": true,
#     "data": {
#       "status": "ok",
#       "counts": {"validated": 1, "warnings": 0, "failures": 0}
#     }
#   }
# }
```

For debug diagnostics, prefix with `DEMON_DEBUG=1` to see container execution details.

## Prerequisites

**Demon Platform Requirements:**
- `demonctl` CLI installed
- Demon platform running (local or dev instance)
- App Pack installer functional (`demonctl app install`)
- container-exec capsule runtime available
- Ritual API endpoints available

**HOSS Requirements:**
- HOSS App Pack v0.1 built and signed
- `hossctl` CLI built
- Sample wiring diagrams available

## Test Scenarios

### Scenario 1: Basic App Pack Installation

**Objective:** Verify HOSS App Pack can be installed on Demon platform

**Steps:**
```bash
# 1. Build app pack
make app-pack-build

# 2. Install on Demon
demonctl app install .artifacts/hoss-app-pack-v0.1.0.tar.gz

# 3. Verify installation
demonctl app list

# Expected output:
# NAME   VERSION   STATUS
# hoss   0.1.0     active
```

**Success Criteria:**
- ✅ App pack installs without errors
- ✅ `demonctl app list` shows hoss as active
- ✅ No warnings or errors in installation logs

**Failure Cases to Test:**
- Missing required fields in app-pack.yaml
- Invalid JSON Schema in contracts
- Non-digest-pinned image reference
- Missing capsule scripts

---

### Scenario 2: Schema Validation

**Objective:** Verify app-pack.yaml conforms to Demon's v1 schema

**Steps:**
```bash
# 1. Fetch Demon's schema
curl -o /tmp/app-pack.v1.schema.json \
  https://raw.githubusercontent.com/afewell-hh/Demon/main/contracts/schemas/app-pack.v1.schema.json

# 2. Validate HOSS app-pack.yaml
python3 <<EOF
import json
from jsonschema import validate

with open('/tmp/app-pack.v1.schema.json') as f:
    schema = json.load(f)

import yaml
with open('app-pack/app-pack.yaml') as f:
    pack = yaml.safe_load(f)

validate(instance=pack, schema=schema)
print("✅ app-pack.yaml conforms to Demon v1 schema")
EOF
```

**Success Criteria:**
- ✅ app-pack.yaml validates against Demon's schema
- ✅ All required fields present
- ✅ All field types match schema

---

### Scenario 3: Contract Registration

**Objective:** Verify HOSS contracts are registered in Demon's registry

**Steps:**
```bash
# 1. Install app pack
demonctl app install ./app-pack

# 2. List contracts
demonctl contract list --app hoss

# Expected output:
# ID                      VERSION   APP   PATH
# hoss/validate.request   0.1.0     hoss  contracts/hoss/validate.request.json
# hoss/validate.result    0.1.0     hoss  contracts/hoss/validate.result.json
```

**Success Criteria:**
- ✅ Both contracts registered
- ✅ Namespaced to `hoss/` prefix
- ✅ Correct version (0.1.0)
- ✅ Schemas accessible via Demon API

---

### Scenario 4: Ritual Execution (Basic)

**Objective:** Execute hoss-validate ritual and verify envelope output

**Steps:**
```bash
# 1. Start validation ritual
curl -X POST http://localhost:8080/api/v1/rituals/hoss-validate/runs \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "diagramPath": "samples/topology-min.yaml"
    }
  }'

# Response:
# {"runId": "run-abc123", "status": "running", "ritual": "hoss-validate"}

# 2. Poll run status
curl http://localhost:8080/api/v1/runs/run-abc123

# 3. Fetch envelope
curl http://localhost:8080/api/v1/runs/run-abc123/envelope
```

**Expected Envelope:**
```json
{
  "status": "ok",
  "counts": {
    "validated": 1,
    "warnings": 0,
    "failures": 0
  },
  "tool": {
    "name": "hhfab",
    "version": "v0.41.3",
    "imageDigest": "ghcr.io/afewell-hh/hoss/hhfab@sha256:..."
  },
  "timestamp": "2025-10-05T...",
  "matrix": ["samples/topology-min.yaml"],
  "errors": []
}
```

**Success Criteria:**
- ✅ Ritual starts successfully
- ✅ Status transitions: running → completed
- ✅ Envelope conforms to validate.result.json schema
- ✅ status = "ok"
- ✅ counts.validated = 1
- ✅ counts.warnings = 0
- ✅ counts.failures = 0

---

### Scenario 5: hossctl CLI Integration

**Objective:** Verify hossctl CLI can interact with Demon APIs

**Steps:**
```bash
# 1. Set Demon endpoint
export DEMON_URL=http://localhost:8080

# 2. Run validation via hossctl
hossctl validate samples/topology-min.yaml --json

# 3. Verify output
```

**Expected Output:**
```json
{
  "status": "ok",
  "counts": {
    "validated": 1,
    "warnings": 0,
    "failures": 0
  },
  "tool": {
    "name": "hhfab",
    "version": "v0.41.3",
    "imageDigest": "ghcr.io/afewell-hh/hoss/hhfab@sha256:..."
  }
}
```

**Success Criteria:**
- ✅ hossctl successfully connects to Demon
- ✅ Ritual starts and completes
- ✅ Envelope returned and displayed
- ✅ Exit code 0 for successful validation

---

### Scenario 6: Container-Exec Capsule Execution

**Objective:** Verify hhfab capsule runs in container-exec runtime

**Steps:**
```bash
# Monitor capsule execution logs
demonctl logs capsule/hhfab --run-id run-abc123
```

**Expected Behavior:**
- ✅ hhfab container pulled by digest
- ✅ Container runs with sandbox constraints:
  - `--network=none`
  - `--read-only`
  - `--tmpfs /tmp`
  - `--security-opt=no-new-privileges`
- ✅ hhfab-validate.sh executes
- ✅ Envelope written to $ENVELOPE_PATH
- ✅ Container exits with code 0

**Logs Should Show:**
```
Pulling ghcr.io/afewell-hh/hoss/hhfab@sha256:...
Running container with sandbox constraints
Executing: bash -lc capsules/hhfab/scripts/hhfab-validate.sh
Validation succeeded
Envelope written to: /workspace/.artifacts/summary.json
Container exited: 0
```

---

### Scenario 7: Validation Failure Handling

**Objective:** Verify error handling when validation fails

**Steps:**
```bash
# 1. Run validation on invalid diagram
hossctl validate samples/invalid/bad-breakout.yaml --json
```

**Expected Envelope:**
```json
{
  "status": "error",
  "counts": {
    "validated": 0,
    "warnings": 0,
    "failures": 1
  },
  "tool": {
    "name": "hhfab",
    "version": "v0.41.3",
    "imageDigest": "ghcr.io/afewell-hh/hoss/hhfab@sha256:..."
  },
  "errors": [
    {
      "message": "Invalid breakout configuration: ...",
      "file": "samples/invalid/bad-breakout.yaml"
    }
  ]
}
```

**Success Criteria:**
- ✅ status = "error"
- ✅ counts.failures = 1
- ✅ errors array populated with details
- ✅ hossctl exits with non-zero code

---

### Scenario 8: UI Card Rendering

**Objective:** Verify Operate UI renders hoss-validate card

**Steps:**
```bash
# 1. Navigate to Operate UI
open http://localhost:8080/operate

# 2. Find "HOSS Validation" card

# 3. Verify fields displayed:
#    - Status badge (green for ok)
#    - Diagrams Validated: 1
#    - Warnings: 0
#    - Failures: 0
#    - Tool Version: v0.41.3
#    - Image Digest: ghcr.io/...@sha256:... (truncated)
```

**Success Criteria:**
- ✅ Card appears in Operate UI
- ✅ Title: "HOSS Validation"
- ✅ All fields render correctly
- ✅ Status badge color matches status (green/yellow/red)
- ✅ No custom JS errors

---

### Scenario 9: App Pack Uninstallation

**Objective:** Verify clean uninstall removes all registrations

**Steps:**
```bash
# 1. Uninstall app pack
demonctl app uninstall hoss

# 2. Verify removal
demonctl app list
demonctl contract list
demonctl ritual list
```

**Success Criteria:**
- ✅ `hoss` not in app list
- ✅ `hoss/*` contracts removed
- ✅ `hoss-validate` ritual removed
- ✅ UI card no longer rendered
- ✅ No orphaned resources

---

### Scenario 10: Digest Pin Enforcement

**Objective:** Verify Demon rejects non-digest-pinned images

**Steps:**
```bash
# 1. Modify app-pack.yaml to use tag instead of digest
sed -i 's|@sha256:[0-9a-f]*|:latest|' app-pack/app-pack.yaml

# 2. Attempt installation
demonctl app install ./app-pack

# Expected error:
# Error: imageDigest must be digest-pinned (@sha256:...)
```

**Success Criteria:**
- ✅ Installation fails with clear error
- ✅ Error message indicates digest requirement
- ✅ No partial installation

---

## Integration Test Execution Plan (Day 7)

### Pre-Session (30 min before)
- [ ] HOSS: Build and sign app pack
- [ ] HOSS: Build hossctl CLI
- [ ] Demon: Start Demon platform instance
- [ ] Demon: Verify container-exec capsule ready
- [ ] Both: Share endpoint URLs and credentials

### Session Agenda (2-3 hours)

**Phase 1: Installation (30 min)**
- Run Scenarios 1, 2, 3
- Verify schema validation
- Check contract registration

**Phase 2: Basic Execution (45 min)**
- Run Scenarios 4, 5, 6
- Execute ritual via API
- Execute via hossctl CLI
- Monitor capsule logs

**Phase 3: Edge Cases (30 min)**
- Run Scenario 7 (failure handling)
- Test error envelopes
- Verify envelope schema compliance

**Phase 4: UI & Cleanup (30 min)**
- Run Scenarios 8, 9
- Check UI card rendering
- Test uninstall flow

**Phase 5: Security Validation (15 min)**
- Run Scenario 10 (digest enforcement)
- Verify sandbox constraints in logs
- Check no network access

**Phase 6: Issues & Next Steps (30 min)**
- Document any failures
- Create follow-up tasks
- Update schemas/manifests as needed

### Post-Session
- [ ] Document all test results
- [ ] Create issues for any failures
- [ ] Update app-pack.yaml if schema changes needed
- [ ] Plan Day 8 fixes

## Known Limitations (v0.1)

**Expected to NOT work:**
- Cosign signature verification (use `--allow-unsigned`)
- Remote app pack fetch (install from local path only)
- Multi-step rituals (only single-step supported)
- Custom UI JavaScript (data-driven only)

**Acceptable for v0.1:**
- Manual approval for app installation
- No automatic updates
- Basic error messages (no detailed stack traces)

## Success Metrics

**Must Pass (Blocking):**
- ✅ Scenarios 1-6 (installation, execution, CLI)
- ✅ Envelope conforms to schema
- ✅ Container-exec runs successfully

**Should Pass (Non-Blocking):**
- ✅ Scenarios 7-9 (error handling, UI, uninstall)
- ✅ Scenario 10 (digest enforcement)

**Nice to Have:**
- ⚪ Performance metrics (ritual execution time)
- ⚪ Multi-diagram validation
- ⚪ Parallel ritual execution

## Contacts

**HOSS Team:** @afewell-hh
**Demon Team:** (TBD from Demon repo)
**Slack Channel:** #sprint-wave-a
**Issue Tracking:** HOSS #25, Demon #237

---

**Document Version:** 1.0
**Last Updated:** Day 4 (Mid-Sprint)
**Next Review:** Day 7 (Integration Session)
