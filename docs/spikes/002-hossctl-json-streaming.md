# Spike 002: hossctl JSON Streaming

**Date:** 2025-10-13
**Related RFC:** [0003-hossctl-cli-wrapper.md](../rfcs/0003-hossctl-cli-wrapper.md)
**Related Issue:** [#64](https://github.com/afewell-hh/hoss/issues/64)

## Objective

Validate newline-delimited JSON event streaming for `hossctl` CLI wrapper before implementing full retry logic and job tracking.

## Approach

Created a proof-of-concept script (`scripts/spike-hossctl-json-streaming.sh`) that:
1. Implements `emit_event()` helper function for generating JSON events
2. Simulates validation workflow with progress events
3. Demonstrates retry scenario with transient failure
4. Validates event parsing with jq
5. Creates example CI/CD parser script

## Results

### Event Stream Format

**Successful Validation (Compact JSON):**
```json
{"event":"started","timestamp":"2025-10-13T02:30:17.177Z","jobId":"20251013-023017-x7g","topologies":["samples/topology-basic.yaml"]}
{"event":"progress","timestamp":"2025-10-13T02:30:17.768Z","message":"Launching validation container..."}
{"event":"progress","timestamp":"2025-10-13T02:30:18.354Z","message":"Validating topology..."}
{"event":"progress","timestamp":"2025-10-13T02:30:19.449Z","message":"Validation complete"}
{"event":"completed","timestamp":"2025-10-13T02:30:19.736Z","status":"ok","result":{"status":"ok","validated":1,"warnings":0,"failures":0,"tool":{"name":"hhfab","version":"0.41.3"}}}
```

**Retry Scenario:**
```json
{"event":"started","timestamp":"2025-10-13T02:29:46.194Z","jobId":"20251013-022946-dje","topologies":["samples/topology-complex.yaml"]}
{"event":"progress","timestamp":"2025-10-13T02:29:46.601Z","message":"Validating topology..."}
{"event":"failed","timestamp":"2025-10-13T02:29:47.204Z","error":"Container startup failed (exit 125)","exitCode":125}
{"event":"retrying","timestamp":"2025-10-13T02:29:47.492Z","attempt":1,"maxAttempts":3,"backoffMs":2000}
{"event":"progress","timestamp":"2025-10-13T02:29:49.580Z","message":"Validating topology..."}
{"event":"completed","timestamp":"2025-10-13T02:29:50.518Z","status":"ok","result":{"status":"ok","validated":1,"warnings":0,"failures":0,"tool":{"name":"hhfab","version":"0.41.3"}}}
```

### Event Types Implemented

1. **started:** Validation launched
   - Fields: `event`, `timestamp`, `jobId`, `topologies[]`

2. **progress:** Interim status update
   - Fields: `event`, `timestamp`, `message`

3. **completed:** Validation finished successfully
   - Fields: `event`, `timestamp`, `status`, `result` (full result.json)

4. **failed:** Validation failed
   - Fields: `event`, `timestamp`, `error`, `exitCode`

5. **retrying:** Retry attempt
   - Fields: `event`, `timestamp`, `attempt`, `maxAttempts`, `backoffMs`

### Key Findings

✅ **Newline-Delimited JSON Works Well:**
- Each event is a single line of compact JSON
- Parseable line-by-line with `jq` or any JSON parser
- Human-readable when pretty-printed

✅ **jq is Sufficient for Parsing:**
- `jq -r '.event'` - Extract event type
- `jq 'select(.event == "progress") | .message'` - Filter specific events
- `tail -1 | jq '.result.status'` - Get final status

✅ **CI/CD Integration is Straightforward:**
- Stream events to stdout (newline-delimited)
- CI scripts read line-by-line, parse with jq
- Can emit real-time progress updates

✅ **Timestamps are ISO 8601:**
- Format: `YYYY-MM-DDTHH:MM:SS.sssZ` (UTC)
- Sortable, timezone-agnostic
- Compatible with log aggregation tools

### Validation Checks (All Passed)

1. ✅ All events are valid JSON
2. ✅ Events are properly newline-delimited (5 events)
3. ✅ All events have timestamp field
4. ✅ Started event includes jobId
5. ✅ Completed event includes result object with status

## Implementation Notes

### emit_event() Function

```bash
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

    # ... (failed, retrying cases)
  esac
}
```

**Key Techniques:**
- Use `jq -n` to create JSON from scratch
- Use `--arg` for string values (auto-escapes)
- Use `--argjson` for nested objects
- Compact output with `jq -c` for newline-delimited format

### CI/CD Parser Example

```bash
#!/bin/bash
# Parse hossctl JSON output in CI/CD pipeline

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
      if [[ "$STATUS" == "ok" ]]; then
        echo "✅ Validation passed"
        exit 0
      else
        echo "❌ Validation failed"
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
      echo "🔄 Retry $ATTEMPT/$MAX"
      ;;
  esac
done < input.jsonl
```

### Job ID Format

```bash
JOB_ID="20251013-$(date +%H%M%S)-$(head -c 6 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 6)"
# Example: 20251013-023017-x7g
```

- Format: `YYYYMMDD-HHMMSS-<random>`
- Sortable by timestamp
- Short random suffix prevents collisions

## Recommendations

1. **Integrate into RFC 0003 Implementation:**
   - Use `emit_event()` function in `bin/hossctl`
   - Add `--json` flag to enable streaming mode
   - Default to human-readable output (no JSON)

2. **Error Handling:**
   - Validate all JSON events before emitting (reject malformed)
   - Include error field in failed events
   - Preserve exit codes for CI/CD scripts

3. **Testing:**
   - Add unit tests for event format validation
   - Test line-by-line parsing with different shells (bash, zsh)
   - Test with large result objects (>1MB)

4. **Documentation:**
   - Add JSON streaming examples to quickstart
   - Document event schema in RFC 0003
   - Provide CI/CD integration patterns (GitHub Actions, GitLab CI)

## Artifacts

- **Spike Script:** `scripts/spike-hossctl-json-streaming.sh`
- **Event Streams:** `.artifacts/spike/events.jsonl`, `.artifacts/spike/events-retry.jsonl`
- **CI/CD Parser:** `.artifacts/spike/parse-hossctl-output.sh`

## Next Steps

1. Implement `hossctl` bash CLI in `app-pack/bin/hossctl`
2. Integrate `emit_event()` functions
3. Add retry logic with exponential backoff
4. Implement job tracking for `--no-wait` mode
5. Test with real `demonctl run` invocations

## Lessons Learned

- **Newline-delimited JSON is perfect for streaming:** Line-buffered, parseable incrementally
- **jq is sufficient for event generation and parsing:** No need for Python
- **Compact JSON is better than pretty-printed:** Single line per event, easy parsing
- **CI/CD integration is straightforward:** Read line-by-line, switch on event type

## Comparison with Alternatives

### Alternative 1: JSON-RPC 2.0
**Pros:** Standardized protocol, request/response correlation
**Cons:** More verbose, requires request IDs, overkill for simple streaming
**Decision:** Newline-delimited JSON is simpler

### Alternative 2: Human-readable text with structured parsing
**Pros:** Easier to read without tools
**Cons:** Fragile parsing (regex), hard to extend
**Decision:** JSON is more robust

### Alternative 3: Binary protocol (protobuf, msgpack)
**Pros:** Faster, smaller
**Cons:** Requires special tools to view, harder to debug
**Decision:** JSON is debuggable

---

**Spike Status:** ✅ Success - Ready for RFC 0003 implementation
