---
name: Bug Report
about: Report a bug or unexpected behavior in HOSS
title: '[BUG] '
labels: ['bug', 'area:hoss', 'needs-triage']
assignees: ''
---

## Bug Description

<!-- Provide a clear and concise description of the bug -->

## Environment

**HOSS Version:**
<!-- e.g., v0.1.0, main@abc1234 -->

**Demon Environment:**
```bash
# Run: demonctl --version
```

**Demon Commit SHA:**
```bash
# Run: cd /path/to/demon && git rev-parse HEAD
```

**HHFAB Digest:**
```bash
# Check: app-pack/app-pack.yaml or from error logs
```

**Platform:**
<!-- e.g., Ubuntu 22.04, macOS 14.0 -->

## Steps to Reproduce

1.
2.
3.

<!-- Provide the exact commands used -->
```bash
# Commands here
```

## Expected Behavior

<!-- What you expected to happen -->

## Actual Behavior

<!-- What actually happened -->

## Logs and Diagnostics

### result.json
```json
<!-- Paste the contents of result.json -->
```

### CLI Output
```
<!-- Paste demonctl run output or relevant logs -->
```

### .artifacts/ Tree
```
<!-- If available, run: tree .artifacts/ -->
```

## Additional Context

<!-- Add any other context about the problem here -->
<!-- For example: -->
<!-- - Does this happen consistently or intermittently? -->
<!-- - Did this work in a previous version? -->
<!-- - Are there any workarounds? -->

## Checklist

- [ ] I have checked existing issues for duplicates
- [ ] I have included the required environment information
- [ ] I have attached result.json and relevant logs
- [ ] I have redacted any sensitive information (credentials, IPs, etc.)
- [ ] I can reproduce this with samples/topology-basic.yaml (if applicable)
