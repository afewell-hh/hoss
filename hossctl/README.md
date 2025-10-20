# hossctl

**HOSS CLI** - Command-line interface for the HOSS App Pack on Demon platform.

## Overview

`hossctl` is a Go-based CLI that interacts with Demon platform APIs to run HOSS fabric validation rituals. It provides a simple interface to validate Hedgehog wiring diagrams and retrieve results.

## Installation

### From Source

```bash
# Build
cd hossctl
go build -o hossctl .

# Install to PATH
go install .
```

### Pre-built Binaries

Download from GitHub releases:
```bash
# Linux amd64
curl -LO https://github.com/afewell-hh/hoss/releases/download/v0.1.0/hossctl-linux-amd64
chmod +x hossctl-linux-amd64
sudo mv hossctl-linux-amd64 /usr/local/bin/hossctl

# macOS arm64
curl -LO https://github.com/afewell-hh/hoss/releases/download/v0.1.0/hossctl-darwin-arm64
chmod +x hossctl-darwin-arm64
sudo mv hossctl-darwin-arm64 /usr/local/bin/hossctl
```

## Configuration

### Environment Variables

- `DEMON_URL` - Demon API endpoint (default: `http://localhost:8080`)
- `DEMON_TOKEN` - Authentication token for Demon API (optional)

### Command-line Flags

```bash
# Override Demon URL
hossctl --demon-url https://demon.example.com validate diagram.yaml

# Set authentication token
hossctl --demon-token "your-token" validate diagram.yaml

# Output JSON only
hossctl --json validate diagram.yaml
```

## Usage

### Validate Command

```bash
# Basic validation
hossctl validate samples/topology-min.yaml

# Strict mode (zero warnings allowed)
hossctl validate --strict samples/topology-min.yaml

# With real-time streaming progress (SSE)
hossctl validate --stream samples/topology-min.yaml

# Streaming with JSON output
hossctl validate --stream --json samples/topology-min.yaml

# With custom fab.yaml
hossctl validate --fab-config hhfab-env/fab.yaml samples/topology-min.yaml

# JSON output only
hossctl validate --json samples/topology-min.yaml

# Start validation without waiting
hossctl validate --no-wait samples/topology-min.yaml

# With automatic retry and exponential backoff
hossctl validate --retries 3 --backoff exponential samples/topology-min.yaml

# With linear backoff strategy
hossctl validate --retries 3 --backoff linear --backoff-base 5s samples/topology-min.yaml

# With custom backoff parameters
hossctl validate --retries 5 --backoff exponential --backoff-base 1s --backoff-multiplier 2.5 --backoff-max 30s samples/topology-min.yaml
```

### Retry and Backoff

`hossctl` supports automatic retry with configurable backoff strategies for transient failures. This is useful for handling network glitches, temporary API unavailability, or container startup issues.

**Flags:**
- `--retries N` - Maximum number of retry attempts (default: 0, no retries)
- `--backoff [exponential|linear|constant]` - Backoff strategy (default: exponential)
- `--backoff-base DURATION` - Base delay for backoff (default: 2s)
- `--backoff-multiplier FLOAT` - Multiplier for exponential backoff (default: 2.0)
- `--backoff-max DURATION` - Maximum delay cap (default: 60s)

**Retriable errors:**
- Network errors (connection refused, timeout, DNS failures)
- HTTP 5xx errors (502, 503, 504)
- Container startup failures
- Stream connection errors

**Non-retriable errors (will NOT retry):**
- Validation failures (topology errors)
- HTTP 4xx errors (bad request, unauthorized, forbidden)
- Invalid input errors

**Backoff strategies:**

1. **Exponential** (default): `delay = min(base × multiplier^attempt, max)`
   - Example (base=2s, multiplier=2): 2s, 4s, 8s, 16s, 32s, 60s (capped)

2. **Linear**: `delay = min(base × (attempt + 1), max)`
   - Example (base=2s): 2s, 4s, 6s, 8s, 10s

3. **Constant**: `delay = base` (always the same delay)
   - Example (base=5s): 5s, 5s, 5s, 5s

**Examples:**

```bash
# Retry up to 3 times with exponential backoff (2s, 4s, 8s)
hossctl validate --retries 3 samples/topology-min.yaml

# Retry with linear backoff
hossctl validate --retries 3 --backoff linear --backoff-base 3s samples/topology-min.yaml

# Retry with constant backoff
hossctl validate --retries 3 --backoff constant --backoff-base 5s samples/topology-min.yaml

# CI/CD: retry on transient failures
hossctl validate --retries 3 --backoff exponential --backoff-max 30s --json topology.yaml > result.json
```

### Job Persistence and Async Validation

`hossctl` supports asynchronous validation with persistent job tracking. Launch validations without waiting, then check status and retrieve results later.

**Commands:**
- `hossctl validate --no-wait` - Launch validation asynchronously, return job ID
- `hossctl status <job-id>` - Check job status
- `hossctl result <job-id>` - Retrieve result envelope
- `hossctl jobs` - List recent job history

**Job Metadata Store:**
- Location: `~/.hossctl/jobs/<job-id>/`
- Retention: Last 100 jobs, 7 days max age
- Automatic pruning on `hossctl jobs` invocation

**Examples:**

```bash
# Launch validation asynchronously
JOB_ID=$(hossctl validate --no-wait samples/topology-large.yaml)
echo "Job launched: $JOB_ID"

# Check job status
hossctl status $JOB_ID

# Wait for job to complete
hossctl status $JOB_ID --wait --timeout 10m

# Retrieve result envelope
hossctl result $JOB_ID

# Save result to file
hossctl result $JOB_ID --output result.json

# List recent jobs
hossctl jobs

# Filter by status
hossctl jobs --status running

# Limit results
hossctl jobs --limit 10
```

**CI/CD Workflow: Parallel Validations:**

```bash
#!/bin/bash
# Launch 3 validations in parallel
JOB1=$(hossctl validate --no-wait samples/topology-1.yaml)
JOB2=$(hossctl validate --no-wait samples/topology-2.yaml)
JOB3=$(hossctl validate --no-wait samples/topology-3.yaml)

# Wait for all to complete
for job in $JOB1 $JOB2 $JOB3; do
  hossctl status $job --wait --timeout 10m
  echo "Job $job completed"
done

# Fetch results
hossctl result $JOB1 > result-1.json
hossctl result $JOB2 > result-2.json
hossctl result $JOB3 > result-3.json

# Check for failures
for result in result-*.json; do
  if jq -e '.status == "error"' $result > /dev/null; then
    echo "Validation failed: $result"
    exit 1
  fi
done
```

**Exit Codes:**
- `hossctl status`:
  - `0` - Job completed successfully
  - `1` - Job failed
  - `2` - Job not found
  - `3` - Job still running (when `--wait=false`)
- `hossctl result`:
  - `0` - Result retrieved successfully
  - `1` - Validation failed
  - `2` - Job not found or still running

### Output

**Success (JSON envelope):**
```json
{
  "status": "ok",
  "counts": {
    "validated": 1,
    "warnings": 0,
    "failures": 0
  },
  "tool": {
    "name": "hhfab",
    "version": "v0.41.3",
    "imageDigest": "ghcr.io/afewell-hh/hoss/hhfab@sha256:54814bbf..."
  },
  "timestamp": "2025-10-05T12:34:56Z",
  "matrix": ["samples/topology-min.yaml"],
  "errors": []
}
```

**Streaming output (--stream --json):**
```json
{"event":"status","timestamp":"2025-10-19T18:30:01.234Z","data":{"status":"queued","jobId":"run-abc123"}}
{"event":"status","timestamp":"2025-10-19T18:30:02.456Z","data":{"status":"running","jobId":"run-abc123"}}
{"event":"envelope","timestamp":"2025-10-19T18:30:15.789Z","data":{"result":{"success":true,"data":{"status":"ok","counts":{"validated":1,"warnings":0,"failures":0}}}}}
{"event":"status","timestamp":"2025-10-19T18:30:16.012Z","data":{"status":"completed","jobId":"run-abc123"}}
```

**Exit codes:**
- `0` - Validation succeeded
- `1` - Validation failed or errors occurred

### Examples

```bash
# Example 1: Validate a minimal topology
hossctl validate samples/topology-min.yaml

# Example 2: Validate with strict mode
hossctl validate --strict samples/topology-min.yaml

# Example 3: Use with CI/CD
if hossctl validate --json samples/topology-min.yaml > result.json; then
  echo "Validation passed"
  jq '.counts' result.json
else
  echo "Validation failed"
  jq '.errors' result.json
  exit 1
fi

# Example 4: Remote Demon instance
export DEMON_URL=https://demon.production.example.com
export DEMON_TOKEN=$(cat ~/.demon/token)
hossctl validate topology.yaml
```

## API Integration

`hossctl` interacts with the following Demon platform APIs:

### Start Ritual
```
POST /api/v1/rituals/{ritualName}/runs
Content-Type: application/json

{
  "input": {
    "diagramPath": "samples/topology-min.yaml",
    "strict": false
  }
}

Response:
{
  "runId": "run-abc123",
  "status": "running",
  "ritual": "hoss-validate"
}
```

### Get Run Status
```
GET /api/v1/runs/{runId}

Response:
{
  "runId": "run-abc123",
  "status": "completed",
  "ritual": "hoss-validate",
  "createdAt": "2025-10-05T12:34:00Z",
  "updatedAt": "2025-10-05T12:34:56Z"
}
```

### Get Envelope
```
GET /api/v1/runs/{runId}/envelope

Response: <validate.result.json envelope>
```

## Development

### Build

```bash
go build -o hossctl .
```

### Test

```bash
go test ./...
```

### Cross-compile

```bash
# Linux amd64
GOOS=linux GOARCH=amd64 go build -o hossctl-linux-amd64 .

# macOS arm64
GOOS=darwin GOARCH=arm64 go build -o hossctl-darwin-arm64 .

# Windows amd64
GOOS=windows GOARCH=amd64 go build -o hossctl-windows-amd64.exe .
```

## Troubleshooting

### Connection Refused

**Error:** `failed to execute request: dial tcp 127.0.0.1:8080: connect: connection refused`

**Solution:** Ensure Demon platform is running and `DEMON_URL` is correct:
```bash
export DEMON_URL=http://your-demon-instance:8080
hossctl validate diagram.yaml
```

### Authentication Failed

**Error:** `API error (status 401): Unauthorized`

**Solution:** Set `DEMON_TOKEN`:
```bash
export DEMON_TOKEN=$(demonctl auth token)
hossctl validate diagram.yaml
```

### Timeout

**Error:** `timeout waiting for ritual to complete`

**Solution:** Increase timeout:
```bash
hossctl validate --timeout 10m diagram.yaml
```

## Contributing

See [CONTRIBUTING.md](../CONTRIBUTING.md) for development guidelines.

## License

Apache-2.0 - See [LICENSE](../LICENSE) file for details.
