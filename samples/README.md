# HOSS Sample Topology Files

This directory contains example topology files for testing HOSS validation.

## Available Samples

### topology-min.yaml
Minimal topology configuration for triggering strict validation.
- **Purpose**: CI/CD testing trigger
- **Complexity**: Minimal
- **Use case**: Automated testing

### topology-basic.yaml
Basic fabric topology example for simple deployments.
- **Purpose**: Getting started and basic validation testing
- **Complexity**: Low
- **Use case**: Small single-spine deployments, learning, development

### topology-complex.yaml
Complex fabric topology with multiple switches and connections.
- **Purpose**: Realistic deployment validation testing
- **Complexity**: High
- **Use case**: Multi-spine deployments, integration testing, production validation

## Using Sample Files

### With HOSS App Pack

```bash
# Install HOSS
tar -xzf hoss-app-pack-v0.1.0.tar.gz
DEMON_APP_HOME=/tmp/app-home demonctl app install ./app-pack

# Run validation (samples are included in app-pack)
DEMON_DEBUG=1 DEMON_APP_HOME=/tmp/app-home DEMON_CONTAINER_USER=$(id -u):$(id -g) \
  demonctl run hoss:hoss-validate
```

### With Review Kit (Developers)

```bash
# Run smoke-local validation on all samples
make review-kit

# Run strict validation with digest-pinned image
export HHFAB_IMAGE_DIGEST="ghcr.io/afewell-hh/hoss/hhfab@sha256:..."
make review-kit-strict
```

## Adding Custom Topologies

To test your own topology files:

1. Place your `.yaml` file in this directory
2. Add the file path to `.github/review-kit/matrix.txt`
3. Run local validation: `make review-kit`
4. Submit a PR to run CI validation

## Validation Expectations

All sample files in this directory should:
- ✅ Pass HOSS strict validation (zero warnings, zero failures)
- ✅ Use valid Hedgehog fabric topology schema
- ✅ Include descriptive comments
- ✅ Be representative of real-world use cases

## Creating Invalid Samples

For testing error detection, place invalid topology files in `samples/invalid/`:
- These files **should** fail validation
- Used for testing HOSS error reporting
- Include comments explaining the intended error

## Support

For questions about topology syntax or validation errors:
- Review the main [README.md](../README.md)
- Check [docs/quickstart.md](../docs/quickstart.md)
- Open an issue at https://github.com/afewell-hh/hoss/issues
