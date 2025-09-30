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

note=""
hhfab_version=""
validated=0
failed=0
warnings=0
duration_ms=0
status="ok"

if [[ -z "${MATRIX_INPUT}" ]]; then
  echo "No MATRIX provided and no .github/review-kit/matrix.txt found" >&2
  status="skipped"
  note="matrix_unavailable"
else
  declare -a TARGETS=()
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    TARGETS+=("${line}")
  done <<< "${MATRIX_INPUT}"

  if ! command -v hhfab >/dev/null 2>&1; then
    echo "ERROR: hhfab binary not available; rerun with a local install or use the strict container job." >&2
    status="skipped"
    note="hhfab_missing"
  else
    if hhfab_output=$(hhfab version 2>&1); then
      printf '%s\n' "${hhfab_output}" >&2
      hhfab_version="${hhfab_output%%$'\n'*}"
    else
      echo "WARN: hhfab version command failed (continuing)" >&2
    fi

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

    if (( failed > 0 )); then
      status="fail"
    fi
  fi
fi

strict_bool="false"
if [[ "${STRICT}" == "1" ]]; then
  strict_bool="true"
fi

image_value="${HHFAB_IMAGE:-${HHFAB_IMAGE_DIGEST:-}}"

export SUMMARY_MODE="${MODE_VALUE}"
export SUMMARY_STATUS="${status}"
export SUMMARY_VALIDATED="${validated}"
export SUMMARY_FAILED="${failed}"
export SUMMARY_WARNINGS="${warnings}"
export SUMMARY_DURATION_MS="${duration_ms}"
export SUMMARY_STRICT_BOOL="${strict_bool}"
export SUMMARY_IMAGE="${image_value}"
export SUMMARY_HHFAB_VERSION="${hhfab_version}"
export SUMMARY_NOTE="${note}"

python3 - "${SUMMARY}" <<'PY'
import json
import os
import sys

output_path = sys.argv[1]

def parse_int(name: str) -> int:
    try:
        return int(os.environ.get(name, "0"))
    except ValueError:
        return 0

data = {
    "mode": os.environ.get("SUMMARY_MODE", "local"),
    "status": os.environ.get("SUMMARY_STATUS", "skipped"),
    "validated": parse_int("SUMMARY_VALIDATED"),
    "failed": parse_int("SUMMARY_FAILED"),
    "warnings": parse_int("SUMMARY_WARNINGS"),
    "durationMs": parse_int("SUMMARY_DURATION_MS"),
    "strict": os.environ.get("SUMMARY_STRICT_BOOL", "false").lower() == "true",
}

image_value = os.environ.get("SUMMARY_IMAGE", "").strip()
data["image"] = image_value if image_value else None

version_value = os.environ.get("SUMMARY_HHFAB_VERSION", "").strip()
data["hhfabVersion"] = version_value or None

note_value = os.environ.get("SUMMARY_NOTE", "").strip()
if note_value:
    data["note"] = note_value

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY

echo "summary -> ${SUMMARY}"

if [[ "${status}" == "skipped" ]]; then
  exit 2
fi

if [[ "${status}" == "fail" ]]; then
  exit 1
fi
