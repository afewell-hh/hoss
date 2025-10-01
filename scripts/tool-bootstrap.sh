#!/usr/bin/env bash
set -Eeuo pipefail

# where to drop tools locally & in GitHub Actions
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"
echo "Using BIN_DIR=$BIN_DIR"

# oras (used by some hh toolchains)
if ! command -v oras >/dev/null 2>&1; then
  echo "[bootstrap] installing oras…"
  curl -fsSL https://i.hhdev.io/oras | bash
fi

# hhfab
if ! command -v hhfab >/dev/null 2>&1; then
  echo "[bootstrap] installing hhfab…"
  curl -fsSL https://i.hhdev.io/hhfab | bash
fi

echo "[bootstrap] versions:"
command -v oras  && oras version || true
command -v hhfab && hhfab version || true
