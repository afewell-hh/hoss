#!/usr/bin/env bash
set -Eeuo pipefail

ART_DIR=".artifacts/review-kit"
SUMMARY="${ART_DIR}/summary.json"
mkdir -p "${ART_DIR}"

STRICT="${STRICT:-0}"
MODE_ENV="${MODE:-}"
MODE_VALUE="${MODE_ENV:-$([[ "${STRICT}" = "1" ]] && echo "strict" || echo "local")}" 
MATRIX_INPUT="${MATRIX:-}"
if [[ -z "${MATRIX_INPUT}" && -f ".github/review-kit/matrix.txt" ]]; then
  # shellcheck disable=SC2013
  while IFS= read -r line; do
    [[ -z "${line}" || "${line}" =~ ^# ]] && continue
    MATRIX_INPUT+="${line}"$'\n'
  done < ".github/review-kit/matrix.txt"
fi

if [[ -z "${MATRIX_INPUT}" ]]; then
  echo "No MATRIX provided and no .github/review-kit/matrix.txt found" >&2
  exit 2
fi

declare -a TARGETS=()
while IFS= read -r line; do
  [[ -z "${line}" ]] && continue
  TARGETS+=("${line}")
done <<< "${MATRIX_INPUT}"

if ! command -v hhfab >/dev/null 2>&1; then
  echo "ERROR: hhfab binary not available; rerun with a local install or use the strict container job." >&2
  exit 2
fi

hhfab version || echo "WARN: hhfab version command failed (continuing)" >&2

validated=0
failed=0
warnings=0
start_ms=$(date +%s%3N)

for target in "${TARGETS[@]}"; do
  validated=$((validated + 1))
  if [[ ! -f "${target}" ]]; then
    echo "ERROR: sample '${target}' is missing" >&2
    failed=$((failed + 1))
    continue
  fi

  tmp_log=$(mktemp)
  if ! hhfab validate "${target}" | tee "${tmp_log}"; then
    echo "ERROR: validation failed for '${target}'" >&2
    failed=$((failed + 1))
  fi
  warnings=$((warnings + $(grep -c "WARNING:" "${tmp_log}" 2>/dev/null || echo 0)))
  rm -f "${tmp_log}"
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
  "warnings": ${warnings},
  "durationMs": ${duration_ms}
}
JSON

echo "summary -> ${SUMMARY}"
