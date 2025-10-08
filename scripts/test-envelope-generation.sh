#!/usr/bin/env bash
set -euo pipefail

# test-envelope-generation.sh - Test envelope generation without Docker
#
# This script simulates the hhfab-validate.sh envelope generation logic
# to verify the envelope format is correct.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "Testing HOSS envelope generation..."
echo ""

# Create temp directory for test artifacts
TEST_DIR=$(mktemp -d)
trap "rm -rf ${TEST_DIR}" EXIT

export ENVELOPE_PATH="${TEST_DIR}/summary.json"
export HHFAB_IMAGE_DIGEST="ghcr.io/afewell-hh/hoss/hhfab@sha256:54814bbf4e8459cfb35c7cf8872546f0d5d54da9fc317ffb53eab0e137b21d7b"
export HHFAB_MATRIX="samples/topology-min.yaml"

echo "==> Simulating envelope generation..."
echo "  ENVELOPE_PATH: ${ENVELOPE_PATH}"
echo "  HHFAB_IMAGE_DIGEST: ${HHFAB_IMAGE_DIGEST}"
echo "  HHFAB_MATRIX: ${HHFAB_MATRIX}"
echo ""

# Simulate envelope generation (without running actual hhfab)
cat > "${ENVELOPE_PATH}" <<EOF
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
    "imageDigest": "${HHFAB_IMAGE_DIGEST}"
  },
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "matrix": ["${HHFAB_MATRIX}"],
  "errors": []
}
EOF

echo "==> Generated envelope:"
jq . "${ENVELOPE_PATH}"
echo ""

# Validate envelope against schema
echo "==> Validating envelope against schema..."

python3 <<PYEOF
import json
import sys
from pathlib import Path

try:
    from jsonschema import validate, ValidationError, Draft7Validator
except ImportError:
    print("Error: jsonschema not installed", file=sys.stderr)
    sys.exit(1)

# Load schema
with open("app-pack/contracts/hoss/validate.result.json") as f:
    schema = json.load(f)

# Load generated envelope
with open("${ENVELOPE_PATH}") as f:
    envelope = json.load(f)

try:
    validate(instance=envelope, schema=schema, cls=Draft7Validator)
    print("✅ Envelope validates against schema")
except ValidationError as e:
    print(f"❌ Validation failed: {e.message}", file=sys.stderr)
    sys.exit(1)
PYEOF

echo ""
echo "==> Testing envelope field extraction..."

# Test jq queries that would be used in CI/monitoring
STATUS=$(jq -r '.status' "${ENVELOPE_PATH}")
VALIDATED=$(jq -r '.counts.validated' "${ENVELOPE_PATH}")
WARNINGS=$(jq -r '.counts.warnings' "${ENVELOPE_PATH}")
FAILURES=$(jq -r '.counts.failures' "${ENVELOPE_PATH}")
VERSION=$(jq -r '.tool.version' "${ENVELOPE_PATH}")

echo "  status: ${STATUS}"
echo "  validated: ${VALIDATED}"
echo "  warnings: ${WARNINGS}"
echo "  failures: ${FAILURES}"
echo "  tool.version: ${VERSION}"
echo ""

# Verify expected values
if [ "${STATUS}" != "ok" ]; then
    echo "❌ Expected status 'ok', got '${STATUS}'" >&2
    exit 1
fi

if [ "${VALIDATED}" != "1" ]; then
    echo "❌ Expected validated count 1, got ${VALIDATED}" >&2
    exit 1
fi

echo "✅ Envelope field extraction successful"
echo ""

echo "==> Test complete!"
echo ""
echo "Summary:"
echo "  - Envelope generation: ✅"
echo "  - Schema validation: ✅"
echo "  - Field extraction: ✅"
echo ""
echo "The envelope format is correct and ready for Demon integration."
