# RFC 0001: Multi-Topology Matrix Orchestration

**Status:** Draft
**Issue:** [#62](https://github.com/afewell-hh/hoss/issues/62)
**Author:** HOSS Team
**Created:** 2025-10-13
**Updated:** 2025-10-13

## Summary

Enable HOSS to validate multiple fabric topologies in a single execution with parallel processing and aggregated results. This eliminates the need for separate validation passes and provides unified pass/fail status across all topologies.

## Motivation

**Current State (v0.1.0):**
- Users must run `demonctl run hoss:hoss-validate` separately for each topology
- Each invocation produces a separate `result.json` envelope
- No built-in aggregation of results across multiple topologies
- Manual scripting required for batch validation

**User Pain Points:**
- Tedious repeated invocations for multi-fabric environments
- Difficult to get unified status across all topologies
- No performance benefit from parallelization
- Complex CI/CD integration for multi-topology validation

**Target Users:**
- Operators managing multiple fabric instances (dev/staging/prod)
- CI/CD pipelines validating topology changes across environments
- Large organizations with regional fabric deployments

## Design

### Contract Changes

#### Request Schema (Backward Compatible)

Support both single topology (v0.1.0 compatibility) and array of topologies:

```yaml
# Single topology (v0.1.0 compatible)
topology: samples/topology-basic.yaml

# OR: Multiple topologies (v0.2.0+)
topologies:
  - samples/topology-basic.yaml
  - samples/topology-complex.yaml
  - samples/perf/topology-large.yaml
```

**Validation Rules:**
- Exactly one of `topology` or `topologies` must be specified
- `topologies` array: minimum 1, maximum 100 entries
- All paths must be relative to workspace root
- Empty array rejected with clear error message

#### Result Envelope Schema

Enhanced envelope with matrix breakdown:

```json
{
  "status": "ok",
  "validated": 3,
  "warnings": 0,
  "failures": 0,
  "matrix": {
    "enabled": true,
    "concurrency": 4,
    "executionTimeMs": 8734,
    "targets": [
      {
        "path": "samples/topology-basic.yaml",
        "status": "ok",
        "validated": 1,
        "warnings": 0,
        "failures": 0,
        "executionTimeMs": 2341
      },
      {
        "path": "samples/topology-complex.yaml",
        "status": "ok",
        "validated": 1,
        "warnings": 0,
        "failures": 0,
        "executionTimeMs": 4567
      },
      {
        "path": "samples/perf/topology-large.yaml",
        "status": "ok",
        "validated": 1,
        "warnings": 0,
        "failures": 0,
        "executionTimeMs": 1826
      }
    ]
  },
  "tool": {
    "name": "hhfab",
    "version": "0.41.3"
  }
}
```

**Field Definitions:**
- `status`: Overall status (`ok` only if ALL targets pass, `failed` if ANY fail)
- `validated`: Sum of validated counts across all targets
- `warnings`: Sum of warnings across all targets
- `failures`: Sum of failures across all targets
- `matrix.enabled`: `true` if multi-topology mode was used
- `matrix.concurrency`: Actual concurrency level used (from `HOSS_CONCURRENCY` env var)
- `matrix.executionTimeMs`: Total wall-clock time for all validations
- `matrix.targets[]`: Per-topology results with individual status/counts/timing

**Backward Compatibility:**
- Single topology mode: `matrix.enabled` = `false`, `matrix.targets[]` contains single entry
- All existing v0.1.0 result parsers continue to work (top-level status/counts unchanged)

### Capsule Implementation

#### scripts/hoss-validate.sh Changes

**High-Level Flow:**

```bash
#!/bin/bash
set -euo pipefail

# 1. Parse request.yaml - detect single vs multi topology
if [[ -n "${TOPOLOGY:-}" ]]; then
  # Single topology mode (v0.1.0 compat)
  TOPOLOGIES=("$TOPOLOGY")
  MATRIX_ENABLED=false
elif [[ -n "${TOPOLOGIES:-}" ]]; then
  # Multi topology mode (v0.2.0+)
  IFS=',' read -ra TOPOLOGIES <<< "$TOPOLOGIES"
  MATRIX_ENABLED=true
else
  echo '{"status":"failed","error":"No topology specified"}' > result.json
  exit 1
fi

# 2. Validate topology count (max 100)
if [[ ${#TOPOLOGIES[@]} -gt 100 ]]; then
  echo '{"status":"failed","error":"Too many topologies (max 100)"}' > result.json
  exit 1
fi

# 3. Set concurrency (default: 4, max: 16)
CONCURRENCY=${HOSS_CONCURRENCY:-4}
if [[ $CONCURRENCY -gt 16 ]]; then
  CONCURRENCY=16
fi

# 4. Execute validations in parallel
START_TIME=$(date +%s%3N)
declare -a PIDS
declare -a RESULTS

for i in "${!TOPOLOGIES[@]}"; do
  topology="${TOPOLOGIES[$i]}"

  # Launch validation in background
  (
    target_start=$(date +%s%3N)
    hhfab validate "$topology" > ".artifacts/target-$i.json" 2>&1
    target_status=$?
    target_end=$(date +%s%3N)

    # Write per-target result
    jq -n \
      --arg path "$topology" \
      --arg status "$([ $target_status -eq 0 ] && echo 'ok' || echo 'failed')" \
      --argjson time "$((target_end - target_start))" \
      '{path: $path, status: $status, executionTimeMs: $time}' \
      > ".artifacts/target-$i-result.json"
  ) &

  PIDS[$i]=$!

  # Limit concurrency (wait if at limit)
  if [[ $(jobs -r | wc -l) -ge $CONCURRENCY ]]; then
    wait -n
  fi
done

# 5. Wait for all validations to complete
for pid in "${PIDS[@]}"; do
  wait "$pid" || true
done

END_TIME=$(date +%s%3N)
TOTAL_TIME=$((END_TIME - START_TIME))

# 6. Aggregate results
jq -s \
  --argjson matrix_enabled "$MATRIX_ENABLED" \
  --argjson concurrency "$CONCURRENCY" \
  --argjson total_time "$TOTAL_TIME" \
  '
  {
    status: (if all(.status == "ok") then "ok" else "failed" end),
    validated: map(.validated // 0) | add,
    warnings: map(.warnings // 0) | add,
    failures: map(.failures // 0) | add,
    matrix: {
      enabled: $matrix_enabled,
      concurrency: $concurrency,
      executionTimeMs: $total_time,
      targets: .
    }
  }
  ' .artifacts/target-*-result.json > result.json
```

**Key Implementation Details:**
- Use bash job control (`&`, `wait -n`) for parallel execution
- Limit concurrent jobs with simple counter check
- Per-target results written to `.artifacts/target-$i-result.json`
- Final aggregation uses `jq -s` to combine per-target JSONs
- Resource safety: enforce max 100 topologies, max concurrency 16

#### Environment Variables

**New Variables:**
- `HOSS_CONCURRENCY`: Max parallel validations (default: 4, max: 16)

**Existing Variables (unchanged):**
- `TOPOLOGY`: Single topology path (v0.1.0 compat)
- `TOPOLOGIES`: Comma-separated list of topology paths (v0.2.0+)
- `DEMON_DEBUG`: Debug output flag

### Performance Characteristics

**Expected Performance:**

| Topology Count | Concurrency | Sequential Time | Parallel Time | Speedup |
|---------------|-------------|-----------------|---------------|---------|
| 1             | N/A         | 3s              | 3s            | 1x      |
| 4             | 4           | 12s             | 3s            | 4x      |
| 10            | 4           | 30s             | 8s            | 3.75x   |
| 100           | 16          | 300s            | 20s           | 15x     |

**Assumptions:**
- Each topology takes ~3s to validate (small topologies)
- Negligible aggregation overhead (<100ms)
- Sufficient CPU cores for parallelization

**Resource Usage:**
- Memory: Linear growth (~100MB per concurrent validation)
- CPU: Scales with concurrency (4 cores for concurrency=4)
- Disk: Per-target artifacts in `.artifacts/target-*`

## Implementation Plan

### Phase 1: Spike - Aggregated Envelope (Week 1)

**Goal:** Validate envelope aggregation logic without full parallel execution.

**Deliverables:**
1. `scripts/spike-aggregate-envelope.sh`: Mock script that generates multiple per-target JSONs and aggregates
2. Sample per-target results in `.artifacts/spike/`
3. Aggregated `result.json` demonstrating schema
4. Documentation: `docs/spikes/001-aggregated-envelope.md`

**Success Criteria:**
- Aggregated envelope matches RFC schema
- Top-level counts are correct sums
- Overall status is `failed` if ANY target fails

### Phase 2: Core Implementation (Week 2)

**Deliverables:**
1. Update `scripts/hoss-validate.sh` with parallel execution logic
2. Update `app-pack/contracts/request.schema.json` (add `topologies` field)
3. Update `app-pack/contracts/result.schema.json` (add `matrix` object)
4. Unit tests for aggregation logic (shellcheck + bats)

**Success Criteria:**
- Single topology mode works (v0.1.0 backward compat)
- Multi topology mode validates 10 topologies in <10s (concurrency=4)
- Result envelope validates against schema

### Phase 3: Integration & Testing (Week 3)

**Deliverables:**
1. Update review-kit matrix to include multi-topology test case
2. CI workflow for multi-topology validation
3. Documentation updates (README, quickstart, runbooks)
4. Performance testing with 100 topology matrix

**Success Criteria:**
- Review-kit passes with multi-topology sample
- Performance meets targets (10 topologies in <10s)
- Nightly validation stays green

## Security Considerations

### Resource Exhaustion
- **Risk:** User specifies 1000 topologies, exhausts memory/CPU
- **Mitigation:** Hard limit of 100 topologies, max concurrency 16

### Path Traversal
- **Risk:** Malicious topology path (`../../etc/passwd`)
- **Mitigation:** Validate paths are relative, under workspace root (future RFC: path canonicalization)

### Denial of Service
- **Risk:** Many large topologies cause validation timeout
- **Mitigation:** Respect Demon's existing timeout mechanism (no change needed)

## Alternatives Considered

### Alternative 1: Sequential Execution
**Pros:** Simpler implementation, no concurrency complexity
**Cons:** Poor performance for large matrices (300s for 100 topologies)
**Decision:** Rejected - performance is critical for CI/CD adoption

### Alternative 2: External Orchestration (Makefile/script)
**Pros:** Keep HOSS simple, let users handle parallelization
**Cons:** Poor UX, every user reinvents the wheel, no unified result envelope
**Decision:** Rejected - orchestration is core value proposition

### Alternative 3: Server Mode (long-lived process)
**Pros:** Reuse validation state, faster startup
**Cons:** Significant complexity, conflicts with Demon's stateless execution model
**Decision:** Deferred to future RFC if needed

## Open Questions

1. **How should artifact paths work in multi-topology mode?**
   - Current: `.artifacts/` contains mixed output from all topologies
   - Proposed: `.artifacts/target-0/`, `.artifacts/target-1/`, etc.
   - Decision: TBD (track in issue #63)

2. **Should concurrency be configurable per-request or only via env var?**
   - Per-request: More flexible (different concurrency for different matrices)
   - Env var only: Simpler, consistent with Demon platform patterns
   - Decision: Start with env var only, add per-request if users request it

3. **How should warnings be handled in matrix mode?**
   - Current RFC: Aggregate warnings across all targets
   - Alternative: Fail overall if total warnings exceed threshold
   - Decision: Start with simple aggregation, add warning budgets in future RFC

## Success Metrics

- **Performance:** 10 topologies validated in <10s with concurrency=4
- **Adoption:** ≥50% of users enable multi-topology mode within 3 months
- **CI/CD Integration:** ≥3 CI workflows use multi-topology validation
- **Support Load:** No increase in topology-related support issues

## References

- Issue #62: https://github.com/afewell-hh/hoss/issues/62
- SECURITY-REVIEW.md: Resource limits recommendation
- Demon platform constraints: Stateless execution, container-based
- Review-kit workflow: `.github/workflows/review-kit.yml`

## Changelog

- 2025-10-13: Initial draft
