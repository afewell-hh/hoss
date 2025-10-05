# HOSS App Pack v0.1

**Hedgehog Operational Support System** - Fabric topology validation for Hedgehog Open Network Fabric

## Overview

HOSS App Pack is a signed, portable bundle that installs on any Demon instance via `demonctl app install`. It provides fabric topology validation using the digest-pinned hhfab tool.

**Version:** 0.1.0
**License:** Apache-2.0
**Repository:** https://github.com/afewell-hh/hoss

## What's Included

- **Ritual:** `hoss-validate` - Validate Hedgehog fabric wiring diagrams
- **Contracts:** JSON Schema definitions for validation requests and results
- **Capsule:** Digest-pinned hhfab container (SHA256-verified)
- **UI Card:** Data-driven Operate card for validation results
- **CLI:** `hossctl` for interacting with HOSS rituals via Demon APIs

## Installation

### Prerequisites

- Demon platform ≥ 1.0
- `demonctl` CLI installed
- Access to Demon instance API endpoint

### Install the App Pack

```bash
# Install from local directory
demonctl app install ./app-pack

# Or install from URL (when published)
demonctl app install https://github.com/afewell-hh/hoss/releases/download/v0.1.0/hoss-app-pack-v0.1.0.tar.gz
```

### Verify Installation

```bash
# List installed apps
demonctl app list

# Expected output:
# NAME   VERSION   STATUS
# hoss   0.1.0     active
```

## Usage

### Using hossctl CLI

```bash
# Validate a wiring diagram
hossctl validate samples/topology-min.yaml

# Output (JSON envelope):
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
  "timestamp": "2025-10-05T12:34:56Z"
}

# Validate with strict mode (zero warnings allowed)
hossctl validate --strict samples/topology-min.yaml
```

### Using Demon Ritual API Directly

```bash
# Start validation ritual
curl -X POST $DEMON_URL/api/v1/rituals/hoss-validate/runs \
  -H "Content-Type: application/json" \
  -d '{
    "input": {
      "diagramPath": "samples/topology-min.yaml"
    }
  }'

# Response:
{
  "runId": "run-abc123",
  "status": "running",
  "ritual": "hoss-validate"
}

# Check run status
curl $DEMON_URL/api/v1/runs/run-abc123

# Get result envelope
curl $DEMON_URL/api/v1/runs/run-abc123/envelope
```

### View Results in Operate UI

1. Navigate to Demon Operate UI: `http://<demon-instance>/operate`
2. Find the **HOSS Validation** card
3. View validation results with status, counts, and tool information

## Configuration

### Environment Variables (hossctl)

- `DEMON_URL` - Demon API endpoint (default: `http://localhost:8080`)
- `DEMON_TOKEN` - Authentication token (if required)

### App Pack Compatibility

This app pack requires:
- **App Pack Schema:** `>=1.0,<2.0`
- **Platform API:** `>=1.0,<2.0`

Check compatibility before installation:
```bash
demonctl version --app-pack-schema
```

## Security

### Image Signing

All container images are digest-pinned and signed with cosign:

```bash
# Verify hhfab image signature
cosign verify ghcr.io/afewell-hh/hoss/hhfab@sha256:54814bbf4e8459cfb35c7cf8872546f0d5d54da9fc317ffb53eab0e137b21d7b \
  --certificate-identity-regexp="^https://github.com/.+/.+@" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

### Sandbox Enforcement

The hhfab capsule runs with strict security constraints:
- No network access (`--network=none`)
- Read-only filesystem
- Writable `/tmp` only (tmpfs)
- Non-root user
- No privilege escalation (`--security-opt=no-new-privileges`)

## Contracts

### validate.request

Input contract for validation ritual:

```json
{
  "diagramPath": "path/to/wiring-diagram.yaml",
  "strict": false,
  "fabConfigPath": "path/to/fab.yaml"
}
```

**Fields:**
- `diagramPath` (required): Path to wiring diagram YAML
- `strict` (optional): Enable strict mode (default: false)
- `fabConfigPath` (optional): Path to fab.yaml configuration

**Schema:** `contracts/hoss/validate.request.json`

### validate.result

Result envelope from validation ritual:

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
  "timestamp": "2025-10-05T12:34:56Z",
  "matrix": ["samples/topology-min.yaml"],
  "errors": []
}
```

**Schema:** `contracts/hoss/validate.result.json`

## Uninstallation

```bash
# Uninstall the app pack
demonctl app uninstall hoss

# Verify removal
demonctl app list
```

All rituals, contracts, and UI registrations will be removed.

## Development

### Building the App Pack

```bash
# From repository root
make app-pack-build

# Output: .artifacts/hoss-app-pack-v0.1.0.tar.gz
```

### Signing

```bash
# Sign the app pack with cosign
make app-pack-sign

# Verify signature
cosign verify-blob \
  --signature .artifacts/hoss-app-pack-v0.1.0.tar.gz.sig \
  --certificate-identity-regexp="^https://github.com/.+/.+@" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com \
  .artifacts/hoss-app-pack-v0.1.0.tar.gz
```

### Local Testing

```bash
# Install on local Demon instance
demonctl app install ./app-pack

# Run validation
hossctl validate samples/topology-min.yaml

# Check logs
demonctl logs ritual/hoss-validate

# Uninstall
demonctl app uninstall hoss
```

## CI/CD

Automated CI pipeline validates the app pack:
1. Schema validation
2. Contract validation
3. Install on ephemeral Demon instance
4. Run sample validation
5. Assert envelope validity (warnings=0, failures=0)
6. Uninstall test

**Workflow:** `.github/workflows/app-pack-build.yml`

## Troubleshooting

### Installation Fails

**Error:** `App Pack schema version mismatch`

**Solution:** Check Demon platform version compatibility:
```bash
demonctl version --app-pack-schema
# Expected: 1.x.x
```

### Validation Fails

**Error:** `Envelope not found at /workspace/.artifacts/summary.json`

**Solution:** Check capsule logs:
```bash
demonctl logs capsule/hhfab --run-id <run-id>
```

### hossctl Connection Refused

**Error:** `connection refused: http://localhost:8080`

**Solution:** Set correct `DEMON_URL`:
```bash
export DEMON_URL=http://your-demon-instance:8080
hossctl validate samples/topology-min.yaml
```

## References

- [Demon App Pack Documentation](https://github.com/afewell-hh/Demon/tree/main/docs/app-packs)
- [HOSS Repository](https://github.com/afewell-hh/hoss)
- [Hedgehog Open Network Fabric](https://docs.githedgehog.com)
- [hhfab Tool](https://github.com/githedgehog/fabricator)

## Support

- **Issues:** https://github.com/afewell-hh/hoss/issues
- **Discussions:** https://github.com/afewell-hh/hoss/discussions

## License

Apache-2.0 - See [LICENSE](../LICENSE) file for details.
