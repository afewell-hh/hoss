#!/bin/bash
set -euo pipefail

# Generate realistic fabric topology based on tier (RFC 0004)
# Usage: generate-topology.sh --tier <medium|large|xl> --output <file>

TIER=""
OUTPUT=""

usage() {
  cat <<EOF
Usage: generate-topology.sh --tier <tier> --output <file>

Tiers:
  medium    20 switches, 50 links, 2 VPCs
  large     100 switches, 300 links, 10 VPCs
  xl        500 switches, 1500 links, 50 VPCs

Example:
  generate-topology.sh --tier medium --output samples/perf/topology-medium.yaml
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tier)
      TIER="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TIER" || -z "$OUTPUT" ]]; then
  echo "ERROR: --tier and --output are required" >&2
  usage >&2
  exit 1
fi

# Determine topology parameters based on tier
case "$TIER" in
  medium)
    SWITCHES=20
    LINKS=50
    VPCS=2
    ;;
  large)
    SWITCHES=100
    LINKS=300
    VPCS=10
    ;;
  xl)
    SWITCHES=500
    LINKS=1500
    VPCS=50
    ;;
  *)
    echo "ERROR: Unknown tier: $TIER" >&2
    echo "Valid tiers: medium, large, xl" >&2
    exit 1
    ;;
esac

echo "Generating $TIER tier topology..."
echo "  Switches: $SWITCHES"
echo "  Links: $LINKS"
echo "  VPCs: $VPCS"
echo "  Output: $OUTPUT"

# Create output directory
mkdir -p "$(dirname "$OUTPUT")"

# Generate topology YAML
cat > "$OUTPUT" <<EOF
# Generated topology: $TIER tier
# Switches: $SWITCHES, Links: $LINKS, VPCs: $VPCS
# Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# trigger strict

apiVersion: wiring.githedgehog.com/v1beta1
kind: Fabric
metadata:
  name: perf-test-$TIER
  namespace: default
spec:
  switches:
EOF

# Generate switches
for i in $(seq 1 "$SWITCHES"); do
  switch_name="switch-$(printf '%04d' $i)"
  asn=$((65000 + i))
  role="leaf"

  # Make some switches spines (every 10th switch)
  if [[ $((i % 10)) -eq 0 ]]; then
    role="spine"
  fi

  cat >> "$OUTPUT" <<EOF
    - name: $switch_name
      role: $role
      asn: $asn
      ip: 10.0.$(( (i - 1) / 256 )).$(( (i - 1) % 256 ))
EOF
done

# Generate links (pair switches sequentially)
cat >> "$OUTPUT" <<EOF
  links:
EOF

for i in $(seq 1 $((LINKS / 2))); do
  src_idx=$((i * 2 - 1))
  dst_idx=$((i * 2))

  # Ensure we don't exceed switch count
  if [[ $src_idx -gt $SWITCHES || $dst_idx -gt $SWITCHES ]]; then
    break
  fi

  src="switch-$(printf '%04d' $src_idx)"
  dst="switch-$(printf '%04d' $dst_idx)"

  cat >> "$OUTPUT" <<EOF
    - from: $src
      to: $dst
      port: Ethernet$((i % 48 + 1))
EOF
done

# Generate VPCs
cat >> "$OUTPUT" <<EOF
  vpcs:
EOF

for i in $(seq 1 "$VPCS"); do
  vpc_name="vpc-$(printf '%03d' $i)"
  vni=$((10000 + i))

  cat >> "$OUTPUT" <<EOF
    - name: $vpc_name
      vni: $vni
      subnet: 172.16.$(( (i - 1) / 256 )).0/24
EOF
done

echo "✅ Generated $TIER tier topology: $OUTPUT"
echo "   File size: $(wc -c < "$OUTPUT") bytes"
echo "   Lines: $(wc -l < "$OUTPUT")"
