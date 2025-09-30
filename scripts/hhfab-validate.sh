#!/usr/bin/env bash
set -Eeuo pipefail

ART_DIR=".artifacts/review-kit"
SUMMARY="${ART_DIR}/summary.json"
mkdir -p "${ART_DIR}"

STRICT="${STRICT:-0}"
MODE_ENV="${MODE:-}"
MODE_VALUE="${MODE_ENV:-$([[ "${STRICT}" = "1" ]] && echo "strict" || echo "local")}" 
MATRIX_INPUT="${MATRIX:-}"

declare -a TARGETS=()
if [[ -n "${MATRIX_INPUT}" ]]; then
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    TARGETS+=("${line}")
  done <<< "${MATRIX_INPUT}"
else
  TARGETS+=("samples/topology-min.yaml" "samples/contract-min.json")
fi

if ! command -v hhfab >/dev/null 2>&1; then
  echo "ERROR: hhfab binary not available; rerun with a local install or use the strict container job." >&2
  exit 2
fi

hhfab version || echo "WARN: hhfab version command failed (continuing)" >&2

validated=0
failed=0
start_ms=$(date +%s%3N)

for target in "${TARGETS[@]}"; do
  validated=$((validated + 1))
  if [[ ! -f "${target}" ]]; then
    echo "ERROR: sample '${target}' is missing" >&2
    failed=$((failed + 1))
    continue
  fi

  if ! hhfab validate "${target}"; then
    echo "ERROR: validation failed for '${target}'" >&2
    failed=$((failed + 1))
  fi
done

end_ms=$(date +%s%3N)
duration_ms=$((end_ms - start_ms))
status="ok"
if (( failed > 0 )); then
  status="fail"
fi

cat > "${SUMMARY}" <<JSON
{
  "mode": "${MODE_VALUE}",
  "status": "${status}",
  "validated": ${validated},
  "failed": ${failed},
  "durationMs": ${duration_ms}
}
JSON

echo "summary -> ${SUMMARY}"
