# RFC 0003: hossctl CLI Wrapper

**Status:** Draft
**Issue:** [#64](https://github.com/afewell-hh/hoss/issues/64)
**Author:** HOSS Team
**Created:** 2025-10-13
**Updated:** 2025-10-13

## Summary

Create `hossctl`, a user-friendly CLI wrapper around `demonctl run hoss:hoss-validate` that provides streaming JSON output, asynchronous execution with polling, automatic retries, and improved error messages. This simplifies CI/CD integration and improves operator experience.

## Motivation

**Current State (v0.1.0):**

Users must manually invoke demonctl with verbose environment variables:

```bash
DEMON_DEBUG=1 DEMON_APP_HOME=/tmp/app-home DEMON_CONTAINER_USER=$(id -u):$(id -g) \
  demonctl run hoss:hoss-validate

# Then manually check result
cat result.json
```

**Pain Points:**
1. **Verbose invocation:** Long command with many env vars
2. **No streaming output:** Must wait for completion, then read result.json
3. **Synchronous blocking:** Can't launch validation and continue working
4. **No retry logic:** Transient failures (container startup glitches) require manual retry
5. **Poor CI/CD integration:** Must wrap demonctl with custom scripts for structured output

**Target Users:**
- CI/CD engineers integrating HOSS into pipelines (GitHub Actions, GitLab CI)
- Operators running ad-hoc validations (want simple command)
- Automation scripts (need structured JSON output, non-blocking execution)

## Design

### Command Structure

```
hossctl validate [flags] [topology...]

Flags:
  --json              Emit newline-delimited JSON events (progress + result)
  --no-wait           Launch async, return job ID immediately
  --retries N         Retry validation up to N times on transient failures (default: 0)
  --backoff TYPE      Retry backoff strategy: constant|linear|exponential (default: exponential)
  --timeout DURATION  Max validation time (default: 5m)
  --app-home PATH     Demon app home directory (default: /tmp/app-home)
  --debug             Enable debug output (sets DEMON_DEBUG=1)
  --help              Show help message

hossctl status <job-id>
  Check status of async validation job

hossctl result <job-id>
  Fetch result.json for async validation job

hossctl logs <job-id>
  Stream logs from async validation job

hossctl cancel <job-id>
  Cancel running async validation job

hossctl version
  Show hossctl and hhfab versions
```

### Streaming JSON Output Mode

**Enabled with `--json` flag:**

```bash
hossctl validate --json samples/topology-basic.yaml
```

**Output format (newline-delimited JSON):**

```json
{"event":"started","timestamp":"2025-10-13T14:32:01.234Z","jobId":"20251013-143201-abc123","topologies":["samples/topology-basic.yaml"]}
{"event":"progress","timestamp":"2025-10-13T14:32:02.456Z","message":"Launching validation container..."}
{"event":"progress","timestamp":"2025-10-13T14:32:03.789Z","message":"Validating topology..."}
{"event":"progress","timestamp":"2025-10-13T14:32:05.012Z","message":"Validation complete"}
{"event":"completed","timestamp":"2025-10-13T14:32:05.234Z","status":"ok","result":{"status":"ok","validated":1,"warnings":0,"failures":0}}
```

**Event Types:**

1. **started:** Validation launched
   - Fields: `jobId`, `topologies`, `timestamp`

2. **progress:** Interim status update
   - Fields: `message`, `timestamp`

3. **completed:** Validation finished successfully
   - Fields: `status`, `result` (full result.json), `timestamp`

4. **failed:** Validation failed
   - Fields: `error`, `exitCode`, `timestamp`

5. **retrying:** Retry attempt (if `--retries` enabled)
   - Fields: `attempt`, `maxAttempts`, `backoffMs`, `timestamp`

**Benefits:**
- Parseable by `jq` line-by-line
- Real-time progress updates (no silent waiting)
- Machine-readable for CI/CD (GitHub Actions can parse events)
- Human-readable without parsing (each line is valid JSON)

### Asynchronous Execution Mode

**Enabled with `--no-wait` flag:**

```bash
# Launch validation in background
JOB_ID=$(hossctl validate --no-wait samples/topology-complex.yaml)
echo "Job ID: $JOB_ID"  # Output: 20251013-143201-abc123

# Continue with other work...
echo "Doing other work..."

# Check job status
hossctl status $JOB_ID
# Output: {"status":"running","startTime":"2025-10-13T14:32:01Z","elapsedMs":5234}

# Wait for completion and fetch result
hossctl result $JOB_ID
# Output: {"status":"ok","validated":1,...}
```

**Job Tracking Implementation:**

- Job metadata stored in `~/.hossctl/jobs/<job-id>/`
- Files:
  - `meta.json`: Job metadata (start time, topologies, status)
  - `result.json`: Symlink to workspace result.json (when complete)
  - `logs.txt`: Captured stdout/stderr from demonctl

**Job ID Format:** `YYYYMMDD-HHMMSS-<random>` (e.g., `20251013-143201-abc123`)

**Job Lifecycle:**
1. `running`: Validation in progress
2. `completed`: Validation finished successfully
3. `failed`: Validation failed or crashed
4. `cancelled`: User cancelled with `hossctl cancel`

### Retry Logic

**Enabled with `--retries N` flag:**

```bash
hossctl validate --retries 3 --backoff exponential samples/topology-basic.yaml
```

**Retry Behavior:**

- **Only retry transient failures:**
  - Container startup failures (exit code 125, 126, 127)
  - Demon communication errors (exit code 2)
  - NOT validation failures (exit code 1) - those are intentional

- **Backoff strategies:**
  - `constant`: Wait fixed 2s between retries
  - `linear`: Wait 2s, 4s, 6s, 8s...
  - `exponential`: Wait 2s, 4s, 8s, 16s... (default, caps at 60s)

- **Max attempts:** `--retries N` means N retry attempts (N+1 total executions)

**Example output with retries:**

```json
{"event":"started","jobId":"abc123","topologies":["samples/topology-basic.yaml"]}
{"event":"progress","message":"Validating topology..."}
{"event":"failed","error":"Container startup failed (exit 125)"}
{"event":"retrying","attempt":1,"maxAttempts":3,"backoffMs":2000}
{"event":"progress","message":"Validating topology..."}
{"event":"completed","status":"ok","result":{...}}
```

### Exit Codes

```
0   Validation passed (status: ok)
1   Validation failed (status: failed, intentional validation errors)
2   Tool error (demonctl failure, container startup failure)
3   Usage error (invalid flags, missing topology)
4   Job not found (for status/result/logs commands)
```

## Implementation

### Technology Choice: Bash

**Decision:** Implement hossctl in Bash (not Python/Go)

**Rationale:**
- Minimal dependencies (bash, jq, demonctl already required)
- Easy to package in app-pack (single script file)
- Consistent with existing HOSS scripts (hoss-validate.sh)
- Fast startup (no interpreter overhead)

**Trade-offs:**
- Less robust error handling than Python
- Limited JSON manipulation (rely on jq)
- Harder to test (no pytest, must use bats)

### File Structure

```
app-pack/
├── bin/
│   └── hossctl              # Main CLI script
├── lib/
│   ├── hossctl-core.sh      # Core validation logic
│   ├── hossctl-jobs.sh      # Job tracking (--no-wait mode)
│   └── hossctl-retry.sh     # Retry logic
└── app-pack.yaml            # Install hossctl in PATH
```

### Core Implementation Outline

**bin/hossctl:**

```bash
#!/usr/bin/env bash
set -euo pipefail

# Parse flags
JSON_MODE=false
NO_WAIT=false
RETRIES=0
BACKOFF=exponential
TIMEOUT=5m
DEBUG=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_MODE=true; shift ;;
    --no-wait) NO_WAIT=true; shift ;;
    --retries) RETRIES="$2"; shift 2 ;;
    --backoff) BACKOFF="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --debug) DEBUG=true; shift ;;
    --help) show_help; exit 0 ;;
    validate|status|result|logs|cancel|version) COMMAND="$1"; shift ;;
    *) TOPOLOGIES+=("$1"); shift ;;
  esac
done

# Dispatch to command handler
case "$COMMAND" in
  validate) cmd_validate ;;
  status)   cmd_status "$1" ;;
  result)   cmd_result "$1" ;;
  logs)     cmd_logs "$1" ;;
  cancel)   cmd_cancel "$1" ;;
  version)  cmd_version ;;
  *) echo "Unknown command: $COMMAND" >&2; exit 3 ;;
esac
```

**cmd_validate function:**

```bash
cmd_validate() {
  # Generate job ID
  JOB_ID="$(date +%Y%m%d-%H%M%S)-$(head -c 8 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 6)"

  # Emit start event (if JSON mode)
  if [[ "$JSON_MODE" == true ]]; then
    jq -n \
      --arg event "started" \
      --arg job_id "$JOB_ID" \
      --argjson topologies "$(printf '%s\n' "${TOPOLOGIES[@]}" | jq -R . | jq -s .)" \
      '{event: $event, jobId: $job_id, topologies: $topologies, timestamp: now | todate}'
  fi

  # Launch validation (with retry logic)
  for attempt in $(seq 0 "$RETRIES"); do
    if run_validation; then
      # Success
      emit_completed
      exit 0
    else
      exit_code=$?
      if [[ $attempt -lt $RETRIES ]] && is_transient_failure "$exit_code"; then
        backoff_ms=$(calculate_backoff "$attempt" "$BACKOFF")
        emit_retrying "$attempt" "$RETRIES" "$backoff_ms"
        sleep "$((backoff_ms / 1000))"
      else
        emit_failed "$exit_code"
        exit "$exit_code"
      fi
    fi
  done
}

run_validation() {
  # Set Demon env vars
  export DEMON_APP_HOME="${DEMON_APP_HOME:-/tmp/app-home}"
  export DEMON_CONTAINER_USER="${DEMON_CONTAINER_USER:-$(id -u):$(id -g)}"
  [[ "$DEBUG" == true ]] && export DEMON_DEBUG=1

  # Run demonctl (capture output if JSON mode)
  if [[ "$JSON_MODE" == true ]]; then
    # Stream progress messages
    demonctl run hoss:hoss-validate 2>&1 | while IFS= read -r line; do
      emit_progress "$line"
    done
    # Check exit code
    return "${PIPESTATUS[0]}"
  else
    # Normal mode (inherit stdout/stderr)
    demonctl run hoss:hoss-validate
  fi
}

emit_progress() {
  local message="$1"
  jq -n \
    --arg event "progress" \
    --arg message "$message" \
    '{event: $event, message: $message, timestamp: now | todate}'
}

emit_completed() {
  local result=$(cat result.json)
  jq -n \
    --arg event "completed" \
    --argjson result "$result" \
    --arg status "$(echo "$result" | jq -r .status)" \
    '{event: $event, status: $status, result: $result, timestamp: now | todate}'
}

emit_failed() {
  local exit_code="$1"
  jq -n \
    --arg event "failed" \
    --argjson exit_code "$exit_code" \
    --arg error "Validation failed with exit code $exit_code" \
    '{event: $event, error: $error, exitCode: $exit_code, timestamp: now | todate}'
}

emit_retrying() {
  local attempt="$1"
  local max_attempts="$2"
  local backoff_ms="$3"
  jq -n \
    --arg event "retrying" \
    --argjson attempt "$((attempt + 1))" \
    --argjson max_attempts "$max_attempts" \
    --argjson backoff_ms "$backoff_ms" \
    '{event: $event, attempt: $attempt, maxAttempts: $max_attempts, backoffMs: $backoff_ms, timestamp: now | todate}'
}
```

### Job Tracking (--no-wait mode)

**Job directory structure:**

```
~/.hossctl/jobs/<job-id>/
├── meta.json        # Job metadata
├── result.json      # Symlink to workspace result.json (when complete)
├── logs.txt         # Captured demonctl output
└── pid              # Process ID of background demonctl
```

**cmd_status implementation:**

```bash
cmd_status() {
  local job_id="$1"
  local job_dir="$HOME/.hossctl/jobs/$job_id"

  if [[ ! -d "$job_dir" ]]; then
    echo "Job not found: $job_id" >&2
    exit 4
  fi

  # Check if process is still running
  local pid=$(cat "$job_dir/pid" 2>/dev/null || echo "")
  if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
    # Still running
    local start_time=$(jq -r .startTime "$job_dir/meta.json")
    local elapsed_ms=$(( ($(date +%s) - $(date -d "$start_time" +%s)) * 1000 ))
    jq -n \
      --arg status "running" \
      --arg start_time "$start_time" \
      --argjson elapsed_ms "$elapsed_ms" \
      '{status: $status, startTime: $start_time, elapsedMs: $elapsed_ms}'
  elif [[ -f "$job_dir/result.json" ]]; then
    # Completed
    cat "$job_dir/result.json"
  else
    # Failed
    jq -n --arg status "failed" '{status: $status}'
  fi
}
```

## Use Cases

### Use Case 1: CI/CD Integration (GitHub Actions)

**Goal:** Parse validation results in real-time, fail fast on errors

```yaml
# .github/workflows/validate.yml
- name: Validate topology
  run: |
    hossctl validate --json samples/topology-basic.yaml | tee output.json

    # Parse final result
    RESULT_STATUS=$(tail -1 output.json | jq -r '.result.status')
    if [[ "$RESULT_STATUS" != "ok" ]]; then
      echo "Validation failed!"
      exit 1
    fi
```

**Benefit:** Structured output without custom parsing

### Use Case 2: Long-Running Validation (--no-wait)

**Goal:** Launch validation, continue with other tasks, check result later

```bash
# Launch async
JOB_ID=$(hossctl validate --no-wait samples/perf/topology-xl.yaml)

# Do other work (building containers, running tests)
make build
make test

# Check if validation done
hossctl status $JOB_ID  # {"status":"running",...}

# Wait for completion and get result
hossctl result $JOB_ID  # Blocks until done, prints result.json
```

**Benefit:** Non-blocking execution for slow validations

### Use Case 3: Retry on Transient Failures

**Goal:** Automatically retry on container startup glitches

```bash
hossctl validate --retries 3 --backoff exponential samples/topology-basic.yaml
```

**Output:**
```json
{"event":"started",...}
{"event":"failed","error":"Container startup failed (exit 125)"}
{"event":"retrying","attempt":1,"backoffMs":2000}
{"event":"completed","status":"ok",...}
```

**Benefit:** Resilience without manual retry scripts

### Use Case 4: Simple Invocation (Default Mode)

**Goal:** Quick validation without flags

```bash
hossctl validate samples/topology-basic.yaml
```

**Output:** (Human-readable, inherits demonctl output)
```
Launching validation...
Validating topology...
✅ Validation passed: 1 topology validated, 0 warnings, 0 failures
```

**Benefit:** Clean UX for operators

## Security Considerations

### Job Directory Permissions
- **Risk:** Other users can read validation results from `~/.hossctl/jobs/`
- **Mitigation:** Create job directories with mode `0700` (owner-only)

### PID Hijacking
- **Risk:** Attacker creates fake PID file to make job appear running
- **Mitigation:** Verify process ownership matches current user (`ps -o uid= -p $pid`)

### Log Injection
- **Risk:** Malicious validation output injects fake JSON events
- **Mitigation:** Validate JSON events before emitting (reject invalid JSON)

## Open Questions

1. **Should hossctl support remote execution (SSH to another host)?**
   - Pros: Useful for distributed environments
   - Cons: Complexity (SSH key management, remote paths)
   - Decision: Defer to future RFC

2. **Should --json mode support JSON-RPC 2.0 format?**
   - Pros: Standardized protocol, request/response correlation
   - Cons: More verbose, most users want simple newline-delimited JSON
   - Decision: Start with newline-delimited JSON (simpler), add JSON-RPC if users request

3. **How should job cleanup work (delete old jobs)?**
   - Automatic: Delete jobs older than 7 days
   - Manual: `hossctl jobs clean` command
   - Decision: Both (auto-cleanup + manual command)

## Success Metrics

- **Adoption:** ≥60% of users switch from `demonctl` to `hossctl` within 3 months
- **CI/CD Integration:** ≥5 CI workflows use `hossctl --json` mode
- **Support Load:** ≥30% reduction in "how do I run HOSS?" support issues
- **Retry Success Rate:** ≥80% of transient failures resolved by automatic retry

## Alternatives Considered

### Alternative 1: Python CLI (Click framework)
**Pros:** Better error handling, easier testing (pytest), rich formatting
**Cons:** Requires Python dependency, slower startup, harder to package
**Decision:** Rejected - Bash is sufficient, matches existing HOSS tooling

### Alternative 2: Extend demonctl (upstream feature)
**Pros:** No wrapper needed, consistent with Demon platform
**Cons:** Requires Demon upstream changes, long feedback cycle
**Decision:** Rejected - hossctl provides value immediately

### Alternative 3: Web UI (dashboard)
**Pros:** Rich visualization, historical results, multi-user
**Cons:** Requires server infrastructure, conflicts with stateless model
**Decision:** Deferred - hossctl CLI is prerequisite, UI can be added later

## References

- Issue #64: https://github.com/afewell-hh/hoss/issues/64
- Demon demonctl CLI: https://github.com/githedgehog/demon
- GitHub Actions structured output: https://docs.github.com/en/actions/using-workflows/workflow-commands-for-github-actions
- Newline-delimited JSON: http://ndjson.org/

## Changelog

- 2025-10-13: Initial draft
