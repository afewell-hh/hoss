#!/usr/bin/env bash
set -Eeuo pipefail

ART_DIR=".artifacts/review-kit"
SUMMARY="${ART_DIR}/summary.json"
mkdir -p "${ART_DIR}"

STRICT="${STRICT:-0}"
MODE_INPUT="${MODE:-}"
if [[ -z "${MODE_INPUT}" ]]; then
  if [[ "${STRICT}" == "1" ]]; then
    MODE_INPUT="strict"
  else
    MODE_INPUT="local"
  fi
fi

MATRIX_INPUT="${MATRIX:-}"
if [[ -z "${MATRIX_INPUT}" && -f ".github/review-kit/matrix.txt" ]]; then
  while IFS= read -r line; do
    [[ -z "${line}" || "${line}" =~ ^# ]] && continue
    MATRIX_INPUT+="${line}"$'\n'
  done < ".github/review-kit/matrix.txt"
fi

started_at_iso=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
start_ms=$(date +%s%3N)

status="ok"
skip_reason=""
note=""
hhfab_version=""
validated=0
failed=0
warnings=0

declare -a TARGETS=()
if [[ -n "${MATRIX_INPUT}" ]]; then
  while IFS= read -r line; do
    [[ -z "${line}" ]] && continue
    TARGETS+=("${line}")
  done <<< "${MATRIX_INPUT}"
fi

if (( ${#TARGETS[@]} == 0 )); then
  status="skipped"
  skip_reason="matrix_empty"
  note="matrix_empty"
fi

if [[ "${status}" == "ok" ]]; then
  if ! command -v hhfab >/dev/null 2>&1; then
    echo "ERROR: hhfab binary not available; rerun with a local install or use the strict container job." >&2
    status="skipped"
    skip_reason="hhfab_missing"
    note="hhfab_missing"
  else
    if hhfab_output=$(hhfab version 2>&1); then
      printf '%s\n' "${hhfab_output}" >&2
      hhfab_version="${hhfab_output%%$'\n'*}"
    else
      echo "WARN: hhfab version command failed (continuing)" >&2
    fi

    for target in "${TARGETS[@]}"; do
      validated=$((validated + 1))
      if [[ ! -f "${target}" ]]; then
        printf '%s:1:1: error: sample is missing\n' "${target}" >&2
        failed=$((failed + 1))
        continue
      fi

      tmp_log=$(mktemp)
      if ! hhfab validate "${target}" | tee "${tmp_log}"; then
        printf '%s:1:1: error: hhfab validation failed (see log)\n' "${target}" >&2
        failed=$((failed + 1))
      fi
      warnings=$((warnings + $(grep -c "WARNING:" "${tmp_log}" 2>/dev/null || echo 0)))
      rm -f "${tmp_log}"
    done

    if (( failed > 0 )); then
      status="fail"
    fi
  fi
fi

end_ms=$(date +%s%3N)
if (( end_ms < start_ms )); then
  duration_ms=0
else
  duration_ms=$((end_ms - start_ms))
fi

strict_bool="false"
if [[ "${STRICT}" == "1" ]]; then
  strict_bool="true"
fi

image_ref="${HHFAB_IMAGE:-${HHFAB_IMAGE_DIGEST:-}}"
image_digest=""
if [[ "${image_ref}" == *@sha256:* ]]; then
  image_digest="${image_ref#*@}"
elif [[ "${image_ref}" == sha256:* ]]; then
  image_digest="${image_ref}"
fi

matrix_serialized=""
if (( ${#TARGETS[@]} > 0 )); then
  matrix_serialized=$(printf '%s\n' "${TARGETS[@]}")
fi

export SUMMARY_MODE="${MODE_INPUT}"
export SUMMARY_STATUS="${status}"
export SUMMARY_STRICT_BOOL="${strict_bool}"
export SUMMARY_VALIDATED="${validated}"
export SUMMARY_FAILED="${failed}"
export SUMMARY_WARNINGS="${warnings}"
export SUMMARY_DURATION_MS="${duration_ms}"
export SUMMARY_IMAGE_REF="${image_ref}"
export SUMMARY_IMAGE_DIGEST="${image_digest}"
export SUMMARY_HHFAB_VERSION="${hhfab_version}"
export SUMMARY_SKIP_REASON="${skip_reason}"
export SUMMARY_NOTE="${note}"
export SUMMARY_MATRIX="${matrix_serialized}"
export SUMMARY_STARTED_AT="${started_at_iso}"

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


status = os.environ.get("SUMMARY_STATUS", "skipped")
allowed_status = {"ok", "fail", "skipped", "error"}
if status not in allowed_status:
    status = "error"

data = {
    "mode": os.environ.get("SUMMARY_MODE", "local"),
    "status": status,
    "strict": os.environ.get("SUMMARY_STRICT_BOOL", "false").lower() == "true",
    "counts": {
        "validated": parse_int("SUMMARY_VALIDATED"),
        "failures": parse_int("SUMMARY_FAILED"),
        "warnings": parse_int("SUMMARY_WARNINGS"),
    },
    "startedAt": os.environ.get("SUMMARY_STARTED_AT", ""),
    "durationMs": parse_int("SUMMARY_DURATION_MS"),
}

matrix_raw = os.environ.get("SUMMARY_MATRIX", "")
if matrix_raw:
    data["matrix"] = [line for line in matrix_raw.splitlines() if line]
else:
    data["matrix"] = []

image_ref = os.environ.get("SUMMARY_IMAGE_REF", "").strip()
image_digest = os.environ.get("SUMMARY_IMAGE_DIGEST", "").strip()
if image_ref or image_digest:
    image_obj = {}
    if image_ref:
        image_obj["ref"] = image_ref
    if image_digest:
        image_obj["digest"] = image_digest
    data["image"] = image_obj

version_value = os.environ.get("SUMMARY_HHFAB_VERSION", "").strip()
if version_value:
    data["hhfab"] = {"version": version_value}

skip_reason = os.environ.get("SUMMARY_SKIP_REASON", "").strip()
if skip_reason:
    data["skipReason"] = skip_reason

note_value = os.environ.get("SUMMARY_NOTE", "").strip()
if note_value:
    data.setdefault("notes", []).append(note_value)

env_fields = {
    "repo": os.environ.get("GITHUB_REPOSITORY"),
    "ref": os.environ.get("GITHUB_REF"),
    "sha": os.environ.get("GITHUB_SHA"),
    "runner": os.environ.get("RUNNER_NAME"),
}
non_empty_env = {k: v for k, v in env_fields.items() if v}
if non_empty_env:
    data["env"] = non_empty_env
else:
    data["env"] = {}

with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\n")
PY

echo "summary -> ${SUMMARY}"

if [[ "${status}" == "fail" ]]; then
  exit 1
fi

if [[ "${status}" == "error" ]]; then
  exit 1
fi
