#!/usr/bin/env bash
set -euo pipefail

# Optional verbose tracing when DEMON_DEBUG is enabled
if [[ -n "${DEMON_DEBUG:-}" && "${DEMON_DEBUG}" != "0" ]]; then
  set -x
fi

# HOSS App Pack v0.2.0 validation script - produces Aggregated Result Envelope
# Implements RFC 0001 (multi-topology aggregation) and RFC 0002 (metadata fields)

# Environment variables expected from Demon runtime:
# - ENVELOPE_PATH: Path where the result envelope should be written
# - HHFAB_IMAGE_DIGEST: Digest of the hhfab container image
# - HHFAB_MATRIX: Newline or comma-separated list of topology paths
# - HOSS_CONCURRENCY: Max parallel validations (default: 4, max: 16)
# - HHFAB_CACHE_DIR: Cache directory (e.g., /tmp/.hhfab-cache)
# - TMPDIR: Temporary directory (e.g., /tmp)

ENVELOPE_PATH="${ENVELOPE_PATH:-.artifacts/summary.json}"
ARTIFACT_DIR="$(dirname "$ENVELOPE_PATH")"
mkdir -p "${ARTIFACT_DIR}" 2>/dev/null || true

# Capture execution start metadata (RFC 0002)
EXEC_START_TIME="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
EXEC_START_MS=$(date +%s%3N)
EXEC_HOSTNAME="$(hostname 2>/dev/null || echo 'unknown')"
EXEC_WORKSPACE="$(pwd)"

# Capture hhfab tool metadata
HHFAB_VERSION="$(hhfab --version 2>/dev/null | head -1 || echo "unknown")"
HHFAB_NAME="hhfab"
HHFAB_IMAGE_DIGEST="${HHFAB_IMAGE_DIGEST:-unknown}"

# Extract gitSha from hhfab --version or env var (RFC 0002)
HHFAB_GIT_SHA="${HHFAB_GIT_SHA:-}"
if [[ -z "$HHFAB_GIT_SHA" ]]; then
  # Try to extract from --version output (format: "hhfab vX.Y.Z (commit abc1234...)")
  HHFAB_GIT_SHA=$(hhfab --version 2>/dev/null | grep -oP '[0-9a-f]{40}' | head -1 || echo "")
fi

HHFAB_GIT_SHORT=""
if [[ -n "$HHFAB_GIT_SHA" ]]; then
  HHFAB_GIT_SHORT="${HHFAB_GIT_SHA:0:7}"
fi

# Detect platform (RFC 0002)
PLATFORM="$(uname -s | tr '[:upper:]' '[:lower:]')/$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/')"

# Parse topologies from HHFAB_MATRIX
if [[ -z "${HHFAB_MATRIX:-}" ]]; then
  # Fall back to single fab.yaml if no matrix provided
  if [ -f "fab.yaml" ]; then
    TOPOLOGIES=("fab.yaml")
  else
    echo "ERROR: No HHFAB_MATRIX provided and no fab.yaml found" >&2
    exit 1
  fi
else
  # Parse matrix (supports newline or comma-separated)
  IFS=$'\n,' read -r -d '' -a TOPOLOGIES <<< "${HHFAB_MATRIX}" || true
fi

# Filter out empty entries
FILTERED_TOPOLOGIES=()
for topo in "${TOPOLOGIES[@]}"; do
  topo=$(echo "$topo" | xargs)  # Trim whitespace
  if [[ -n "$topo" ]]; then
    FILTERED_TOPOLOGIES+=("$topo")
  fi
done
TOPOLOGIES=("${FILTERED_TOPOLOGIES[@]}")

TOPOLOGY_COUNT=${#TOPOLOGIES[@]}

if [[ $TOPOLOGY_COUNT -eq 0 ]]; then
  echo "ERROR: No topologies to validate" >&2
  exit 1
fi

# Enforce max 100 topologies (RFC 0001 safety limit)
if [[ $TOPOLOGY_COUNT -gt 100 ]]; then
  echo "ERROR: Too many topologies ($TOPOLOGY_COUNT > 100 max)" >&2
  exit 1
fi

# Determine concurrency (default: 4, max: 16)
CONCURRENCY="${HOSS_CONCURRENCY:-4}"
if [[ $CONCURRENCY -gt 16 ]]; then
  CONCURRENCY=16
fi

# Determine if this is multi-topology mode
MATRIX_ENABLED=false
if [[ $TOPOLOGY_COUNT -gt 1 ]]; then
  MATRIX_ENABLED=true
fi

echo "=== HOSS v0.2.0 Validation ===" >&2
echo "Topologies: $TOPOLOGY_COUNT" >&2
echo "Concurrency: $CONCURRENCY" >&2
echo "Matrix mode: $MATRIX_ENABLED" >&2
echo "" >&2

# Create per-target artifact directories
TARGET_ARTIFACT_DIR="${ARTIFACT_DIR}/targets"
mkdir -p "${TARGET_ARTIFACT_DIR}"

# Validate each topology (with concurrency limiting)
declare -a PIDS
declare -a TARGET_RESULTS

for i in "${!TOPOLOGIES[@]}"; do
  topology="${TOPOLOGIES[$i]}"
  target_dir="${TARGET_ARTIFACT_DIR}/target-${i}"
  mkdir -p "$target_dir"

  # Launch validation in background
  (
    target_start_ms=$(date +%s%3N)
    target_rc=0

    # Run hhfab validation for this topology
    set +e
    if [ -f "$topology" ]; then
      # Compute checksum (RFC 0002)
      checksum=$(sha256sum "$topology" | awk '{print "sha256:" $1}')

      # Run validation
      cd "$(dirname "$topology")"
      hhfab init --dev >"$target_dir/hhfab-init.log" 2>&1
      hhfab vlab gen >"$target_dir/hhfab-vlab.log" 2>&1
      hhfab validate >"$target_dir/hhfab-validate.log" 2>&1
      target_rc=$?
    else
      echo "Topology file not found: $topology" >"$target_dir/error.log"
      target_rc=1
    fi
    set -e

    target_end_ms=$(date +%s%3N)
    target_duration=$((target_end_ms - target_start_ms))

    # Determine target status
    target_status="ok"
    target_validated=0
    target_warnings=0
    target_failures=0

    if [ $target_rc -eq 0 ]; then
      target_status="ok"
      target_validated=1
    else
      target_status="error"
      target_failures=1
    fi

    # Extract errors if failed
    errors_json="[]"
    if [ $target_rc -ne 0 ] && [ -f "$target_dir/hhfab-validate.log" ]; then
      error_msg=$(tail -5 "$target_dir/hhfab-validate.log" | tr '\n' ' ' | sed 's/"/\\"/g')
      errors_json="[{\"message\":\"$error_msg\"}]"
    fi

    # Collect artifact paths (RFC 0002)
    artifact_paths_json="[]"
    if [ -d "$target_dir" ]; then
      artifact_paths=$(find "$target_dir" -type f -printf "%P\n" | jq -R . | jq -s .)
      artifact_paths_json="$artifact_paths"
    fi

    # Write per-target result
    jq -n \
      --arg path "$topology" \
      --arg status "$target_status" \
      --argjson validated "$target_validated" \
      --argjson warnings "$target_warnings" \
      --argjson failures "$target_failures" \
      --argjson execution_time "$target_duration" \
      --arg checksum "${checksum:-}" \
      --argjson artifact_paths "$artifact_paths_json" \
      --argjson errors "$errors_json" \
      '{
        path: $path,
        status: $status,
        validated: $validated,
        warnings: $warnings,
        failures: $failures,
        executionTimeMs: $execution_time,
        checksum: $checksum,
        artifactPaths: $artifact_paths,
        errors: $errors
      }' > "$target_dir/result.json"

  ) &

  PIDS[$i]=$!

  # Limit concurrency (wait if at limit)
  if [[ $(jobs -r | wc -l) -ge $CONCURRENCY ]]; then
    wait -n || true
  fi
done

# Wait for all validations to complete
for pid in "${PIDS[@]}"; do
  wait "$pid" || true
done

# Capture execution end metadata
EXEC_END_MS=$(date +%s%3N)
EXEC_END_TIME="$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")"
TOTAL_DURATION_MS=$((EXEC_END_MS - EXEC_START_MS))

# Aggregate results using jq
echo "Aggregating results..." >&2

# Build tool metadata JSON
TOOL_METADATA=$(jq -n \
  --arg name "$HHFAB_NAME" \
  --arg version "$HHFAB_VERSION" \
  --arg image_digest "$HHFAB_IMAGE_DIGEST" \
  --arg git_sha "${HHFAB_GIT_SHA:-null}" \
  --arg git_short "${HHFAB_GIT_SHORT:-null}" \
  --arg platform "$PLATFORM" \
  '{
    name: $name,
    version: $version,
    imageDigest: $image_digest,
    gitSha: (if $git_sha != "null" and $git_sha != "" then $git_sha else null end),
    gitShort: (if $git_short != "null" and $git_short != "" then $git_short else null end),
    platform: $platform
  }')

# Build execution metadata JSON (RFC 0002)
EXECUTION_METADATA=$(jq -n \
  --arg start_time "$EXEC_START_TIME" \
  --arg end_time "$EXEC_END_TIME" \
  --arg hostname "$EXEC_HOSTNAME" \
  --arg workspace "$EXEC_WORKSPACE" \
  '{
    startTime: $start_time,
    endTime: $end_time,
    hostname: $hostname,
    workspace: $workspace
  }')

# Aggregate all per-target results
jq -s \
  --argjson tool_metadata "$TOOL_METADATA" \
  --argjson execution_metadata "$EXECUTION_METADATA" \
  --argjson matrix_enabled "$MATRIX_ENABLED" \
  --argjson concurrency "$CONCURRENCY" \
  --argjson total_duration "$TOTAL_DURATION_MS" \
  '
  # Calculate aggregated status (error if any target failed)
  def overall_status:
    if all(.status == "ok") then "ok"
    elif any(.status == "error") then "error"
    else "warning"
    end;

  # Calculate aggregated counts
  def sum_counts:
    {
      validated: (map(.validated // 0) | add),
      warnings: (map(.warnings // 0) | add),
      failures: (map(.failures // 0) | add)
    };

  # Build exit code (0 if all ok, 1 otherwise)
  def exit_code:
    if all(.status == "ok") then 0 else 1 end;

  # Build result envelope
  {
    status: overall_status,
    counts: sum_counts,
    tool: $tool_metadata,
    metrics: {
      durationMs: $total_duration,
      exitCode: exit_code,
      counts: sum_counts
    },
    timestamp: $execution_metadata.startTime,
    matrix: {
      enabled: $matrix_enabled,
      concurrency: $concurrency,
      executionTimeMs: $total_duration,
      targets: .
    },
    execution: $execution_metadata,
    errors: (if any(.status == "error") then [.[] | select(.status == "error") | .errors[]] else [] end)
  }
  ' "${TARGET_ARTIFACT_DIR}"/target-*/result.json > "${ENVELOPE_PATH}"

# Check final status
FINAL_STATUS=$(jq -r '.status' "${ENVELOPE_PATH}")
FINAL_EXIT_CODE=$(jq -r '.metrics.exitCode' "${ENVELOPE_PATH}")

echo "" >&2
echo "=== Validation Complete ===" >&2
echo "Status: $FINAL_STATUS" >&2
echo "Validated: $(jq -r '.counts.validated' "${ENVELOPE_PATH}")" >&2
echo "Warnings: $(jq -r '.counts.warnings' "${ENVELOPE_PATH}")" >&2
echo "Failures: $(jq -r '.counts.failures' "${ENVELOPE_PATH}")" >&2
echo "Duration: ${TOTAL_DURATION_MS}ms" >&2
echo "Envelope: ${ENVELOPE_PATH}" >&2

if [ "$FINAL_EXIT_CODE" -ne 0 ]; then
  exit "$FINAL_EXIT_CODE"
fi

exit 0
