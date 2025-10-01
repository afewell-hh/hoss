#!/usr/bin/env bash
set -euo pipefail

# Create a temporary directory for the hhfab environment
TMP_DIR=$(mktemp -d)

# Initialize the hhfab environment
cd "$TMP_DIR"
hhfab init --dev

# Generate a VLAB wiring diagram
hhfab vlab gen

# Run the validation
hhfab validate

# Clean up the temporary directory
rm -rf "$TMP_DIR"
