# HOSS Support Runbook

This guide helps you collect diagnostics and troubleshoot HOSS validation issues.

## Quick Diagnostic Collection

When reporting issues, collect these essential diagnostics:

### 1. Result Envelope

```bash
# The result.json file contains validation results
cat result.json | jq .

# Check validation status
jq '.validated, .warnings, .failures, .status' result.json
```

### 2. Artifacts Tree

```bash
# List all generated artifacts
tree .artifacts/

# Or if tree is not available:
find .artifacts/ -type f -ls
```

### 3. HOSS Environment

```bash
# Get demonctl version
demonctl --version

# Get Demon commit SHA
cd /path/to/demon
git rev-parse HEAD

# Get HHFAB digest from app-pack
grep -A5 "hhfab" app-pack/app-pack.yaml
```

### 4. CLI Logs

```bash
# Run with debug output
DEMON_DEBUG=1 DEMON_APP_HOME=/tmp/app-home DEMON_CONTAINER_USER=$(id -u):$(id -g) \
  demonctl run hoss:hoss-validate 2>&1 | tee hoss-debug.log
```

## Minimal Reproduction

To help diagnose issues, try reproducing with the basic sample:

```bash
# 1. Install HOSS v0.1.0
wget https://github.com/afewell-hh/hoss/releases/download/v0.1.0/hoss-app-pack-v0.1.0.tar.gz
tar -xzf hoss-app-pack-v0.1.0.tar.gz
DEMON_APP_HOME=/tmp/app-home demonctl app install ./app-pack

# 2. Run validation with basic sample
cd /path/to/hoss/samples
DEMON_DEBUG=1 DEMON_APP_HOME=/tmp/app-home DEMON_CONTAINER_USER=$(id -u):$(id -g) \
  demonctl run hoss:hoss-validate 2>&1 | tee validation.log

# 3. Collect outputs
ls -la result.json .artifacts/
cat result.json
```

## Common Issues

### Issue: "Workspace mount not found"

**Symptoms:**
- Error mentions "file not found" or "workspace" in logs
- result.json missing or empty

**Diagnosis:**
```bash
# Check Demon version
demonctl --version
# Should be 0.0.1 or later

# Check Demon SHA
cd /path/to/demon && git rev-parse HEAD
# Should be 52884c7b or later (includes workspace mount fix)
```

**Resolution:**
- Update Demon to version 0.0.1+ with workspace mount fix
- See: https://github.com/githedgehog/demon/pull/267

### Issue: Permission Errors

**Symptoms:**
- "Permission denied" errors
- Container cannot write to .artifacts/

**Diagnosis:**
```bash
# Check current user ID
id -u
id -g

# Check DEMON_CONTAINER_USER setting
echo $DEMON_CONTAINER_USER
```

**Resolution:**
```bash
# Set container user to match your user
export DEMON_CONTAINER_USER=$(id -u):$(id -g)

# Verify .artifacts/ permissions
ls -ld .artifacts/
# Should be owned by your user
```

### Issue: Signature Verification Fails

**Symptoms:**
- cosign verify-blob fails
- "certificate identity does not match" errors

**Diagnosis:**
```bash
# Check cosign version
cosign version
# Should be v2.0+

# Verify bundle file exists
ls -lh hoss-app-pack-v0.1.0.tar.gz.bundle
```

**Resolution:**
```bash
# Ensure correct cosign command
cosign verify-blob hoss-app-pack-v0.1.0.tar.gz \
  --bundle hoss-app-pack-v0.1.0.tar.gz.bundle \
  --certificate-identity-regexp="^https://github.com/afewell-hh/.+@" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com

# If still failing, re-download the bundle
wget https://github.com/afewell-hh/hoss/releases/download/v0.1.0/hoss-app-pack-v0.1.0.tar.gz.bundle --force
```

### Issue: Validation Takes Too Long

**Symptoms:**
- Validation hangs or takes minutes
- No progress output

**Diagnosis:**
```bash
# Check if HHFAB container is running
docker ps | grep hhfab

# Check Docker logs
docker logs $(docker ps -q | head -1)
```

**Resolution:**
- Kill hung containers: `docker kill $(docker ps -q)`
- Clear Docker cache: `docker system prune -f`
- Re-run with DEMON_DEBUG=1 for visibility

## Diagnostic Package

Create a complete diagnostic package for support:

```bash
#!/bin/bash
# collect-diagnostics.sh

DIAG_DIR="hoss-diagnostics-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DIAG_DIR"

echo "Collecting HOSS diagnostics..."

# Environment
echo "=== Environment ===" > "$DIAG_DIR/environment.txt"
demonctl --version >> "$DIAG_DIR/environment.txt" 2>&1
echo "" >> "$DIAG_DIR/environment.txt"
echo "Demon SHA: $(cd /path/to/demon && git rev-parse HEAD 2>/dev/null || echo 'not available')" >> "$DIAG_DIR/environment.txt"
echo "HHFAB digest: $(grep -A5 hhfab app-pack/app-pack.yaml | grep digest || echo 'not found')" >> "$DIAG_DIR/environment.txt"
echo "Platform: $(uname -a)" >> "$DIAG_DIR/environment.txt"
echo "Docker: $(docker --version)" >> "$DIAG_DIR/environment.txt"

# Result envelope
if [[ -f result.json ]]; then
  cp result.json "$DIAG_DIR/"
else
  echo "result.json not found" > "$DIAG_DIR/result.json.missing"
fi

# Artifacts
if [[ -d .artifacts ]]; then
  cp -r .artifacts "$DIAG_DIR/"
else
  echo "No .artifacts directory" > "$DIAG_DIR/artifacts.missing"
fi

# Logs (if available)
if [[ -f hoss-debug.log ]]; then
  cp hoss-debug.log "$DIAG_DIR/"
fi

# Package it
tar -czf "${DIAG_DIR}.tar.gz" "$DIAG_DIR"
echo "Diagnostic package created: ${DIAG_DIR}.tar.gz"
echo "Please attach this file when opening a support issue."
```

## Privacy and Security

**⚠️ Important**: Before sharing diagnostics:

### DO NOT Include:
- Credentials or API keys
- Internal hostnames or IP addresses
- Proprietary topology configurations
- Customer-specific data

### DO Redact:
```bash
# Redact sensitive fields from result.json
jq 'del(.topology.internal, .metadata.customer)' result.json > result-redacted.json

# Replace IP addresses
sed 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/REDACTED/g' logs.txt > logs-redacted.txt
```

### Safe to Share:
- result.json (validation status, counts, errors)
- demonctl version and Demon SHA
- HHFAB version/digest
- Error messages and stack traces
- Directory structure (.artifacts/ tree)

## Opening a Support Issue

1. **Collect diagnostics** using the script above
2. **Redact sensitive information**
3. **Try minimal reproduction** with samples/topology-basic.yaml
4. **Open issue** at https://github.com/afewell-hh/hoss/issues/new/choose
5. **Use bug report template** and fill all required fields
6. **Attach** diagnostic package (redacted)

## Getting Help

- **Documentation**: [README.md](../../README.md)
- **Quickstart**: [docs/quickstart.md](../quickstart.md)
- **Bug Reports**: Use [bug report template](https://github.com/afewell-hh/hoss/issues/new?template=bug_report.md)
- **Feature Requests**: Use [feature request template](https://github.com/afewell-hh/hoss/issues/new?template=feature_request.md)
- **Review Kit Issues**: [docs/runbooks/review-kit.md](review-kit.md)

## References

- **v0.1.0 Release**: https://github.com/afewell-hh/hoss/releases/tag/v0.1.0
- **GA Checklist**: [docs/GA-CHECKLIST.md](../GA-CHECKLIST.md)
- **Demon Platform**: https://github.com/githedgehog/demon
- **HHFAB Tool**: Documentation TBD

---

**Last Updated**: 2025-10-13 (v0.1.0 GA)
