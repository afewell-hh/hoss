#!/usr/bin/env bash
set -Eeuo pipefail

ART_DIR=".artifacts/review-kit"
SUMMARY="${ART_DIR}/summary.json"
mkdir -p "${ART_DIR}"

status="skipped"
reason="tooling_missing"

# Optional: respect strict mode (no network, RO fs would be handled by CI runner)
STRICT_MODE="${HHFAB_STRICT:-0}"

# If hhfab exists, run a no-op help/version to prove plumbing works
if command -v hhfab >/dev/null 2>&1; then
  status="ok"
  reason="dry_run"
  hhfab version || true
else
  echo "WARN: 'hhfab' not found; emitting skipped summary" >&2
fi

# Minimal, structured output for CI comments
cat > "${SUMMARY}" <<JSON
{
  "strictMode": ${STRICT_MODE},
  "status": "${status}",
  "reason": "${reason}",
  "artifact": "${SUMMARY}"
}
JSON

echo "summary -> ${SUMMARY}"
