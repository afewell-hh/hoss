# Container-Exec Capsule - HOSS Requirements

**Target:** Demon Platform Team
**Purpose:** Define HOSS App Pack's requirements for container-exec capsule
**Version:** 1.0
**Date:** Day 4, Sprint Wave A

## Overview

This document specifies HOSS's requirements for the Demon platform's container-exec capsule implementation. These requirements are derived from HOSS App Pack v0.1's `app-pack.yaml` specification.

## Required Capsule Configuration

### Minimal Configuration (app-pack.yaml)

```yaml
capsules:
  - type: container-exec
    name: hhfab
    imageDigest: ghcr.io/afewell-hh/hoss/hhfab@sha256:54814bbf4e8459cfb35c7cf8872546f0d5d54da9fc317ffb53eab0e137b21d7b
    command: ["bash", "-lc", "capsules/hhfab/scripts/hhfab-validate.sh"]
    env:
      TMPDIR: /tmp
      HHFAB_CACHE_DIR: /tmp/.hhfab-cache
    outputs:
      envelopePath: /workspace/.artifacts/summary.json
    sandbox:
      network: none
      readOnly: true
      tmpfs:
        - /tmp
      securityOpt:
        - no-new-privileges
```

## Requirement Categories

### 1. Image Handling

**R1.1: Digest-Pinned Image Pull**
```bash
# Must pull by digest (not tag)
docker pull ghcr.io/afewell-hh/hoss/hhfab@sha256:54814bbf4e8459cfb35c7cf8872546f0d5d54da9fc317ffb53eab0e137b21d7b
```

**Requirements:**
- ✅ Support `@sha256:` digest format
- ✅ Reject tag-based references (`:latest`, `:v1.0`)
- ✅ Validate digest format (64 hex characters)
- ✅ Pull multi-arch manifests if available

**Priority:** CRITICAL (Day 6)

---

**R1.2: Image Registry Authentication**
```bash
# May require GHCR authentication
docker login ghcr.io
```

**Requirements:**
- ✅ Support GHCR registry (`ghcr.io`)
- ✅ Pass credentials if required (public images work without auth)
- ⚪ Support other registries (nice-to-have)

**Priority:** HIGH (Day 6)

---

### 2. Filesystem Mounts

**R2.1: Read-Only Workspace Mount**
```bash
docker run --read-only \
  -v "$PWD:/workspace:ro" \
  ...
```

**Requirements:**
- ✅ Mount app pack directory at `/workspace`
- ✅ Read-only mode (`:ro`)
- ✅ Include all app pack files:
  - `capsules/hhfab/scripts/hhfab-validate.sh`
  - `app-pack.yaml`
  - `contracts/`
  - `rituals/`
  - `ui/`

**Priority:** CRITICAL (Day 6)

---

**R2.2: Writable Artifacts Directory**
```bash
docker run --read-only \
  -v "$PWD/.artifacts:/workspace/.artifacts" \
  ...
```

**Requirements:**
- ✅ Mount `.artifacts` directory at `/workspace/.artifacts`
- ✅ Read-write mode (default)
- ✅ Persist envelope after container exits
- ✅ Create directory if it doesn't exist

**Priority:** CRITICAL (Day 6)

---

**R2.3: Tmpfs for /tmp**
```bash
docker run --read-only \
  --tmpfs /tmp:rw \
  ...
```

**Requirements:**
- ✅ Mount tmpfs at `/tmp`
- ✅ Read-write mode
- ✅ Size limit: 256MB recommended (configurable)
- ✅ Cleaned up after container exits

**Priority:** CRITICAL (Day 6)

---

### 3. Network Isolation

**R3.1: No Network Access**
```bash
docker run --network=none ...
```

**Requirements:**
- ✅ Disable all network interfaces (except loopback)
- ✅ No DNS resolution
- ✅ No outbound connections
- ✅ No inbound connections

**Priority:** CRITICAL (Day 6)

**Security Justification:**
- Prevents data exfiltration
- Prevents command & control connections
- Reduces attack surface

---

### 4. Security Constraints

**R4.1: No New Privileges**
```bash
docker run --security-opt=no-new-privileges ...
```

**Requirements:**
- ✅ Prevent privilege escalation
- ✅ Block setuid/setgid binaries
- ✅ Enforce at container runtime

**Priority:** CRITICAL (Day 6)

---

**R4.2: Non-Root User**
```bash
docker run --user 65532:65532 ...
```

**Requirements:**
- ✅ Run container as non-root user
- ✅ UID/GID: 65532:65532 (recommended)
- ⚪ Configurable UID/GID (nice-to-have)

**Priority:** HIGH (Day 6)

---

### 5. Environment Variables

**R5.1: Capsule Environment**
```yaml
env:
  TMPDIR: /tmp
  HHFAB_CACHE_DIR: /tmp/.hhfab-cache
```

**Requirements:**
- ✅ Pass environment variables from `env` block
- ✅ Support string values only
- ✅ No variable expansion/interpolation required

**Priority:** CRITICAL (Day 6)

---

**R5.2: Runtime-Provided Environment**
```bash
# Demon runtime must set these
ENVELOPE_PATH=/workspace/.artifacts/summary.json
HHFAB_IMAGE_DIGEST=ghcr.io/afewell-hh/hoss/hhfab@sha256:...
```

**Requirements:**
- ✅ `ENVELOPE_PATH`: Path where capsule writes result envelope
- ✅ `HHFAB_IMAGE_DIGEST`: Digest of the running container (for audit)
- ⚪ `CAPSULE_NAME`: Name of the capsule (nice-to-have)
- ⚪ `RITUAL_RUN_ID`: Run ID for correlation (nice-to-have)

**Priority:** CRITICAL (Day 6)

---

### 6. Command Execution

**R6.1: Command Array**
```yaml
command: ["bash", "-lc", "capsules/hhfab/scripts/hhfab-validate.sh"]
```

**Requirements:**
- ✅ Execute command array (not shell string)
- ✅ No shell interpretation (security)
- ✅ Working directory: `/workspace`

**Priority:** CRITICAL (Day 6)

**Example Docker Run:**
```bash
docker run --rm \
  --network=none \
  --read-only \
  --user 65532:65532 \
  --security-opt=no-new-privileges \
  --tmpfs /tmp:rw \
  -v "$PWD:/workspace:ro" \
  -v "$PWD/.artifacts:/workspace/.artifacts" \
  -w /workspace \
  -e TMPDIR=/tmp \
  -e HHFAB_CACHE_DIR=/tmp/.hhfab-cache \
  -e ENVELOPE_PATH=/workspace/.artifacts/summary.json \
  -e HHFAB_IMAGE_DIGEST=ghcr.io/afewell-hh/hoss/hhfab@sha256:... \
  ghcr.io/afewell-hh/hoss/hhfab@sha256:... \
  bash -lc "capsules/hhfab/scripts/hhfab-validate.sh"
```

---

### 7. Output Handling

**R7.1: Envelope Retrieval**
```yaml
outputs:
  envelopePath: /workspace/.artifacts/summary.json
```

**Requirements:**
- ✅ Read envelope from `envelopePath` after container exits
- ✅ Validate envelope is valid JSON
- ✅ Return envelope to ritual caller
- ⚠️ Handle missing envelope (error case)

**Priority:** CRITICAL (Day 6)

**Error Handling:**
```json
# If envelope missing or invalid, return:
{
  "status": "error",
  "errors": [
    {
      "message": "Capsule failed to produce envelope at /workspace/.artifacts/summary.json"
    }
  ]
}
```

---

**R7.2: Exit Code Handling**
```bash
# Container exit code determines ritual status
exit 0   # Success
exit 1-255  # Failure
```

**Requirements:**
- ✅ Capture container exit code
- ✅ Map to ritual status:
  - `0` → Check envelope for status
  - `non-zero` → Status = error (even if envelope says ok)

**Priority:** CRITICAL (Day 6)

---

### 8. Logging & Observability

**R8.1: Container Logs**
```bash
# Capture stdout/stderr
docker logs <container-id>
```

**Requirements:**
- ✅ Capture stdout and stderr
- ✅ Make available via `demonctl logs capsule/hhfab --run-id <run-id>`
- ✅ Retain for debugging (90-day retention recommended)
- ⚪ Structured logging support (nice-to-have)

**Priority:** HIGH (Day 7)

---

**R8.2: Execution Metrics**
```json
{
  "duration_ms": 5432,
  "exitCode": 0,
  "imageDigest": "ghcr.io/afewell-hh/hoss/hhfab@sha256:...",
  "capsuleName": "hhfab",
  "runId": "run-abc123"
}
```

**Requirements:**
- ⚪ Execution duration
- ⚪ Exit code
- ⚪ Image digest used
- ⚪ Resource usage (memory, CPU)

**Priority:** LOW (v0.2)

---

### 9. Timeout & Cleanup

**R9.1: Execution Timeout**
```yaml
# Ritual definition
timeout: 300s
```

**Requirements:**
- ✅ Enforce timeout from ritual definition
- ✅ Kill container gracefully (SIGTERM)
- ✅ Force kill after grace period (SIGKILL)
- ✅ Return timeout error in envelope

**Priority:** HIGH (Day 6)

**Timeout Error:**
```json
{
  "status": "error",
  "errors": [
    {
      "message": "Capsule execution timed out after 300s"
    }
  ]
}
```

---

**R9.2: Container Cleanup**
```bash
# Always clean up containers
docker run --rm ...
```

**Requirements:**
- ✅ Remove container after execution (`--rm`)
- ✅ Clean up tmpfs mounts
- ✅ No orphaned containers
- ⚪ Clean up unused images (nice-to-have)

**Priority:** HIGH (Day 6)

---

## Implementation Checklist

### Minimal Viable (Day 6)

**Must Have:**
- [ ] R1.1: Digest-pinned image pull
- [ ] R2.1: Read-only workspace mount
- [ ] R2.2: Writable artifacts directory
- [ ] R2.3: Tmpfs for /tmp
- [ ] R3.1: No network access
- [ ] R4.1: No new privileges
- [ ] R5.1: Capsule environment variables
- [ ] R5.2: Runtime-provided environment
- [ ] R6.1: Command array execution
- [ ] R7.1: Envelope retrieval
- [ ] R7.2: Exit code handling
- [ ] R9.1: Execution timeout
- [ ] R9.2: Container cleanup

**Nice to Have (defer to v0.2):**
- [ ] R1.2: Multi-registry support
- [ ] R4.2: Configurable UID/GID
- [ ] R8.1: Structured logging
- [ ] R8.2: Execution metrics

---

## Test Cases for Integration (Day 7)

### Test 1: Basic Execution
```bash
# Start ritual
curl -X POST http://localhost:8080/api/v1/rituals/hoss-validate/runs \
  -d '{"input": {"diagramPath": "samples/topology-min.yaml"}}'

# Expect: Container runs, envelope produced, exit code 0
```

### Test 2: Network Isolation
```bash
# Inside container, attempt network access
ping -c 1 google.com
curl http://example.com

# Expect: Both fail (no network)
```

### Test 3: Filesystem Isolation
```bash
# Inside container, attempt writes outside /tmp
touch /workspace/test.txt

# Expect: Permission denied (read-only)
```

### Test 4: Timeout Enforcement
```yaml
# Ritual with 5s timeout
timeout: 5s
```

```bash
# Script that sleeps 10s
sleep 10

# Expect: Container killed at 5s, timeout error in envelope
```

### Test 5: Missing Envelope
```bash
# Script that doesn't write envelope
exit 0

# Expect: Error returned, status = error
```

---

## Reference Implementation

**Pseudo-code for Demon container-exec runtime:**

```go
func ExecuteCapsule(ctx context.Context, capsule Capsule, ritual Ritual) (*Envelope, error) {
    // 1. Pull image by digest
    if err := docker.Pull(capsule.ImageDigest); err != nil {
        return nil, err
    }

    // 2. Create container with constraints
    container := docker.CreateContainer(capsule.ImageDigest, &ContainerConfig{
        Cmd:           capsule.Command,
        WorkingDir:    "/workspace",
        User:          "65532:65532",
        NetworkMode:   "none",
        ReadonlyRootfs: true,
        SecurityOpt:   []string{"no-new-privileges"},
        Binds: []string{
            fmt.Sprintf("%s:/workspace:ro", workspacePath),
            fmt.Sprintf("%s:/workspace/.artifacts", artifactsPath),
        },
        Tmpfs: map[string]string{
            "/tmp": "rw,size=256m",
        },
        Env: BuildEnv(capsule.Env, ritual.RunID, capsule.ImageDigest),
    })

    // 3. Start with timeout
    ctx, cancel := context.WithTimeout(ctx, ritual.Timeout)
    defer cancel()

    if err := docker.Start(ctx, container.ID); err != nil {
        return nil, err
    }

    // 4. Wait for completion
    exitCode, err := docker.Wait(ctx, container.ID)
    if err != nil {
        return nil, err
    }

    // 5. Retrieve envelope
    envelopePath := capsule.Outputs.EnvelopePath
    envelope, err := ReadEnvelope(filepath.Join(artifactsPath, envelopePath))
    if err != nil {
        return ErrorEnvelope("Failed to read envelope: %v", err), nil
    }

    // 6. Override status if exit code non-zero
    if exitCode != 0 {
        envelope.Status = "error"
    }

    return envelope, nil
}
```

---

## FAQ

**Q: Why digest-only references?**
A: Security. Tags are mutable; digests guarantee immutability and reproducibility.

**Q: Why no network access?**
A: Defense in depth. Prevents data exfiltration and C&C connections.

**Q: Why read-only filesystem?**
A: Prevents malicious code from persisting or modifying the app pack.

**Q: Why tmpfs instead of volumes for /tmp?**
A: Faster, ephemeral, auto-cleaned. No persistent state.

**Q: Why non-root user?**
A: Least privilege. Limits blast radius if container is compromised.

**Q: Can we skip some security constraints for v0.1?**
A: **No.** All listed security constraints are critical and non-negotiable.

---

## Contact

**HOSS Team:** @afewell-hh
**Issue:** HOSS #25, Demon #237
**Slack:** #sprint-wave-a

**Questions?** Post in Demon #237 or ping HOSS team in Slack.

---

**Document Version:** 1.0
**Last Updated:** Day 4 (Mid-Sprint)
**Next Review:** Day 7 (Integration Session)
