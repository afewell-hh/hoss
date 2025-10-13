# RFC 0004: Performance Hardening for Large Topology Matrices

**Status:** Draft
**Issue:** [#65](https://github.com/afewell-hh/hoss/issues/65)
**Author:** HOSS Team
**Created:** 2025-10-13
**Updated:** 2025-10-13

## Summary

Establish performance testing infrastructure, baseline thresholds, and profiling capabilities for validating large fabric topologies (100+ switches, 1000+ links). This ensures HOSS scales to production workloads and provides early detection of performance regressions.

## Motivation

**Current State (v0.1.0):**

- Performance baseline based on small sample topologies (2-3 switches)
- No large topology samples for testing
- No automated performance testing in CI
- No guidance on performance limits or scaling characteristics

**Known Metrics (v0.1.0 GA):**
- Review-kit validation: 20-30 seconds for 2-3 small topologies
- Memory usage: <100MB per validation
- CPU: Single-core, minimal usage

**Unknown Performance Characteristics:**
- How does validation time scale with topology size (10x, 100x)?
- What is the memory footprint for 100-switch fabrics?
- Are there performance bottlenecks in hhfab or capsule scripts?
- What are acceptable performance thresholds?

**User Pain Points:**
1. **Large Fabric Operators:** "Will HOSS handle our 500-switch production fabric?"
2. **Performance Engineers:** "How do we know if a PR introduces performance regression?"
3. **Capacity Planning:** "How many concurrent validations can our CI runners handle?"

## Design

### Sample Topology Tiers

Create realistic sample topologies across multiple size tiers:

#### Tier 1: Small (Baseline - Already Exists)
- **File:** `samples/topology-basic.yaml`
- **Scale:** 2-5 switches, 10-20 links
- **Target:** <3s validation, <100MB memory
- **Purpose:** Quick smoke test, v0.1.0 compatibility

#### Tier 2: Medium (New)
- **File:** `samples/perf/topology-medium.yaml`
- **Scale:** 20 switches, 50 links, 2 VPCs
- **Target:** <5s validation, <200MB memory
- **Purpose:** Typical small enterprise fabric

#### Tier 3: Large (New)
- **File:** `samples/perf/topology-large.yaml`
- **Scale:** 100 switches, 300 links, 10 VPCs
- **Target:** <30s validation, <500MB memory
- **Purpose:** Large enterprise or multi-datacenter fabric

#### Tier 4: Extra-Large (New - Stress Test)
- **File:** `samples/perf/topology-xl.yaml`
- **Scale:** 500 switches, 1500 links, 50 VPCs
- **Target:** <120s validation, <1GB memory
- **Purpose:** Stress test, identify breaking points

### Performance Test Workflow

**New Workflow:** `.github/workflows/perf-test.yml`

```yaml
name: Performance Testing

on:
  schedule:
    # Run nightly at 04:00 UTC (after nightly GA validation)
    - cron: '0 4 * * *'
  workflow_dispatch:
    inputs:
      topology_tier:
        description: 'Topology tier to test'
        required: false
        default: 'all'
        type: choice
        options:
          - all
          - medium
          - large
          - xl

env:
  HHFAB_IMAGE_DIGEST: ${{ vars.HHFAB_IMAGE_DIGEST }}

jobs:
  perf-test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        tier: [medium, large, xl]

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Generate topology sample
        run: |
          # Generate topology using script (parameterized)
          scripts/generate-topology.sh --tier ${{ matrix.tier }} \
            --output samples/perf/topology-${{ matrix.tier }}.yaml

      - name: Run validation with profiling
        run: |
          START_TIME=$(date +%s%3N)

          # Run with time profiling
          /usr/bin/time -v docker run --rm \
            --network=none \
            --read-only \
            --tmpfs /tmp:rw \
            --memory 2g \
            --cpus 2 \
            -v "$PWD:/workspace:ro" \
            -v "$PWD/.artifacts:/workspace/.artifacts" \
            -w /workspace \
            "$HHFAB_IMAGE_DIGEST" \
            "scripts/hoss-validate.sh" \
            2>&1 | tee perf-${{ matrix.tier }}.log

          END_TIME=$(date +%s%3N)
          VALIDATION_TIME=$((END_TIME - START_TIME))

          # Extract memory metrics from /usr/bin/time output
          PEAK_MEMORY=$(grep "Maximum resident set size" perf-${{ matrix.tier }}.log | awk '{print $6}')

          # Build performance report
          jq -n \
            --arg tier "${{ matrix.tier }}" \
            --arg topology "samples/perf/topology-${{ matrix.tier }}.yaml" \
            --argjson time "$VALIDATION_TIME" \
            --argjson memory "$PEAK_MEMORY" \
            '{
              tier: $tier,
              topology: $topology,
              validationTimeMs: $time,
              peakMemoryKB: $memory
            }' > .artifacts/perf-${{ matrix.tier }}-result.json

      - name: Check thresholds
        run: |
          # Load thresholds from config
          THRESHOLD_FILE="docs/performance-thresholds.json"
          RESULT_FILE=".artifacts/perf-${{ matrix.tier }}-result.json"

          # Compare against thresholds
          python3 scripts/check-perf-thresholds.py \
            --thresholds "$THRESHOLD_FILE" \
            --result "$RESULT_FILE" \
            --tier "${{ matrix.tier }}"

      - name: Upload performance report
        uses: actions/upload-artifact@v4
        with:
          name: perf-report-${{ matrix.tier }}
          path: .artifacts/perf-${{ matrix.tier }}-result.json
          retention-days: 90

      - name: Post results to issue
        if: always()
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          RESULT=$(cat .artifacts/perf-${{ matrix.tier }}-result.json)
          gh issue comment 65 --body "**Performance Test Result (${{ matrix.tier }}):**
          \`\`\`json
          $RESULT
          \`\`\`
          Workflow: ${{ github.server_url }}/${{ github.repository }}/actions/runs/${{ github.run_id }}"
```

### Performance Thresholds

**Configuration File:** `docs/performance-thresholds.json`

```json
{
  "version": "1.0",
  "updated": "2025-10-13",
  "thresholds": {
    "small": {
      "maxTimeMs": 3000,
      "maxMemoryMB": 100,
      "description": "Baseline - 2-5 switches"
    },
    "medium": {
      "maxTimeMs": 5000,
      "maxMemoryMB": 200,
      "description": "Small enterprise - 20 switches"
    },
    "large": {
      "maxTimeMs": 30000,
      "maxMemoryMB": 500,
      "description": "Large enterprise - 100 switches"
    },
    "xl": {
      "maxTimeMs": 120000,
      "maxMemoryMB": 1024,
      "description": "Stress test - 500 switches"
    }
  },
  "tolerances": {
    "time": 1.1,
    "memory": 1.2
  },
  "notes": [
    "Thresholds are conservative estimates based on CI runner specs (2 vCPU, 7GB RAM)",
    "Tolerance factors allow 10% time variance, 20% memory variance",
    "XL tier is stress test - failures are informational, not blocking"
  ]
}
```

### Threshold Checking Script

**New Script:** `scripts/check-perf-thresholds.py`

```python
#!/usr/bin/env python3
import argparse
import json
import sys

def check_thresholds(thresholds_file, result_file, tier):
    # Load thresholds
    with open(thresholds_file) as f:
        config = json.load(f)

    # Load result
    with open(result_file) as f:
        result = json.load(f)

    # Get threshold for tier
    threshold = config['thresholds'][tier]
    tolerance = config['tolerances']

    # Check time threshold
    max_time_ms = threshold['maxTimeMs'] * tolerance['time']
    actual_time_ms = result['validationTimeMs']
    time_ok = actual_time_ms <= max_time_ms

    # Check memory threshold
    max_memory_mb = threshold['maxMemoryMB'] * tolerance['memory']
    actual_memory_mb = result['peakMemoryKB'] / 1024
    memory_ok = actual_memory_mb <= max_memory_mb

    # Print results
    print(f"Tier: {tier}")
    print(f"Time: {actual_time_ms}ms / {max_time_ms}ms (threshold) - {'✅ PASS' if time_ok else '❌ FAIL'}")
    print(f"Memory: {actual_memory_mb:.1f}MB / {max_memory_mb}MB (threshold) - {'✅ PASS' if memory_ok else '❌ FAIL'}")

    # Exit code
    if tier == 'xl':
        # XL is informational only, don't fail CI
        print("\nℹ️  XL tier is stress test - failures are informational")
        sys.exit(0)
    elif time_ok and memory_ok:
        print("\n✅ Performance thresholds met")
        sys.exit(0)
    else:
        print("\n❌ Performance regression detected")
        sys.exit(1)

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Check performance thresholds')
    parser.add_argument('--thresholds', required=True, help='Thresholds JSON file')
    parser.add_argument('--result', required=True, help='Performance result JSON file')
    parser.add_argument('--tier', required=True, choices=['small', 'medium', 'large', 'xl'], help='Topology tier')

    args = parser.parse_args()
    check_thresholds(args.thresholds, args.result, args.tier)
```

### Topology Generation Script

**New Script:** `scripts/generate-topology.sh`

```bash
#!/bin/bash
set -euo pipefail

# Generate realistic fabric topology based on tier
# Usage: generate-topology.sh --tier medium --output topology.yaml

TIER=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier) TIER="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

case "$TIER" in
  medium)
    SWITCHES=20
    LINKS=50
    VPCS=2
    ;;
  large)
    SWITCHES=100
    LINKS=300
    VPCS=10
    ;;
  xl)
    SWITCHES=500
    LINKS=1500
    VPCS=50
    ;;
  *)
    echo "Unknown tier: $TIER" >&2
    exit 1
    ;;
esac

# Generate topology YAML (simplified - actual implementation would be more complex)
cat > "$OUTPUT" <<EOF
# Generated topology: $TIER tier
# Switches: $SWITCHES, Links: $LINKS, VPCs: $VPCS
# trigger strict

fabric:
  name: perf-test-$TIER
  switches:
EOF

# Generate switches
for i in $(seq 1 "$SWITCHES"); do
  cat >> "$OUTPUT" <<EOF
    - name: switch-$(printf '%03d' $i)
      role: leaf
      asn: $((65000 + i))
EOF
done

# Generate links (simplified - pair switches)
cat >> "$OUTPUT" <<EOF
  links:
EOF

for i in $(seq 1 $((LINKS / 2))); do
  src=$((i * 2 - 1))
  dst=$((i * 2))
  cat >> "$OUTPUT" <<EOF
    - from: switch-$(printf '%03d' $src)
      to: switch-$(printf '%03d' $dst)
EOF
done

# Generate VPCs
cat >> "$OUTPUT" <<EOF
  vpcs:
EOF

for i in $(seq 1 "$VPCS"); do
  cat >> "$OUTPUT" <<EOF
    - name: vpc-$(printf '%02d' $i)
      vni: $((10000 + i))
EOF
done

echo "Generated $TIER tier topology: $OUTPUT"
```

### Profiling Runbook

**New Document:** `docs/runbooks/performance-tuning.md`

```markdown
# Performance Tuning and Profiling

## Quick Profiling

Run validation with detailed timing:

\`\`\`bash
/usr/bin/time -v scripts/hoss-validate.sh 2>&1 | tee perf.log

# Extract key metrics
grep "Maximum resident set size" perf.log  # Peak memory (KB)
grep "User time" perf.log                  # CPU time
grep "Elapsed" perf.log                    # Wall clock time
\`\`\`

## Detailed Profiling with perf

\`\`\`bash
# Record performance data
perf record -g -- scripts/hoss-validate.sh

# Analyze
perf report
\`\`\`

## Bottleneck Identification

1. **Slow validation (>30s for large topology)**
   - Check hhfab version (ensure latest)
   - Check CPU throttling: \`cat /proc/cpuinfo | grep MHz\`
   - Profile with \`perf stat\` to identify hot functions

2. **High memory usage (>500MB for large topology)**
   - Check for memory leaks in hhfab (valgrind)
   - Review topology complexity (reduce redundant config)

3. **Slow aggregation (>1s for 100 targets)**
   - Profile jq aggregation: \`time jq -s '...' target-*-result.json\`
   - Consider switching to Python for aggregation
\`\`\`
```

## Implementation Plan

### Phase 1: Infrastructure Setup (Week 1)

**Deliverables:**
1. Create topology generation script (`scripts/generate-topology.sh`)
2. Generate sample topologies (medium, large, xl)
3. Create performance thresholds config (`docs/performance-thresholds.json`)
4. Create threshold checking script (`scripts/check-perf-thresholds.py`)

**Success Criteria:**
- All 3 sample topologies generated and committed
- Thresholds configured based on initial test runs

### Phase 2: Workflow Integration (Week 2)

**Deliverables:**
1. Create `.github/workflows/perf-test.yml`
2. Run baseline performance tests locally
3. Update thresholds based on actual measurements
4. Create performance tuning runbook

**Success Criteria:**
- Workflow runs successfully for all 3 tiers
- Threshold checks pass for medium/large, xl is informational
- Artifacts uploaded to GitHub Actions

### Phase 3: Monitoring and Iteration (Ongoing)

**Deliverables:**
1. Weekly performance reports posted to issue #65
2. Threshold adjustments based on 4 weeks of data
3. Performance regression alerts in CI

**Success Criteria:**
- ≥90% of nightly perf tests pass thresholds
- Performance regressions detected within 24 hours

## Security Considerations

### Resource Exhaustion
- **Risk:** XL topology exhausts CI runner resources, impacts other jobs
- **Mitigation:** Run perf tests on dedicated runner pool (future), limit memory/CPU with `--memory 2g --cpus 2`

### Topology Generation
- **Risk:** Generated topologies contain invalid config, false negatives
- **Mitigation:** Validate generated topologies with hhfab before committing

## Open Questions

1. **Should we track performance metrics over time (trend analysis)?**
   - Store results in GitHub Pages or external DB
   - Plot time-series graphs (detect gradual degradation)
   - Decision: Defer to v0.3.0 (start with simple pass/fail)

2. **Should performance tests block PRs or only run on main?**
   - Block PRs: Prevent regressions before merge
   - Main only: Faster PR feedback, detect regressions post-merge
   - Decision: Main only for now (nightly), add PR blocking in v0.3.0 if needed

3. **What is the target performance for multi-topology mode (RFC 0001)?**
   - Current thresholds are for single topology
   - Multi-topology mode adds parallelization overhead
   - Decision: Update thresholds after RFC 0001 implementation

## Success Metrics

- **Regression Detection:** ≥95% of performance regressions caught within 24 hours
- **Threshold Accuracy:** ≤5% false positive rate (spurious failures)
- **Performance Transparency:** All users can reproduce performance tests locally
- **Capacity Planning:** Operators can predict validation time for their fabric size

## Alternatives Considered

### Alternative 1: Manual Performance Testing
**Pros:** No CI overhead, simple
**Cons:** Not repeatable, easy to skip, no regression detection
**Decision:** Rejected - automation is critical

### Alternative 2: External Benchmarking Service (e.g., Bencher)
**Pros:** Sophisticated trend analysis, beautiful graphs
**Cons:** External dependency, cost, complexity
**Decision:** Deferred - start simple, add if needed

### Alternative 3: Performance Tests Only on Tagged Releases
**Pros:** Minimal CI load
**Cons:** Regressions not caught until release time (too late)
**Decision:** Rejected - nightly testing is better

## References

- Issue #65: https://github.com/afewell-hh/hoss/issues/65
- SECURITY-REVIEW.md: Resource limits recommendation
- docs/GA-CHECKLIST.md: v0.1.0 performance baseline
- `/usr/bin/time` manual: https://man7.org/linux/man-pages/man1/time.1.html

## Changelog

- 2025-10-13: Initial draft
