# Performance Test Topologies

This directory contains sample Hedgehog fabric topologies for HOSS performance testing and benchmarking.

**Related Documentation:**
- [RFC 0004: Performance Hardening](../../docs/rfcs/0004-performance-hardening.md)
- [Performance Tuning Runbook](../../docs/runbooks/performance-tuning.md)
- [Performance Thresholds](../../docs/performance-thresholds.json)
- [Issue #65: Performance Hardening](https://github.com/afewell-hh/hoss/issues/65)

---

## Overview

Performance topologies are used to:
- **Benchmark** HOSS validation performance across different fabric sizes
- **Detect regressions** in validation time and memory usage
- **Test scalability** for large enterprise deployments
- **Establish baselines** for capacity planning

All topologies are automatically tested nightly via the [perf-test workflow](../../.github/workflows/perf-test.yml).

---

## Topology Tiers

| Tier | File | Switches | Links | VPCs | Target Time | Target Memory | Purpose |
|------|------|----------|-------|------|-------------|---------------|---------|
| **Medium** | `topology-medium.yaml` | 20 | 50 | 2 | <5s | <200MB | Small enterprise fabric |
| **Large** | `topology-large.yaml` | 100 | 300 | 10 | <30s | <500MB | Large enterprise fabric |
| **XL** | `topology-xl.yaml` | 500 | 1500 | 50 | <120s | <1GB | Stress test (informational) |

**Notes:**
- Thresholds include 10% time tolerance and 20% memory tolerance
- XL tier failures are informational only and do not block CI
- All topologies enable strict validation mode (`# trigger strict`)

---

## Quick Start

### Validate a Performance Topology

```bash
# Medium tier (20 switches)
hossctl validate samples/perf/topology-medium.yaml

# Large tier (100 switches)
hossctl validate samples/perf/topology-large.yaml

# XL tier (500 switches - stress test)
hossctl validate samples/perf/topology-xl.yaml
```

### Run with Profiling

```bash
# Profile validation time and memory
/usr/bin/time -v hossctl validate samples/perf/topology-large.yaml 2>&1 | tee perf.log

# Extract metrics
grep "Maximum resident set size" perf.log  # Peak memory (KB)
grep "Elapsed" perf.log                    # Wall clock time
```

### Check Against Thresholds

```bash
# Run validation with performance measurement
HHFAB_MATRIX="samples/perf/topology-medium.yaml" \
  /usr/bin/time -v scripts/hhfab-validate.sh 2>&1 | tee perf.log

# Build performance report
# (extract metrics from perf.log and build JSON)

# Check thresholds
python3 scripts/check-perf-thresholds.py \
  --thresholds docs/performance-thresholds.json \
  --result .artifacts/perf-medium-result.json \
  --tier medium
```

---

## Topology Details

### Medium Tier (`topology-medium.yaml`)

**Scale:** 20 switches, 50 links, 2 VPCs

**Characteristics:**
- Typical small enterprise fabric
- 2 spine switches, 18 leaf switches
- Leaf-spine topology with 4 uplinks per leaf
- 2 VPCs for tenant isolation

**Performance Targets:**
- Validation time: <5 seconds
- Peak memory: <200MB
- Suitable for: Development, CI smoke tests

**Use Cases:**
- Quick validation during development
- CI pipeline smoke tests
- Baseline performance measurement

---

### Large Tier (`topology-large.yaml`)

**Scale:** 100 switches, 300 links, 10 VPCs

**Characteristics:**
- Large enterprise or multi-datacenter fabric
- 4 spine switches, 96 leaf switches
- Leaf-spine topology with 6 uplinks per leaf
- 10 VPCs for multi-tenant deployments

**Performance Targets:**
- Validation time: <30 seconds
- Peak memory: <500MB
- Suitable for: Production-scale testing

**Use Cases:**
- Performance regression testing
- Capacity planning for large deployments
- Nightly performance benchmarking

---

### XL Tier (`topology-xl.yaml`)

**Scale:** 500 switches, 1500 links, 50 VPCs

**Characteristics:**
- Stress test topology
- 8 spine switches, 492 leaf switches
- Leaf-spine topology with 8 uplinks per leaf
- 50 VPCs for extreme multi-tenancy

**Performance Targets:**
- Validation time: <120 seconds (2 minutes)
- Peak memory: <1GB
- Suitable for: Stress testing, breaking point identification

**Use Cases:**
- Identify performance bottlenecks
- Test resource limits
- Validate HOSS scalability claims

**Note:** XL tier failures are **informational only** and do not block CI. This tier is used to identify performance limits, not enforce them.

---

## Regenerating Topologies

Topologies are generated using the `scripts/generate-topology.sh` script:

```bash
# Regenerate medium tier
scripts/generate-topology.sh --tier medium --output samples/perf/topology-medium.yaml

# Regenerate large tier
scripts/generate-topology.sh --tier large --output samples/perf/topology-large.yaml

# Regenerate XL tier
scripts/generate-topology.sh --tier xl --output samples/perf/topology-xl.yaml
```

**When to regenerate:**
- Topology format changes (new hhfab version)
- Scale requirements change (add more switches/links)
- Bug fixes in topology generator

---

## Performance Testing Workflow

The [perf-test workflow](../../.github/workflows/perf-test.yml) runs nightly to test all performance tiers:

**Schedule:**
- Runs nightly at 04:00 UTC (after nightly review-kit)
- Can be manually triggered via workflow_dispatch

**What it does:**
1. Validates each performance tier (medium, large, xl)
2. Measures validation time and peak memory usage
3. Compares against thresholds with tolerance
4. Uploads performance reports as artifacts (retained 90 days)
5. Creates GitHub issue on failure (for medium/large tiers only)

**Artifacts:**
- `perf-report-medium-<run-id>` - Medium tier results + logs
- `perf-report-large-<run-id>` - Large tier results + logs
- `perf-report-xl-<run-id>` - XL tier results + logs

---

## Interpreting Results

Performance results are stored as JSON:

```json
{
  "tier": "medium",
  "topology": "samples/perf/topology-medium.yaml",
  "validationTimeMs": 3456,
  "peakMemoryKB": 148352,
  "validationStatus": "ok",
  "timestamp": "2025-10-13T12:00:00Z",
  "image": "ghcr.io/afewell-hh/hoss/hhfab@sha256:..."
}
```

**Key Metrics:**
- `validationTimeMs` - Total time including container startup
- `peakMemoryKB` - Peak RSS (Resident Set Size) from `/usr/bin/time -v`
- `validationStatus` - Validation result: `ok`, `failed`, or `error`

**Performance Pass Criteria:**
```
validationTimeMs ≤ threshold.maxTimeMs × 1.1  (10% tolerance)
peakMemoryMB ≤ threshold.maxMemoryMB × 1.2    (20% tolerance)
```

---

## Troubleshooting Performance Issues

See the [Performance Tuning Runbook](../../docs/runbooks/performance-tuning.md) for detailed troubleshooting guidance.

**Common Issues:**

| Symptom | Possible Cause | Resolution |
|---------|---------------|------------|
| Slow validation (>30s for large) | I/O bottleneck, container startup overhead | Use local SSD, pre-pull images |
| High memory (>500MB for large) | Memory leak, excessive concurrency | Reduce `HOSS_CONCURRENCY`, check for leaks |
| Slow aggregation (>1s for 100 targets) | jq performance, disk I/O | Use tmpfs for `.artifacts/`, optimize jq |

**Quick Profiling:**
```bash
# Profile medium tier locally
/usr/bin/time -v scripts/hhfab-validate.sh \
  samples/perf/topology-medium.yaml 2>&1 | tee perf.log

# Extract metrics
grep "Maximum resident set size" perf.log
grep "Elapsed" perf.log
```

---

## Best Practices

### For Developers

- **Run medium tier locally** before pushing changes
- **Check performance regression** if adding new validation logic
- **Profile with `/usr/bin/time -v`** to measure impact

### For CI/CD

- **Monitor nightly performance reports** for regressions
- **Investigate failures within 24 hours**
- **Update thresholds** only with justification (10+ data points)

### For Operators

- **Use medium tier** to estimate validation time for your fabric size
- **Extrapolate from large tier** for 100+ switch deployments
- **XL tier is informational** - don't use for production planning

---

## FAQ

**Q: Why are there only 3 tiers? What about 10-switch fabrics?**

A: Use the baseline `samples/topology-basic.yaml` for small fabrics (<10 switches). Medium tier is the smallest performance-tested tier.

**Q: Can I use these topologies for functional testing?**

A: These topologies are optimized for performance testing (size, scale). Use `samples/topology-basic.yaml` and `samples/topology-complex.yaml` for functional validation.

**Q: Why does XL tier not block CI?**

A: XL tier is a stress test to identify breaking points, not enforce performance. It's informational only to avoid flaky CI.

**Q: How are thresholds determined?**

A: Thresholds are based on 95th percentile of 10+ nightly runs on GitHub Actions runners (2 vCPU, 7GB RAM), plus tolerance factors.

**Q: Can I adjust thresholds?**

A: Yes, but only with justification. Submit a PR with updated thresholds and data supporting the change (10+ runs, 95th percentile calculation).

---

## References

- [RFC 0004: Performance Hardening](../../docs/rfcs/0004-performance-hardening.md)
- [Performance Tuning Runbook](../../docs/runbooks/performance-tuning.md)
- [Performance Thresholds Config](../../docs/performance-thresholds.json)
- [Performance Test Workflow](../../.github/workflows/perf-test.yml)
- [Issue #65: Performance Hardening](https://github.com/afewell-hh/hoss/issues/65)

---

**Last Updated:** 2025-10-13 (RFC 0004 implementation)
