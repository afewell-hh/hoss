#!/usr/bin/env bash
set -euo pipefail

# integration-phase1-3.sh
# Automates the Phase 1–3 readiness checks for Work Packet #25.
#
# Phase 1: Contract validation (`scripts/validate-contracts.sh`)
# Phase 2: Envelope generation via hhfab capsule (container if available)
# Phase 3: Envelope schema validation using `demonctl contracts validate-envelope`

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARTIFACT_DIR="${REPO_ROOT}/.artifacts/integration-phase1-3"
mkdir -p "${ARTIFACT_DIR}"
chmod 777 "${ARTIFACT_DIR}" >/dev/null 2>&1 || true

log() {
	echo "==> $1"
}

phase1_status="pending"
phase2_status="pending"
phase3_status="pending"
phase3_note=""
phase3_log=""
SUMMARY_FILE="${ARTIFACT_DIR}/summary.json"
CONTRACT_LOG=""
HHFAB_LOG=""
ENVELOPE_PATH=""

relpath() {
	local target="$1"
	if [[ -z "${target}" || ! -e "${target}" ]]; then
		echo ""
		return
	fi
	python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$target" "${REPO_ROOT}"
}

finalize() {
	local exit_code=$?
	set +e
	if [[ ${exit_code} -ne 0 ]]; then
		[[ "${phase1_status}" == "pending" ]] && phase1_status="failed"
		[[ "${phase2_status}" == "pending" ]] && phase2_status="failed"
		[[ "${phase3_status}" == "pending" ]] && phase3_status="failed"
	else
		[[ "${phase1_status}" == "pending" ]] && phase1_status="ok"
		[[ "${phase2_status}" == "pending" ]] && phase2_status="ok"
		[[ "${phase3_status}" == "pending" ]] && phase3_status="ok"
	fi
	cat > "${SUMMARY_FILE}" <<EOF
{
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "phase1": {
    "status": "${phase1_status}",
    "log": "$(relpath "${CONTRACT_LOG}")"
  },
  "phase2": {
    "status": "${phase2_status}",
    "envelope": "$(relpath "${ENVELOPE_PATH}")",
    "log": "$(relpath "${HHFAB_LOG}")"
  },
  "phase3": {
    "status": "${phase3_status}",
    "log": "$(relpath "${phase3_log}")",
    "note": "${phase3_note}"
  }
}
EOF
}
trap finalize EXIT

log "Phase 1: Validating contracts"
CONTRACT_LOG="${ARTIFACT_DIR}/phase1-contracts.log"
pushd "${REPO_ROOT}" >/dev/null
bash ./scripts/validate-contracts.sh | tee "${CONTRACT_LOG}"
popd >/dev/null
phase1_status="ok"

log "Phase 2: Generating hhfab envelope"
ENVELOPE_PATH="${ARTIFACT_DIR}/hoss-envelope.json"
export ENVELOPE_PATH
export HHFAB_IMAGE_DIGEST="${HHFAB_IMAGE_DIGEST:-}"
MATRIX_FILE="${REPO_ROOT}/.github/review-kit/matrix.txt"
export HHFAB_MATRIX="${HHFAB_MATRIX:-$(
	sed -e '/^[[:space:]]*#/d' -e '/^[[:space:]]*$/d' "${MATRIX_FILE}"
)}"

HHFAB_LOG="${ARTIFACT_DIR}/hhfab-validate.log"
rm -f "${HHFAB_LOG}" "${ENVELOPE_PATH}"

if command -v docker >/dev/null 2>&1 && [[ -n "${HHFAB_IMAGE_DIGEST}" ]]; then
	log "Running hhfab capsule in container (${HHFAB_IMAGE_DIGEST})"
	docker run --rm \
	  --network=none \
	  --read-only \
	  --tmpfs /tmp:rw \
	  -e TMPDIR=/tmp \
	  -e HHFAB_CACHE_DIR=/tmp/.hhfab-cache \
	  -e ENVELOPE_PATH=/workspace/.artifacts/$(basename "${ENVELOPE_PATH}") \
	  -e HHFAB_IMAGE_DIGEST="${HHFAB_IMAGE_DIGEST}" \
	  -e HHFAB_MATRIX="${HHFAB_MATRIX}" \
	  -v "${REPO_ROOT}/app-pack:/workspace:ro" \
	  -v "${ARTIFACT_DIR}:/workspace/.artifacts" \
	  -w /workspace \
	  "${HHFAB_IMAGE_DIGEST}" \
	  capsules/hhfab/scripts/hhfab-validate.sh | tee "${HHFAB_LOG}"
else
	log "Docker or HHFAB_IMAGE_DIGEST not available; using local capsule script"
	pushd "${REPO_ROOT}" >/dev/null
	HHFAB_MATRIX="${HHFAB_MATRIX}" HHFAB_IMAGE_DIGEST="${HHFAB_IMAGE_DIGEST:-unknown}" \
	  bash app-pack/capsules/hhfab/scripts/hhfab-validate.sh | tee "${HHFAB_LOG}"
	popd >/dev/null
fi

if [[ ! -s "${ENVELOPE_PATH}" ]]; then
	echo "❌ Envelope not generated: ${ENVELOPE_PATH}" >&2
	exit 1
fi
phase2_status="ok"

log "Phase 3: Validating envelope with demonctl"
DEMON_ROOT="${DEMON_ROOT:-${REPO_ROOT}/../demon}"
if [[ ! -d "${DEMON_ROOT}" ]]; then
	echo "⚠️  Demon repository not found at ${DEMON_ROOT}; skipping Phase 3" >&2
	phase3_status="skipped"
	phase3_note="Demon repository not available"
else
	pushd "${DEMON_ROOT}" >/dev/null
	phase3_log="${ARTIFACT_DIR}/phase3-demonctl.log"
	cargo run -p demonctl -- contracts validate-envelope "${ENVELOPE_PATH}" \
	  | tee "${phase3_log}"
	popd >/dev/null
	phase3_status="ok"
fi

log "Artifacts written to ${ARTIFACT_DIR}"
log "Envelope path: ${ENVELOPE_PATH}"
