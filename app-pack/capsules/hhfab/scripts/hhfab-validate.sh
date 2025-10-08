#!/usr/bin/env bash
set -euo pipefail

# Optional verbose tracing when DEMON_DEBUG is enabled
if [[ -n "${DEMON_DEBUG:-}" && "${DEMON_DEBUG}" != "0" ]]; then
  set -x
fi

# HOSS App Pack validation script - produces Explainable Result Envelope
# This script runs inside the digest-pinned hhfab container and emits
# a result envelope conforming to contracts/hoss/validate.result.json

# Environment variables expected from Demon runtime:
# - ENVELOPE_PATH: Path where the result envelope should be written
# - HHFAB_IMAGE_DIGEST: Digest of the hhfab container image
# - HHFAB_CACHE_DIR: Cache directory (e.g., /tmp/.hhfab-cache)
# - TMPDIR: Temporary directory (e.g., /tmp)

ENVELOPE_PATH="${ENVELOPE_PATH:-.artifacts/summary.json}"
ARTIFACT_DIR="$(dirname "$ENVELOPE_PATH")"
mkdir -p "${ARTIFACT_DIR}" 2>/dev/null || true

# Capture hhfab version and tool info
HHFAB_VERSION="$(hhfab --version 2>/dev/null || echo "unknown")"
HHFAB_NAME="hhfab"
HHFAB_IMAGE_DIGEST="${HHFAB_IMAGE_DIGEST:-unknown}"

# Timestamp in ISO 8601 format
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# Run hhfab validation
set +e
HHFAB_LOG="${ARTIFACT_DIR}/hhfab-validate.log"
RC=0

if [ -f "fab.yaml" ]; then
	hhfab init --dev >>"${HHFAB_LOG}" 2>&1
	hhfab vlab gen >>"${HHFAB_LOG}" 2>&1
	hhfab validate >>"${HHFAB_LOG}" 2>&1
	RC=$?
else
	echo "No fab.yaml found; skipping hhfab validation (matrix-based validation only)" >>"${HHFAB_LOG}"
fi
set -e

# Build validated targets count from HHFAB_MATRIX if available
validated=0
if [[ -n "${HHFAB_MATRIX:-}" ]]; then
	validated=$(printf '%s' "${HHFAB_MATRIX}" | awk 'NF' | wc -l | tr -d ' ')
	if [[ -z "${validated// /}" ]]; then validated=0; fi
else
	# Fall back: if hhfab succeeded, assume 1 validated target
	if [ "$RC" -eq 0 ]; then validated=1; fi
fi

# Build matrix JSON array
matrix_json="[]"
if [[ -n "${HHFAB_MATRIX:-}" ]]; then
	IFS=$'\n' read -r -d '' -a _m <<< "${HHFAB_MATRIX}" || true
	vals=""
	for e in "${_m[@]}"; do
		if [[ -n "${e// /}" ]]; then
			# Escape backslashes and double quotes
			esc=${e//\\/\\\\}
			esc=${esc//"/\\"}
			vals+="\"${esc}\","
		fi
	done
	vals=${vals%,}
	matrix_json="[${vals}]"
fi

# Determine status
status="ok"
failures=0
warnings=0

if [ "$RC" -ne 0 ]; then
	status="error"
	failures=1
fi

# Build errors array if validation failed
errors_json="[]"
if [ "$RC" -ne 0 ] && [ -f "${HHFAB_LOG}" ]; then
	# Extract error message from log (last 10 lines)
	error_msg=$(tail -10 "${HHFAB_LOG}" | tr '\n' ' ' | sed 's/"/\\"/g')
	errors_json="[{\"message\":\"hhfab validation failed: ${error_msg}\"}]"
fi

# Write Explainable Result Envelope conforming to validate.result.json schema
cat > "${ENVELOPE_PATH}" <<EOF
{
  "status": "${status}",
  "counts": {
    "validated": ${validated},
    "warnings": ${warnings},
    "failures": ${failures}
  },
  "tool": {
    "name": "${HHFAB_NAME}",
    "version": "${HHFAB_VERSION}",
    "imageDigest": "${HHFAB_IMAGE_DIGEST}"
  },
  "timestamp": "${TIMESTAMP}",
  "matrix": ${matrix_json},
  "errors": ${errors_json}
}
EOF

if [ "$RC" -ne 0 ]; then
	echo "Validation failed; see ${HHFAB_LOG}" >&2
	echo "Envelope written to: ${ENVELOPE_PATH}" >&2
	exit $RC
fi

echo "Validation succeeded" >&2
echo "Envelope written to: ${ENVELOPE_PATH}" >&2
exit 0
