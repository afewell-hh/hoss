#!/usr/bin/env bash
set -euo pipefail

if ! command -v hhfab >/dev/null 2>&1; then
  echo "WARN: 'hhfab' not found; skipping wiring diagram validation."
  echo "      Install or provide it in CI to enforce."
  exit 0
fi

status=0
shopt -s nullglob
for f in samples/**/*.yaml samples/**/*.yml; do
  echo "Validating with hhfab: $f"
  if ! hhfab validate --in "$f"; then
    echo '::error file=$f::hhfab validation failed'
    echo "ERROR: validation failed for $f"
    status=1
  fi
done
exit $status
