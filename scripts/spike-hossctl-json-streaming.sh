#!/bin/bash
# Spike: hossctl JSON Streaming
# Purpose: Validate newline-delimited JSON event streaming for hossctl
# Related: RFC 0003 (hossctl CLI wrapper)

set -euo pipefail

SPIKE_DIR=".artifacts/spike"
mkdir -p "$SPIKE_DIR"

echo "🔬 Spike: hossctl JSON Streaming"
echo "================================="
echo ""

# Helper function to emit JSON events
emit_event() {
  local event_type="$1"
  shift
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")

  case "$event_type" in
    started)
      local job_id="$1"
      local topology="$2"
      jq -n \
        --arg event "started" \
        --arg timestamp "$timestamp" \
        --arg job_id "$job_id" \
        --arg topology "$topology" \
        '{event: $event, timestamp: $timestamp, jobId: $job_id, topologies: [$topology]}'
      ;;

    progress)
      local message="$1"
      jq -n \
        --arg event "progress" \
        --arg timestamp "$timestamp" \
        --arg message "$message" \
        '{event: $event, timestamp: $timestamp, message: $message}'
      ;;

    completed)
      local status="$1"
      local result_json="$2"
      jq -n \
        --arg event "completed" \
        --arg timestamp "$timestamp" \
        --arg status "$status" \
        --argjson result "$result_json" \
        '{event: $event, timestamp: $timestamp, status: $status, result: $result}'
      ;;

    failed)
      local error="$1"
      local exit_code="$2"
      jq -n \
        --arg event "failed" \
        --arg timestamp "$timestamp" \
        --arg error "$error" \
        --argjson exit_code "$exit_code" \
        '{event: $event, timestamp: $timestamp, error: $error, exitCode: $exit_code}'
      ;;

    retrying)
      local attempt="$1"
      local max_attempts="$2"
      local backoff_ms="$3"
      jq -n \
        --arg event "retrying" \
        --arg timestamp "$timestamp" \
        --argjson attempt "$attempt" \
        --argjson max_attempts "$max_attempts" \
        --argjson backoff_ms "$backoff_ms" \
        '{event: $event, timestamp: $timestamp, attempt: $attempt, maxAttempts: $max_attempts, backoffMs: $backoff_ms}'
      ;;
  esac
}

# Simulate validation workflow with JSON events
echo "📡 Simulating hossctl validate --json samples/topology-basic.yaml"
echo "=================================================================="
echo ""

# Generate job ID
JOB_ID="20251013-$(date +%H%M%S)-$(head -c 6 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 6)"

# Event 1: Started
emit_event started "$JOB_ID" "samples/topology-basic.yaml" | tee -a "$SPIKE_DIR/events-pretty.jsonl"
emit_event started "$JOB_ID" "samples/topology-basic.yaml" | jq -c . >> "$SPIKE_DIR/events.jsonl"
sleep 0.5

# Event 2: Progress - Launching container
emit_event progress "Launching validation container..." | tee -a "$SPIKE_DIR/events-pretty.jsonl"
emit_event progress "Launching validation container..." | jq -c . >> "$SPIKE_DIR/events.jsonl"
sleep 0.5

# Event 3: Progress - Validating
emit_event progress "Validating topology..." | tee -a "$SPIKE_DIR/events-pretty.jsonl"
emit_event progress "Validating topology..." | jq -c . >> "$SPIKE_DIR/events.jsonl"
sleep 1.0

# Event 4: Progress - Complete
emit_event progress "Validation complete" | tee -a "$SPIKE_DIR/events-pretty.jsonl"
emit_event progress "Validation complete" | jq -c . >> "$SPIKE_DIR/events.jsonl"
sleep 0.2

# Event 5: Completed with result
RESULT_JSON='{"status":"ok","validated":1,"warnings":0,"failures":0,"tool":{"name":"hhfab","version":"0.41.3"}}'
emit_event completed "ok" "$RESULT_JSON" | tee -a "$SPIKE_DIR/events-pretty.jsonl"
emit_event completed "ok" "$RESULT_JSON" | jq -c . >> "$SPIKE_DIR/events.jsonl"

echo ""
echo "✅ JSON streaming simulation complete"
echo ""

# Demonstrate parsing
echo "🔍 Parsing Events with jq:"
echo "=========================="
echo ""

echo "1. Extract all event types:"
jq -r '.event' "$SPIKE_DIR/events.jsonl"
echo ""

echo "2. Filter only progress messages:"
jq -r 'select(.event == "progress") | .message' "$SPIKE_DIR/events.jsonl"
echo ""

echo "3. Extract final result status:"
jq -r 'select(.event == "completed") | .result.status' "$SPIKE_DIR/events.jsonl"
echo ""

echo "4. Pretty-print completed event:"
jq 'select(.event == "completed")' "$SPIKE_DIR/events.jsonl"
echo ""

# Simulate failed validation with retry
echo "📡 Simulating validation with transient failure + retry"
echo "========================================================"
echo ""

JOB_ID_2="20251013-$(date +%H%M%S)-$(head -c 6 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 6)"

emit_event started "$JOB_ID_2" "samples/topology-complex.yaml" | jq -c .
emit_event started "$JOB_ID_2" "samples/topology-complex.yaml" | jq -c . >> "$SPIKE_DIR/events-retry.jsonl"
sleep 0.3
emit_event progress "Validating topology..." | jq -c .
emit_event progress "Validating topology..." | jq -c . >> "$SPIKE_DIR/events-retry.jsonl"
sleep 0.5
emit_event failed "Container startup failed (exit 125)" 125 | jq -c .
emit_event failed "Container startup failed (exit 125)" 125 | jq -c . >> "$SPIKE_DIR/events-retry.jsonl"
sleep 0.2
emit_event retrying 1 3 2000 | jq -c .
emit_event retrying 1 3 2000 | jq -c . >> "$SPIKE_DIR/events-retry.jsonl"
sleep 2.0
emit_event progress "Validating topology..." | jq -c .
emit_event progress "Validating topology..." | jq -c . >> "$SPIKE_DIR/events-retry.jsonl"
sleep 0.8
emit_event completed "ok" "$RESULT_JSON" | jq -c .
emit_event completed "ok" "$RESULT_JSON" | jq -c . >> "$SPIKE_DIR/events-retry.jsonl"

echo ""
echo "✅ Retry simulation complete"
echo ""

# Validation checks
echo "🧪 Validation Checks:"
echo "===================="

# Check 1: All events are valid JSON
if jq empty "$SPIKE_DIR/events.jsonl" 2>/dev/null; then
  echo "✅ All events are valid JSON"
else
  echo "❌ Invalid JSON detected"
  exit 1
fi

# Check 2: Events are newline-delimited (can be parsed line-by-line)
LINE_COUNT=$(wc -l < "$SPIKE_DIR/events.jsonl")
EVENT_COUNT=$(jq -s 'length' "$SPIKE_DIR/events.jsonl")
if [[ "$LINE_COUNT" == "$EVENT_COUNT" ]]; then
  echo "✅ Events are properly newline-delimited ($EVENT_COUNT events)"
else
  echo "❌ Newline delimiting issue (lines: $LINE_COUNT, events: $EVENT_COUNT)"
  exit 1
fi

# Check 3: All events have timestamp field
EVENTS_WITH_TIMESTAMP=0
while IFS= read -r line; do
  if echo "$line" | jq -e '.timestamp != null' >/dev/null 2>&1; then
    EVENTS_WITH_TIMESTAMP=$((EVENTS_WITH_TIMESTAMP + 1))
  fi
done < "$SPIKE_DIR/events.jsonl"

if [[ "$EVENTS_WITH_TIMESTAMP" == "$EVENT_COUNT" ]]; then
  echo "✅ All events have timestamp field"
else
  echo "❌ Some events missing timestamp ($EVENTS_WITH_TIMESTAMP/$EVENT_COUNT)"
  exit 1
fi

# Check 4: Started event has jobId
JOB_ID_FROM_EVENT=$(head -1 "$SPIKE_DIR/events.jsonl" | jq -r '.jobId')
if [[ -n "$JOB_ID_FROM_EVENT" ]]; then
  echo "✅ Started event includes jobId: $JOB_ID_FROM_EVENT"
else
  echo "❌ Started event missing jobId"
  exit 1
fi

# Check 5: Completed event has result object
RESULT_STATUS=$(tail -1 "$SPIKE_DIR/events.jsonl" | jq -r '.result.status')
if [[ "$RESULT_STATUS" == "ok" ]]; then
  echo "✅ Completed event includes result object with status"
else
  echo "❌ Completed event missing or invalid result"
  exit 1
fi

echo ""
echo "🎉 All validation checks passed!"
echo ""

# Demonstrate CI/CD integration pattern
echo "📋 CI/CD Integration Pattern:"
echo "============================="
cat > "$SPIKE_DIR/parse-hossctl-output.sh" <<'SCRIPT'
#!/bin/bash
# Example: Parse hossctl JSON output in CI/CD pipeline

# Simulate reading from hossctl output (using spike events)
INPUT_FILE="${1:-.artifacts/spike/events.jsonl}"

echo "Parsing hossctl output from: $INPUT_FILE"
echo ""

# Stream events and handle each type
while IFS= read -r event; do
  EVENT_TYPE=$(echo "$event" | jq -r '.event')

  case "$EVENT_TYPE" in
    started)
      JOB_ID=$(echo "$event" | jq -r '.jobId')
      echo "▶️  Validation started: $JOB_ID"
      ;;

    progress)
      MESSAGE=$(echo "$event" | jq -r '.message')
      echo "⏳ $MESSAGE"
      ;;

    completed)
      STATUS=$(echo "$event" | jq -r '.status')
      VALIDATED=$(echo "$event" | jq -r '.result.validated')
      FAILURES=$(echo "$event" | jq -r '.result.failures')

      if [[ "$STATUS" == "ok" ]]; then
        echo "✅ Validation passed: $VALIDATED topologies validated"
        exit 0
      else
        echo "❌ Validation failed: $FAILURES failures"
        exit 1
      fi
      ;;

    failed)
      ERROR=$(echo "$event" | jq -r '.error')
      echo "❌ Validation error: $ERROR"
      exit 2
      ;;

    retrying)
      ATTEMPT=$(echo "$event" | jq -r '.attempt')
      MAX=$(echo "$event" | jq -r '.maxAttempts')
      BACKOFF=$(echo "$event" | jq -r '.backoffMs')
      echo "🔄 Retry $ATTEMPT/$MAX (backoff: ${BACKOFF}ms)"
      ;;
  esac
done < "$INPUT_FILE"
SCRIPT

chmod +x "$SPIKE_DIR/parse-hossctl-output.sh"

echo ""
echo "Example CI/CD parser script created: $SPIKE_DIR/parse-hossctl-output.sh"
echo ""
echo "Running parser on spike events:"
bash "$SPIKE_DIR/parse-hossctl-output.sh" "$SPIKE_DIR/events.jsonl"
echo ""

echo "📁 Spike artifacts saved to: $SPIKE_DIR/"
echo "   - events.jsonl (successful validation events)"
echo "   - events-retry.jsonl (retry scenario events)"
echo "   - parse-hossctl-output.sh (CI/CD parser example)"
echo ""
echo "Next steps:"
echo "  1. Implement hossctl CLI wrapper in bash"
echo "  2. Integrate emit_event functions"
echo "  3. Add retry logic with backoff calculation"
echo "  4. Test with real demonctl invocations"
