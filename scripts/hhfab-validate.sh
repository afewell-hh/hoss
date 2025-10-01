#!/usr/bin/env bash
set -euo pipefail

run_hhfab_validate() {
  local target="$1"

  # prefer explicit flag styles if supported; fall back to positional / stdin
  if hhfab validate --help 2>&1 | grep -Eq -- '(^|\s)(-f|--file)\b'; then
    hhfab validate -f "$target"
    return
  fi
  if hhfab validate --help 2>&1 | grep -Eq -- '(^|\s)--config\b'; then
    hhfab validate --config "$target"
    return
  fi

  # some builds accept positional file
  if hhfab validate "$target"; then
    return
  fi

  # last resort: pipe as stdin (for builds that auto-detect from content)
  hhfab validate < "$target"
}

if ! command -v hhfab >/dev/null 2>&1; then
  echo "WARN: 'hhfab' not found; skipping wiring diagram validation."
  echo "      Install or provide it in CI to enforce."
  exit 0
fi

status=0
shopt -s nullglob
for f in samples/**/*.yaml samples/**/*.yml; do
  echo "Validating with hhfab: $f"
  if ! run_hhfab_validate "$f"; then
    echo '::error file=$f::hhfab validation failed'
    echo "ERROR: validation failed for $f"
    status=1
  fi
done
exit $status
