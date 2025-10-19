# hoss

[![review-kit (smoke-local)](https://github.com/afewell-hh/hoss/actions/workflows/review-kit.yml/badge.svg?job=smoke-local)](https://github.com/afewell-hh/hoss/actions/workflows/review-kit.yml)
[![review-kit (strict)](https://github.com/afewell-hh/hoss/actions/workflows/review-kit.yml/badge.svg?job=review-kit%20%28strict%29)](https://github.com/afewell-hh/hoss/actions/workflows/review-kit.yml)
[![actionlint](https://github.com/afewell-hh/hoss/actions/workflows/actionlint.yml/badge.svg)](https://github.com/afewell-hh/hoss/actions/workflows/actionlint.yml)

**Hedgehog Operational Support System** - Fabric topology validation for Hedgehog Open Network Fabric.

## 🎉 v0.2.0 Generally Available

HOSS v0.2.0 is now generally available with multi-topology aggregation, streaming validation, and enhanced metadata:

- ✅ **Multi-topology validation** with parallel execution (RFC 0001)
- ✅ **hossctl CLI** with SSE streaming support (RFC 0003)
- ✅ **Enhanced metadata** fields: tool.gitSha, matrix.details, execution context (RFC 0002)
- ✅ **Performance hardening** with threshold testing (RFC 0004)
- 🔐 Cosign OIDC keyless signing for all releases
- ✅ **Fully backward compatible** with v0.1.0

**[Download v0.2.0](https://github.com/afewell-hh/hoss/releases/tag/v0.2.0)** | **[Release Notes](https://github.com/afewell-hh/hoss/releases/tag/v0.2.0)** | **[Upgrade from v0.1.0](docs/UPGRADE-v0.1.0-to-v0.2.0-rc1.md)** | **[Getting Started](#getting-started)**

---

## Previous Releases

- **v0.1.0** - [Download](https://github.com/afewell-hh/hoss/releases/tag/v0.1.0) | [Release Notes](https://github.com/afewell-hh/hoss/releases/tag/v0.1.0)
- **v0.2.0-rc1** - [Download](https://github.com/afewell-hh/hoss/releases/tag/v0.2.0-rc1) | [RC1 Checklist](docs/v0.2.0-rc1-checklist.md)

## Getting Started

Get up and running with HOSS in 5 minutes:

### Prerequisites

- [Demon platform](https://github.com/githedgehog/demon) with demonctl 0.0.1+
- [cosign](https://docs.sigstore.dev/cosign/installation/) for signature verification (optional but recommended)

### Quick Start

```bash
# 1. Download and verify the release
wget https://github.com/afewell-hh/hoss/releases/download/v0.2.0/hoss-app-pack-v0.2.0.tar.gz
wget https://github.com/afewell-hh/hoss/releases/download/v0.2.0/hoss-app-pack-v0.2.0.tar.gz.bundle

cosign verify-blob hoss-app-pack-v0.2.0.tar.gz \
  --bundle hoss-app-pack-v0.2.0.tar.gz.bundle \
  --certificate-identity-regexp="^https://github.com/afewell-hh/.+@" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com

# 2. Extract and install
tar -xzf hoss-app-pack-v0.2.0.tar.gz
DEMON_APP_HOME=/tmp/app-home demonctl app install ./app-pack

# 3. Run your first validation
DEMON_DEBUG=1 DEMON_APP_HOME=/tmp/app-home DEMON_CONTAINER_USER=$(id -u):$(id -g) \
  demonctl run hoss:hoss-validate

# 4. Check the results
cat result.json | jq .
```

**Next steps:**
- See [Installation](#installation) for alternative installation methods
- Read [docs/quickstart.md](docs/quickstart.md) for detailed examples
- Check [samples/](samples/) for example topology files

## Installation

### Install from Release (Recommended)

Download and install the latest release:

```bash
# Download latest release
wget https://github.com/afewell-hh/hoss/releases/download/v0.2.0/hoss-app-pack-v0.2.0.tar.gz
tar -xzf hoss-app-pack-v0.2.0.tar.gz

# Install with Demon
DEMON_APP_HOME=/tmp/app-home demonctl app install ./app-pack

# Run validation (single topology)
DEMON_DEBUG=1 DEMON_APP_HOME=/tmp/app-home DEMON_CONTAINER_USER=1000:1000 \
  demonctl run hoss:hoss-validate

# Run validation (multi-topology with parallel execution)
export HHFAB_MATRIX="topology-1.yaml,topology-2.yaml,topology-3.yaml"
export HOSS_CONCURRENCY=4
DEMON_DEBUG=1 DEMON_APP_HOME=/tmp/app-home DEMON_CONTAINER_USER=1000:1000 \
  demonctl run hoss:hoss-validate
```

### Verify Signature

Verify the app-pack signature with cosign:

```bash
# Download signature bundle
wget https://github.com/afewell-hh/hoss/releases/download/v0.2.0/hoss-app-pack-v0.2.0.tar.gz.bundle

# Verify with cosign
cosign verify-blob hoss-app-pack-v0.2.0.tar.gz \
  --bundle hoss-app-pack-v0.2.0.tar.gz.bundle \
  --certificate-identity-regexp="^https://github.com/afewell-hh/.+@" \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

### Install from Source

```bash
git clone https://github.com/afewell-hh/hoss
cd hoss
make app-pack-build
DEMON_APP_HOME=/tmp/app-home demonctl app install ./app-pack
```

## Review Kit

**Strict validation** with digest-pinned hhfab container, zero-warning enforcement, and comprehensive security hardening.

**Quick start:**
```bash
# Run smoke-local validation
make review-kit

# Run strict validation (requires digest-pinned image)
HHFAB_IMAGE_DIGEST="ghcr.io/afewell-hh/hoss/hhfab@sha256:..." make review-kit-strict
```

### Reproduce Strict Validation Locally

Run the exact same container-based validation that CI uses:

```bash
# Set the digest variable (get current value from repo vars)
export HHFAB_IMAGE_DIGEST="ghcr.io/afewell-hh/hoss/hhfab@sha256:54814bbf4e8459cfb35c7cf8872546f0d5d54da9fc317ffb53eab0e137b21d7b"

# Run validation in isolated container
docker run --rm \
  --network=none \
  --read-only \
  --tmpfs /tmp:rw \
  -e TMPDIR=/tmp \
  -e HHFAB_CACHE_DIR=/tmp/.hhfab-cache \
  -e HHFAB_MATRIX="$(cat .github/review-kit/matrix.txt)" \
  -v "$PWD:/workspace:ro" \
  -v "$PWD/.artifacts:/workspace/.artifacts" \
  -w /workspace \
  "$HHFAB_IMAGE_DIGEST" \
  'scripts/hhfab-validate.sh'

# Check results (smoke mode writes to summary-smoke-<id>.json)
cat .artifacts/review-kit/summary-smoke-latest.json | jq .
```

### How to Rotate the hhfab Digest

See the [Review Kit Runbook](docs/runbooks/review-kit.md) for complete operational procedures:

- **Digest rotation** (rebuild & update `HHFAB_IMAGE_DIGEST` variable)
- **Failure triage** (how to get summary artifacts, common causes)
- **Minimum version policy** (currently: `v0.4.0`)
- **Branch protection** (required checks configuration)
- **Matrix management** (adding/removing validation targets)

**Quick digest rotation:**
```bash
docker build -f Dockerfile.tools.hhfab -t ghcr.io/afewell-hh/hoss/hhfab:latest .
docker push ghcr.io/afewell-hh/hoss/hhfab:latest
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/afewell-hh/hoss/hhfab:latest)
gh api -X PATCH "/repos/afewell-hh/hoss/actions/variables/HHFAB_IMAGE_DIGEST" -f value="$DIGEST"
gh workflow run review-kit.yml --ref main
```

## Workflow Details

### smoke-local
Best-effort validation using any available hhfab binary on the runner. Allowed to fail without blocking CI. Emits `.artifacts/review-kit/summary-smoke-<run>.json` (and updates `summary-smoke-latest.json`) for diagnostics.

### review-kit (strict)
Digest-pinned, network-isolated, read-only container validation with comprehensive enforcement gates:
- ✅ Status must be `"ok"`
- ✅ hhfab version ≥ v0.4.0
- ✅ Warning budget: 0 (strict)
- ✅ Validated targets > 0
- ✅ All required summary fields present

**Security hardening:**
- `--network=none` (no network access)
- `--read-only` (immutable filesystem)
- `--security-opt=no-new-privileges`
- `--user "$(id -u):$(id -g)"` (non-root)
- tmpfs for `/tmp` only

## Performance Testing

HOSS includes automated performance testing to detect regressions and establish scaling characteristics. Performance tests run nightly and measure validation time and memory usage across multiple topology sizes.

**Quick start:**
```bash
# Test medium tier (20 switches)
hossctl validate samples/perf/topology-medium.yaml

# Profile validation performance
/usr/bin/time -v hossctl validate samples/perf/topology-large.yaml 2>&1 | tee perf.log
```

### Performance Tiers

| Tier | Switches | Links | VPCs | Target Time | Target Memory | Purpose |
|------|----------|-------|------|-------------|---------------|---------|
| Medium | 20 | 50 | 2 | <5s | <200MB | Small enterprise |
| Large | 100 | 300 | 10 | <30s | <500MB | Large enterprise |
| XL | 500 | 1500 | 50 | <120s | <1GB | Stress test |

**Nightly Testing:**
- Runs at 04:00 UTC via [perf-test workflow](.github/workflows/perf-test.yml)
- Tests all tiers with digest-pinned hhfab container
- Compares against thresholds (10% time tolerance, 20% memory tolerance)
- Creates GitHub issue on regression (medium/large tiers only)
- Retains performance reports for 90 days

**Resources:**
- [Performance Test Topologies](samples/perf/) - Sample topologies for benchmarking
- [Performance Tuning Runbook](docs/runbooks/performance-tuning.md) - Profiling and troubleshooting guide
- [Performance Thresholds](docs/performance-thresholds.json) - Threshold configuration
- [RFC 0004: Performance Hardening](docs/rfcs/0004-performance-hardening.md) - Design and implementation details

## Contributing

1. Add sample files to `.github/review-kit/matrix.txt`
2. Ensure smoke-local passes locally: `bash scripts/hhfab-validate.sh`
3. Submit PR; strict validation will run automatically
4. All enforcement gates must pass before merge

## Getting Help

- **Quickstart Guide**: [docs/quickstart.md](docs/quickstart.md)
- **Support Runbook**: [docs/runbooks/support.md](docs/runbooks/support.md) - Troubleshooting and diagnostics collection
- **Bug Reports**: [Open an issue](https://github.com/afewell-hh/hoss/issues/new?template=bug_report.md)
- **Feature Requests**: [Request a feature](https://github.com/afewell-hh/hoss/issues/new?template=feature_request.md)
- **Review Kit Issues**: [docs/runbooks/review-kit.md](docs/runbooks/review-kit.md)

## License

See LICENSE file for details.
