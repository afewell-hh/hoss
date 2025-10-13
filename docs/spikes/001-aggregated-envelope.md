# Spike 001: Aggregated Result Envelope

**Date:** 2025-10-13
**Related RFC:** [0001-multi-topology-matrix.md](../rfcs/0001-multi-topology-matrix.md)
**Related Issue:** [#62](https://github.com/afewell-hh/hoss/issues/62)

## Objective

Validate the result envelope aggregation logic for multi-topology validation mode before implementing full parallel execution.

## Approach

Created a proof-of-concept script (`scripts/spike-aggregate-envelope.sh`) that:
1. Generates mock per-target result JSON files (4 targets with mixed success/failure)
2. Aggregates results using `jq -s` (slurp mode)
3. Validates aggregation correctness (status, counts, target array)

## Results

### Aggregated Envelope Schema

```json
{
  "status": "failed",
  "validated": 3,
  "warnings": 2,
  "failures": 3,
  "tool": {
    "name": "hhfab",
    "version": "0.41.3"
  },
  "matrix": {
    "enabled": true,
    "concurrency": 4,
    "executionTimeMs": 25165,
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
        "warnings": 2,
        "failures": 0,
        "executionTimeMs": 4567
      },
      {
        "path": "samples/perf/topology-large.yaml",
        "status": "ok",
        "validated": 1,
        "warnings": 0,
        "failures": 0,
        "executionTimeMs": 18234
      },
      {
        "path": "samples/invalid/topology-broken.yaml",
        "status": "failed",
        "validated": 0,
        "warnings": 0,
        "failures": 3,
        "executionTimeMs": 1023,
        "errors": [
          "Switch 'sw1' missing required field 'asn'",
          "Link 'link1' references undefined switch 'sw99'",
          "VPC 'vpc1' has invalid VNI range"
        ]
      }
    ]
  }
}
```

### Key Findings

✅ **Aggregation Logic Works Correctly:**
- Overall status is `failed` when ANY target fails
- Top-level counts are correct sums: `validated=3`, `warnings=2`, `failures=3`
- `matrix.targets[]` preserves per-target details (including error messages)

✅ **jq Performance is Adequate:**
- Aggregation of 4 targets completes in <10ms
- Scales linearly (estimated <100ms for 100 targets)

✅ **Schema is Backward Compatible:**
- Top-level fields (`status`, `validated`, etc.) unchanged from v0.1.0
- New `matrix` object is additive (won't break existing parsers)

### Validation Checks (All Passed)

1. ✅ Overall status is `failed` (correct - one target failed)
2. ✅ Validated count is 3 (correct sum)
3. ✅ Warnings count is 2 (correct sum)
4. ✅ Failures count is 3 (correct sum)
5. ✅ Matrix has 4 targets
6. ✅ Matrix enabled flag is true

## Implementation Notes

### jq Aggregation Command

```bash
jq -s \
  --argjson matrix_enabled true \
  --argjson concurrency 4 \
  --argjson total_time 25165 \
  '
  {
    status: (if all(.status == "ok") then "ok" else "failed" end),
    validated: map(.validated // 0) | add,
    warnings: map(.warnings // 0) | add,
    failures: map(.failures // 0) | add,
    tool: {
      name: "hhfab",
      version: "0.41.3"
    },
    matrix: {
      enabled: $matrix_enabled,
      concurrency: $concurrency,
      executionTimeMs: $total_time,
      targets: .
    }
  }
  ' target-*-result.json > result.json
```

**Key jq Techniques:**
- `jq -s`: Slurp mode (reads all files into single array)
- `all(.status == "ok")`: Check if all targets passed
- `map(.validated // 0) | add`: Sum counts with null-safety
- `targets: .`: Include full per-target array

### Error Handling

- Per-target errors are preserved in `targets[].errors[]` array
- Overall envelope still valid JSON even if one target fails
- No partial results (all targets must complete before aggregation)

## Recommendations

1. **Integrate into RFC 0001 Implementation:**
   - Use exact jq command from spike in `scripts/hoss-validate.sh`
   - Add tool metadata extraction (RFC 0002 fields)
   - Add execution timing logic

2. **Schema Extensions:**
   - Add `matrix.targets[].artifactPaths[]` (RFC 0002)
   - Add `matrix.targets[].checksum` for topology integrity (RFC 0002)

3. **Testing:**
   - Add unit tests for aggregation edge cases:
     - All targets pass
     - All targets fail
     - Mixed success/failure
     - Empty targets array (error case)

4. **Documentation:**
   - Update contract schema in README
   - Add aggregation example to quickstart

## Artifacts

- **Spike Script:** `scripts/spike-aggregate-envelope.sh`
- **Mock Results:** `.artifacts/spike/target-*-result.json`
- **Aggregated Envelope:** `.artifacts/spike/result-aggregated.json`

## Next Steps

1. Implement parallel execution logic (bash job control with `&` and `wait`)
2. Integrate aggregation into `scripts/hoss-validate.sh`
3. Add concurrency limiting (`HOSS_CONCURRENCY` env var)
4. Test with real hhfab validations (not mocks)

## Lessons Learned

- jq is powerful enough for aggregation (no need for Python)
- Envelope schema extensions are straightforward (additive, backward compatible)
- Mock-based validation works well for testing aggregation logic in isolation

---

**Spike Status:** ✅ Success - Ready for RFC 0001 implementation
