#!/bin/bash
# Spike: Aggregated Result Envelope
# Purpose: Validate multi-topology result aggregation logic
# Related: RFC 0001 (Multi-topology matrix orchestration)

set -euo pipefail

SPIKE_DIR=".artifacts/spike"
mkdir -p "$SPIKE_DIR"

echo "🔬 Spike: Aggregated Result Envelope"
echo "===================================="
echo ""

# Generate mock per-target results
echo "📝 Generating mock per-target results..."

# Target 0: Success (basic topology)
cat > "$SPIKE_DIR/target-0-result.json" <<'EOF'
{
  "path": "samples/topology-basic.yaml",
  "status": "ok",
  "validated": 1,
  "warnings": 0,
  "failures": 0,
  "executionTimeMs": 2341
}
EOF

# Target 1: Success (complex topology)
cat > "$SPIKE_DIR/target-1-result.json" <<'EOF'
{
  "path": "samples/topology-complex.yaml",
  "status": "ok",
  "validated": 1,
  "warnings": 2,
  "failures": 0,
  "executionTimeMs": 4567
}
EOF

# Target 2: Success (large topology)
cat > "$SPIKE_DIR/target-2-result.json" <<'EOF'
{
  "path": "samples/perf/topology-large.yaml",
  "status": "ok",
  "validated": 1,
  "warnings": 0,
  "failures": 0,
  "executionTimeMs": 18234
}
EOF

# Target 3: Failure (invalid topology)
cat > "$SPIKE_DIR/target-3-result.json" <<'EOF'
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
EOF

echo "✅ Generated 4 mock target results"
echo ""

# Aggregate results using jq
echo "🔄 Aggregating results with jq..."

MATRIX_ENABLED=true
CONCURRENCY=4
TOTAL_TIME=25165  # Sum of execution times + overhead

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
  ' "$SPIKE_DIR"/target-*-result.json > "$SPIKE_DIR/result-aggregated.json"

echo "✅ Aggregation complete"
echo ""

# Display aggregated result
echo "📊 Aggregated Result Envelope:"
echo "=============================="
cat "$SPIKE_DIR/result-aggregated.json" | jq .
echo ""

# Validate aggregation logic
echo "🧪 Validation Checks:"
echo "===================="

RESULT_JSON="$SPIKE_DIR/result-aggregated.json"

# Check 1: Overall status should be "failed" (because target-3 failed)
OVERALL_STATUS=$(jq -r '.status' "$RESULT_JSON")
if [[ "$OVERALL_STATUS" == "failed" ]]; then
  echo "✅ Overall status is 'failed' (correct - one target failed)"
else
  echo "❌ Overall status is '$OVERALL_STATUS' (expected 'failed')"
  exit 1
fi

# Check 2: Validated count should be 3 (sum of all targets)
VALIDATED=$(jq -r '.validated' "$RESULT_JSON")
if [[ "$VALIDATED" == "3" ]]; then
  echo "✅ Validated count is 3 (correct sum)"
else
  echo "❌ Validated count is $VALIDATED (expected 3)"
  exit 1
fi

# Check 3: Warnings count should be 2 (only from target-1)
WARNINGS=$(jq -r '.warnings' "$RESULT_JSON")
if [[ "$WARNINGS" == "2" ]]; then
  echo "✅ Warnings count is 2 (correct sum)"
else
  echo "❌ Warnings count is $WARNINGS (expected 2)"
  exit 1
fi

# Check 4: Failures count should be 3 (only from target-3)
FAILURES=$(jq -r '.failures' "$RESULT_JSON")
if [[ "$FAILURES" == "3" ]]; then
  echo "✅ Failures count is 3 (correct sum)"
else
  echo "❌ Failures count is $FAILURES (expected 3)"
  exit 1
fi

# Check 5: Matrix should have 4 targets
TARGET_COUNT=$(jq '.matrix.targets | length' "$RESULT_JSON")
if [[ "$TARGET_COUNT" == "4" ]]; then
  echo "✅ Matrix has 4 targets"
else
  echo "❌ Matrix has $TARGET_COUNT targets (expected 4)"
  exit 1
fi

# Check 6: Matrix enabled flag should be true
MATRIX_ENABLED_FLAG=$(jq -r '.matrix.enabled' "$RESULT_JSON")
if [[ "$MATRIX_ENABLED_FLAG" == "true" ]]; then
  echo "✅ Matrix enabled flag is true"
else
  echo "❌ Matrix enabled flag is $MATRIX_ENABLED_FLAG (expected true)"
  exit 1
fi

echo ""
echo "🎉 All validation checks passed!"
echo ""
echo "📁 Spike artifacts saved to: $SPIKE_DIR/"
echo "   - target-*-result.json (mock per-target results)"
echo "   - result-aggregated.json (aggregated envelope)"
echo ""
echo "Next steps:"
echo "  1. Review aggregated envelope schema"
echo "  2. Integrate aggregation logic into scripts/hoss-validate.sh"
echo "  3. Add parallel execution for multiple topologies"
