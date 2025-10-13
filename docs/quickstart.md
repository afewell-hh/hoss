# HOSS Quickstart Guide

Get up and running with HOSS topology validation in 5 minutes.

## Prerequisites

Before you begin, ensure you have:

- **Demon platform** (demonctl 0.0.1+) - [Installation guide](https://github.com/githedgehog/demon)
- **cosign** (optional but recommended) - [Installation guide](https://docs.sigstore.dev/cosign/installation/)
- **jq** (for viewing results) - `apt install jq` or `brew install jq`

## Step 1: Download HOSS v0.1.0

Download the signed app-pack from the latest release:

```bash
wget https://github.com/afewell-hh/hoss/releases/download/v0.1.0/hoss-app-pack-v0.1.0.tar.gz
wget https://github.com/afewell-hh/hoss/releases/download/v0.1.0/hoss-app-pack-v0.1.0.tar.gz.bundle
```

## Step 2: Verify the Signature (Recommended)

Verify the app-pack was signed by the HOSS CI system:

```bash
cosign verify-blob hoss-app-pack-v0.1.0.tar.gz \
  --bundle hoss-app-pack-v0.1.0.tar.gz.bundle \
  --certificate-identity-regexp="^https://github.com/afewell-hh/.+@" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

You should see `Verified OK` if the signature is valid.

## Step 3: Extract and Install

Extract the app-pack and install it with Demon:

```bash
# Extract the app-pack
tar -xzf hoss-app-pack-v0.1.0.tar.gz

# Install with Demon
DEMON_APP_HOME=/tmp/app-home demonctl app install ./app-pack
```

## Step 4: Run Your First Validation

Run a validation against a basic topology:

```bash
# Run validation
DEMON_DEBUG=1 DEMON_APP_HOME=/tmp/app-home DEMON_CONTAINER_USER=$(id -u):$(id -g) \
  demonctl run hoss:hoss-validate
```

## Step 5: View the Results

Check the validation results:

```bash
# View formatted results
cat result.json | jq .

# Check validation status
cat result.json | jq '.validated'

# View any warnings or failures
cat result.json | jq '.warnings, .failures'
```

## Example: Validating a Sample Topology

HOSS includes sample topology files for testing:

```bash
# Clone the repository to get samples
git clone https://github.com/afewell-hh/hoss
cd hoss/samples

# View available samples
ls -la *.yaml

# Run validation against a sample (requires additional setup)
# See the full documentation for integrating custom topologies
```

## Understanding the Results

The `result.json` file contains:

- **`validated`**: Number of successfully validated topologies
- **`warnings`**: Non-critical issues found
- **`failures`**: Critical validation failures
- **`status`**: Overall validation status (`ok`, `warning`, or `error`)

Example successful result:

```json
{
  "validated": 1,
  "warnings": 0,
  "failures": 0,
  "status": "ok"
}
```

## Troubleshooting

### Demon workspace mount issues

If you encounter workspace mount errors, ensure you're using:
- Demon with the workspace mount fix (SHA `52884c7b` or later)
- demonctl version 0.0.1 or later

### Permission errors

Ensure `DEMON_CONTAINER_USER` matches your user:

```bash
DEMON_CONTAINER_USER=$(id -u):$(id -g)
```

### Signature verification fails

If cosign verification fails:
1. Ensure you're using cosign v2.0+
2. Check your network connection (verification requires internet access)
3. Verify you downloaded the correct `.bundle` file

## Next Steps

- **Read the documentation**: See [GA-CHECKLIST.md](GA-CHECKLIST.md) for GA readiness details
- **Explore samples**: Check [samples/](../samples/) for example topology files
- **Run review-kit**: See the main README for developer validation workflows
- **Report issues**: Open an issue at https://github.com/afewell-hh/hoss/issues

## Support

For support:
1. Check [docs/support.md](support.md) for troubleshooting guides
2. Review existing issues at https://github.com/afewell-hh/hoss/issues
3. Open a new issue using the bug report template

---

**HOSS v0.1.0** - Hedgehog Operational Support System
