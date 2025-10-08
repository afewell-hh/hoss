#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ARTIFACT_DIR="${REPO_ROOT}/.artifacts"
APP_PACK_VERSION="${APP_PACK_VERSION:-0.1.0}"
TARBALL_NAME="hoss-app-pack-v${APP_PACK_VERSION}.tar.gz"
TARBALL_PATH="${ARTIFACT_DIR}/${TARBALL_NAME}"

COSIGN_BIN="${COSIGN_BIN:-cosign}"
COSIGN_KEY_PATH="${COSIGN_KEY_PATH:-}"
COSIGN_PUBLIC_KEY_PATH="${COSIGN_PUBLIC_KEY_PATH:-${REPO_ROOT}/app-pack/signing/cosign.pub}"
COSIGN_SIGNATURE_PATH="${COSIGN_SIGNATURE_PATH:-${REPO_ROOT}/app-pack/signing/cosign.sig}"

mkdir -p "${ARTIFACT_DIR}"

echo "[app-pack] Building bundle -> ${TARBALL_PATH}"
tar -czf "${TARBALL_PATH}" -C "${REPO_ROOT}" app-pack/

signing_performed="false"
if command -v "${COSIGN_BIN}" >/dev/null 2>&1 && [[ -n "${COSIGN_KEY_PATH}" && -f "${COSIGN_KEY_PATH}" ]]; then
	echo "[app-pack] Signing bundle with cosign"
	"${COSIGN_BIN}" sign-blob \
		--key "${COSIGN_KEY_PATH}" \
		--output-signature "${COSIGN_SIGNATURE_PATH}" \
		"${TARBALL_PATH}"
	signing_performed="true"
else
	echo "[app-pack] ⚠️  Skipping cosign signing (set COSIGN_KEY_PATH and ensure cosign is on PATH)" >&2
fi

if [[ ! -f "${COSIGN_PUBLIC_KEY_PATH}" ]]; then
	echo "[app-pack] ⚠️  Public key missing at ${COSIGN_PUBLIC_KEY_PATH}. Provide COSIGN_PUBLIC_KEY_PATH to point to the published key." >&2
fi

if [[ -f "${COSIGN_PUBLIC_KEY_PATH}" ]]; then
	PUB_HASH=$(python3 -c 'import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "${COSIGN_PUBLIC_KEY_PATH}")
	python3 - "$PUB_HASH" <<'PY'
import pathlib, re, sys
value = sys.argv[1]
path = pathlib.Path("app-pack/app-pack.yaml")
text = path.read_text()
pattern = r"(publicKeyHash:\s*\n\s*algorithm:\s*sha256\s*\n\s*value:\s*)([0-9a-f]+)"
new_text, count = re.subn(pattern, r"\1" + value, text)
if count == 0:
    raise SystemExit("Failed to update publicKeyHash value in app-pack.yaml")
path.write_text(new_text)
PY
	echo "[app-pack] Updated publicKeyHash to ${PUB_HASH}"
fi

DEMON_ROOT="${DEMON_ROOT:-${REPO_ROOT}/../demon}"
if [[ -d "${DEMON_ROOT}" ]]; then
	pushd "${DEMON_ROOT}" >/dev/null
	if cargo run -p demonctl -- app --help >/dev/null 2>&1; then
		echo "[app-pack] Verifying bundle with demonctl app install --verify-only"
		cargo run -p demonctl -- app install "${TARBALL_PATH}" --verify-only >/dev/null
	else
		echo "[app-pack] ℹ️  demonctl app install not yet available; skipping verification" >&2
	fi
	popd >/dev/null
else
	echo "[app-pack] ℹ️  Demon repository not found at ${DEMON_ROOT}; skipping verification" >&2
fi

echo "[app-pack] Done. Bundle: ${TARBALL_PATH}"
if [[ "${signing_performed}" == "true" ]]; then
	echo "[app-pack] Signature: ${COSIGN_SIGNATURE_PATH}"
fi
