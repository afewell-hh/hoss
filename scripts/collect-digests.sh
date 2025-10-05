#!/usr/bin/env bash
set -euo pipefail

# collect-digests.sh - Fetch multi-arch image digests from GHCR and generate bundle YAML
#
# Usage:
#   ./scripts/collect-digests.sh [OPTIONS]
#
# Options:
#   --tag TAG          Image tag to inspect (default: main)
#   --owner OWNER      GitHub owner/org (default: afewell-hh)
#   --repo REPO        Repository name (default: Demon)
#   --show-platforms   Display per-platform manifest digests
#   --bundle-out FILE  Write bundle YAML to FILE (default: stdout)
#   --json-out FILE    Write digest JSON to FILE (default: none)
#   --help             Show this help message

OWNER="${OWNER:-afewell-hh}"
REPO="${REPO:-demon}"
TAG="${TAG:-main}"
SHOW_PLATFORMS=0
BUNDLE_OUT=""
JSON_OUT=""

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)          TAG="$2"; shift 2 ;;
    --owner)        OWNER="$2"; shift 2 ;;
    --repo)         REPO="$2"; shift 2 ;;
    --show-platforms) SHOW_PLATFORMS=1; shift ;;
    --bundle-out)   BUNDLE_OUT="$2"; shift 2 ;;
    --json-out)     JSON_OUT="$2"; shift 2 ;;
    --help|-h)      usage 0 ;;
    *)              echo "Unknown option: $1" >&2; usage 1 ;;
  esac
done

BASE="ghcr.io/$OWNER/$REPO"
IMAGES=(runtime operate-ui engine)

echo "Fetching digests from $BASE (tag: $TAG)..." >&2
echo "" >&2

declare -A DIGESTS

for IMG in "${IMAGES[@]}"; do
  echo "== $IMG:$TAG ==" >&2
  DIGEST=$(docker buildx imagetools inspect "$BASE/$IMG:$TAG" | awk '/Digest:/{print $2; exit}')

  if [[ -z "$DIGEST" ]]; then
    echo "ERROR: Failed to fetch digest for $IMG:$TAG" >&2
    exit 1
  fi

  echo "  $DIGEST" >&2
  DIGESTS[$IMG]="$DIGEST"

  if [[ $SHOW_PLATFORMS -eq 1 ]]; then
    echo "  Platforms:" >&2
    docker buildx imagetools inspect "$BASE/$IMG:$TAG" --format '{{json .Manifest}}' \
      | jq -r '.manifests[] | "    \(.platform.os)/\(.platform.architecture)  \(.digest)"' 2>/dev/null || true
  fi
  echo "" >&2
done

# Generate bundle YAML
BUNDLE_YAML="# Auto-generated bundle for $TAG
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# Base: $BASE

name: preview-$TAG
version: 0.0.1

images:
  runtime: $BASE/runtime@${DIGESTS[runtime]}
  operate_ui: $BASE/operate-ui@${DIGESTS[operate-ui]}
  engine: $BASE/engine@${DIGESTS[engine]}

params:
  nats:
    url: nats://127.0.0.1:4222
  # Add any required env/ports here for bootstrap
"

if [[ -n "$BUNDLE_OUT" ]]; then
  echo "$BUNDLE_YAML" > "$BUNDLE_OUT"
  echo "Bundle written to: $BUNDLE_OUT" >&2
else
  echo "---" >&2
  echo "Bundle YAML:" >&2
  echo "---" >&2
  echo "$BUNDLE_YAML"
fi

echo "" >&2
echo "✅ Digest collection complete!" >&2

# --- CI-friendly outputs: exports, cosign verify, JSON + GHA outputs ---
RUNTIME_DIGEST="$BASE/runtime@${DIGESTS[runtime]}"
OPERATE_UI_DIGEST="$BASE/operate-ui@${DIGESTS[operate-ui]}"
ENGINE_DIGEST="$BASE/engine@${DIGESTS[engine]}"

# Optional cosign verify (off by default). Set COSIGN_VERIFY=1 to enable.
if [[ "${COSIGN_VERIFY:-0}" = "1" ]]; then
  if command -v cosign >/dev/null 2>&1; then
    echo "" >&2
    echo "Verifying signatures with cosign..." >&2
    for d in "$RUNTIME_DIGEST" "$OPERATE_UI_DIGEST" "$ENGINE_DIGEST"; do
      [[ "$d" == *@sha256:* ]] || { echo "ERROR: Not digest-pinned: $d" >&2; exit 3; }
      cosign verify \
        --certificate-identity-regexp '^https://github\.com/afewell-hh/Demon/\.github/workflows/.*@refs/heads/main' \
        --certificate-oidc-issuer 'https://token.actions.githubusercontent.com' \
        "$d" >/dev/null
    done
    echo "✅ Cosign verification passed!" >&2
  else
    echo "WARN: COSIGN_VERIFY=1 but 'cosign' not found; skipping verification." >&2
  fi
fi

# Emit JSON output (optional file or none)
if [[ -n "$JSON_OUT" ]]; then
  mkdir -p "$(dirname "$JSON_OUT")"
  cat > "$JSON_OUT" <<EOF
{
  "tag": "$TAG",
  "images": {
    "runtime": "$RUNTIME_DIGEST",
    "operate_ui": "$OPERATE_UI_DIGEST",
    "engine": "$ENGINE_DIGEST"
  }
}
EOF
  echo "JSON written to: $JSON_OUT" >&2
fi

# Set GitHub Actions outputs for downstream steps
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  [[ -n "$BUNDLE_OUT" ]] && echo "bundle_path=$BUNDLE_OUT" >> "$GITHUB_OUTPUT"
  [[ -n "$JSON_OUT" ]]   && echo "json_path=$JSON_OUT"     >> "$GITHUB_OUTPUT"
fi

# Optional: enforce digest pins (CI hardening). Set REQUIRE_PINS=1 to enable.
if [[ "${REQUIRE_PINS:-0}" = "1" ]] && [[ -n "${JSON_OUT:-}" ]]; then
  if ! grep -Eq '@sha256:[0-9a-f]{64}' "$JSON_OUT"; then
    echo "ERROR: non-digest refs present; set REQUIRE_PINS=0 to bypass" >&2
    exit 3
  fi
  echo "✅ All images are digest-pinned" >&2
fi

echo "" >&2
echo "Next steps:" >&2
echo "  1. Verify bundle: demonctl --bundle <bundle-file> verify" >&2
echo "  2. Dry-run: demonctl --bundle <bundle-file> run --dry-run" >&2
echo "  3. Update docs with digests" >&2
