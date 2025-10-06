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

# With custom fab.yaml
hossctl validate --fab-config hhfab-env/fab.yaml samples/topology-min.yaml

# JSON output only
hossctl validate --json samples/topology-min.yaml

# Start validation without waiting
hossctl validate --no-wait samples/topology-min.yaml
```

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
