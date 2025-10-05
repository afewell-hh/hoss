#!/usr/bin/env bash
set -euo pipefail

# validate-contracts.sh - Validate JSON contracts against schemas
#
# Usage:
#   ./scripts/validate-contracts.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

cd "${REPO_ROOT}"

echo "Validating HOSS App Pack contracts..."
echo ""

# Check for required tools
if ! command -v jq &> /dev/null; then
    echo "Error: jq is required but not installed" >&2
    exit 1
fi

# We'll use a simple Python script for JSON Schema validation
# since it's more portable than installing ajv-cli
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required for schema validation" >&2
    exit 1
fi

# Install jsonschema if not available (for validation)
if ! python3 -c "import jsonschema" 2>/dev/null; then
    echo "Installing jsonschema package for validation..."
    pip3 install --user jsonschema 2>&1 | grep -v "Requirement already satisfied" || true
fi

CONTRACTS_DIR="app-pack/contracts/hoss"
SAMPLES_DIR="${CONTRACTS_DIR}/.samples"

# Validate JSON syntax first
echo "==> Checking JSON syntax..."
for json_file in "${CONTRACTS_DIR}"/*.json "${SAMPLES_DIR}"/*.json; do
    if [ -f "$json_file" ]; then
        echo "  - $(basename "$json_file")"
        jq empty "$json_file" || {
            echo "    ❌ Invalid JSON syntax" >&2
            exit 1
        }
    fi
done
echo "  ✅ All JSON files have valid syntax"
echo ""

# Validate schemas are valid JSON Schema
echo "==> Validating schemas are valid JSON Schema..."
for schema in "${CONTRACTS_DIR}"/{validate.request.json,validate.result.json}; do
    echo "  - $(basename "$schema")"
    # Check for required JSON Schema fields
    jq -e '."$schema" and .title and .type' "$schema" > /dev/null || {
        echo "    ❌ Missing required JSON Schema fields" >&2
        exit 1
    }
done
echo "  ✅ All schemas are valid JSON Schema"
echo ""

# Validate sample envelopes against schemas
echo "==> Validating samples against schemas..."

python3 <<'PYEOF'
import json
import sys
from pathlib import Path

try:
    from jsonschema import validate, ValidationError, Draft7Validator
except ImportError:
    print("Error: jsonschema not installed", file=sys.stderr)
    sys.exit(1)

contracts_dir = Path("app-pack/contracts/hoss")
samples_dir = contracts_dir / ".samples"

# Load schemas
with open(contracts_dir / "validate.request.json") as f:
    request_schema = json.load(f)

with open(contracts_dir / "validate.result.json") as f:
    result_schema = json.load(f)

errors = []

# Validate request samples
for sample_file in samples_dir.glob("validate.request.*.json"):
    print(f"  - {sample_file.name} against validate.request.json")
    with open(sample_file) as f:
        sample = json.load(f)
    try:
        validate(instance=sample, schema=request_schema, cls=Draft7Validator)
        print(f"    ✅ Valid")
    except ValidationError as e:
        print(f"    ❌ Validation failed: {e.message}", file=sys.stderr)
        errors.append(f"{sample_file.name}: {e.message}")

# Validate result samples
for sample_file in samples_dir.glob("validate.result.*.json"):
    print(f"  - {sample_file.name} against validate.result.json")
    with open(sample_file) as f:
        sample = json.load(f)
    try:
        validate(instance=sample, schema=result_schema, cls=Draft7Validator)
        print(f"    ✅ Valid")
    except ValidationError as e:
        print(f"    ❌ Validation failed: {e.message}", file=sys.stderr)
        errors.append(f"{sample_file.name}: {e.message}")

if errors:
    print("\nValidation errors:", file=sys.stderr)
    for err in errors:
        print(f"  - {err}", file=sys.stderr)
    sys.exit(1)

print("\n✅ All samples validate against their schemas")
PYEOF

echo ""
echo "==> Contract validation complete!"
echo ""
echo "Summary:"
echo "  - JSON syntax: ✅"
echo "  - Schema validity: ✅"
echo "  - Sample validation: ✅"
echo ""
echo "All contracts are valid and ready for use."
