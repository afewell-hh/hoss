# Performance Tuning and Profiling

This runbook provides guidance on profiling HOSS validation performance, identifying bottlenecks, and resolving performance issues.

**Related:**
- [RFC 0004: Performance Hardening](../rfcs/0004-performance-hardening.md)
- [Performance Thresholds](../performance-thresholds.json)
- [Issue #65: Performance Hardening](https://github.com/afewell-hh/hoss/issues/65)

---

## Quick Performance Check

Run a quick performance check locally:

```bash
# Medium tier (20 switches)
/usr/bin/time -v bash scripts/hhfab-validate.sh \
  samples/perf/topology-medium.yaml 2>&1 | tee perf.log

# Extract key metrics
grep "Maximum resident set size" perf.log  # Peak memory (KB)
grep "User time" perf.log                  # CPU time
grep "Elapsed" perf.log                    # Wall clock time
```

**Expected results (medium tier):**
- Validation time: <5s
- Peak memory: <200MB
- CPU usage: 70-90%

---

## Performance Tiers

HOSS performance testing uses three topology tiers:

| Tier   | Switches | Links | VPCs | Target Time | Target Memory | Purpose |
|--------|----------|-------|------|-------------|---------------|---------|
| Medium | 20       | 50    | 2    | <5s         | <200MB        | Small enterprise |
| Large  | 100      | 300   | 10   | <30s        | <500MB        | Large enterprise |
| XL     | 500      | 1500  | 50   | <120s       | <1GB          | Stress test |

**Note:** XL tier is informational only and does not block CI.

---

## Profiling Tools

### 1. Basic Timing with `/usr/bin/time`

```bash
# Run validation with detailed timing
/usr/bin/time -v scripts/hhfab-validate.sh 2>&1 | tee perf.log

# Key metrics to examine:
# - "Elapsed (wall clock) time" - Total time including container startup
# - "User time" - CPU time spent in user mode
# - "System time" - CPU time spent in kernel mode
# - "Maximum resident set size" - Peak memory usage (KB)
# - "Percent of CPU this job got" - CPU utilization
```

### 2. Profiling with `perf`

For detailed CPU profiling:

```bash
# Record performance data
perf record -g -- scripts/hhfab-validate.sh

# Analyze
perf report

# Look for:
# - Hot functions (highest % of samples)
# - Call graph to identify bottlenecks
# - Cache misses, page faults
```

### 3. Memory Profiling with `valgrind`

For memory leak detection:

```bash
# Run with valgrind (much slower)
valgrind --tool=memcheck --leak-check=full \
  scripts/hhfab-validate.sh

# Look for:
# - Memory leaks (blocks still reachable)
# - Invalid memory access
# - Use of uninitialized memory
```

### 4. Container Resource Monitoring

Monitor container resource usage during validation:

```bash
# In one terminal, start validation
docker run --rm --name hoss-perf-test \
  -v "$PWD:/workspace:ro" \
  "$HHFAB_IMAGE_DIGEST" \
  scripts/hhfab-validate.sh

# In another terminal, monitor stats
docker stats hoss-perf-test

# Look for:
# - CPU % (should be high during validation)
# - Memory usage (should not exceed 2GB)
# - Network I/O (should be 0 with --network=none)
```

---

## Common Performance Issues

### Issue 1: Slow Validation (>30s for large topology)

**Symptoms:**
- Validation takes much longer than threshold
- CPU usage is low (<50%)

**Possible Causes:**
1. **I/O bottleneck** - Slow disk, network file system
2. **Container startup overhead** - Image pull, layer extraction
3. **hhfab version regression** - New version has performance issues

**Diagnosis:**
```bash
# Check if it's container startup or validation
time docker run --rm "$HHFAB_IMAGE_DIGEST" echo "hello"  # Should be <2s

# Profile the validation script
bash -x scripts/hhfab-validate.sh 2>&1 | tee trace.log

# Look for slow steps in trace.log
```

**Resolution:**
- Use local SSD for workspace (not NFS)
- Pre-pull container image: `docker pull "$HHFAB_IMAGE_DIGEST"`
- Check hhfab version: `hhfab --version`
- Report regression to hhfab upstream

---

### Issue 2: High Memory Usage (>500MB for large topology)

**Symptoms:**
- Peak memory exceeds threshold
- OOM kills (Out of Memory)

**Possible Causes:**
1. **Memory leak** - hhfab or validation script leaks memory
2. **Large topology** - Topology has excessive complexity
3. **Parallel validation overhead** - Too many concurrent validations

**Diagnosis:**
```bash
# Run with reduced concurrency
HOSS_CONCURRENCY=1 scripts/hhfab-validate.sh

# Check memory growth over time
while true; do
  docker stats --no-stream hoss-perf-test | grep hoss-perf-test
  sleep 1
done
```

**Resolution:**
- Reduce `HOSS_CONCURRENCY` (default: 4, try 2 or 1)
- Simplify topology (remove redundant configuration)
- Check for memory leaks with valgrind
- Increase Docker memory limit: `docker run --memory 4g ...`

---

### Issue 3: Slow Aggregation (>1s for 100 targets)

**Symptoms:**
- Validation completes quickly, but aggregation is slow
- High CPU usage during aggregation phase

**Possible Causes:**
1. **jq performance** - Large JSON aggregation with jq
2. **Disk I/O** - Slow writes to `.artifacts/`

**Diagnosis:**
```bash
# Profile aggregation phase
time jq -s '.' .artifacts/review-kit/target-*/result.json

# Check disk I/O
iostat -x 1  # During validation
```

**Resolution:**
- Use faster aggregation (Python instead of jq for large datasets)
- Use tmpfs for `.artifacts/`: `-v /tmp/.artifacts:/workspace/.artifacts`
- Reduce artifact output (disable verbose logging)

---

## Performance Optimization Tips

### 1. Use Digest-Pinned Images

Always use digest-pinned images for reproducible performance:

```bash
export HHFAB_IMAGE_DIGEST="ghcr.io/afewell-hh/hoss/hhfab@sha256:54814bbf..."
```

### 2. Limit Resource Usage

Prevent resource exhaustion with Docker limits:

```bash
docker run --rm \
  --memory 2g \
  --cpus 2 \
  --network=none \
  ...
```

### 3. Use Concurrency Appropriately

Tune `HOSS_CONCURRENCY` based on available CPUs:

```bash
# For 2 CPUs
export HOSS_CONCURRENCY=2

# For 4 CPUs
export HOSS_CONCURRENCY=4

# For large single topology
export HOSS_CONCURRENCY=1
```

### 4. Pre-pull Images

Pre-pull container images to reduce startup time:

```bash
docker pull "$HHFAB_IMAGE_DIGEST"
```

### 5. Use Local Storage

Use local SSD storage for workspace (not NFS):

```bash
# Bad (slow NFS)
cd /mnt/nfs/workspace
scripts/hhfab-validate.sh

# Good (local SSD)
cd /home/user/workspace
scripts/hhfab-validate.sh
```

---

## Threshold Tuning

Thresholds are defined in `docs/performance-thresholds.json`:

```json
{
  "thresholds": {
    "medium": {
      "maxTimeMs": 5000,
      "maxMemoryMB": 200
    }
  },
  "tolerances": {
    "time": 1.1,
    "memory": 1.2
  }
}
```

**Tolerance factors:**
- `time: 1.1` - Allow 10% variance in validation time
- `memory: 1.2` - Allow 20% variance in memory usage

**When to adjust thresholds:**
1. **False positives** - Spurious failures due to runner variability
2. **Legitimate regression** - Upstream hhfab performance degradation
3. **Hardware change** - CI runners upgraded/downgraded

**How to adjust:**
1. Collect data from 10+ nightly runs
2. Calculate 95th percentile for time and memory
3. Update thresholds to 95th percentile + tolerance
4. Submit PR with updated thresholds and justification

---

## Interpreting Performance Reports

Performance reports are generated by `.github/workflows/perf-test.yml`:

```json
{
  "tier": "medium",
  "topology": "samples/perf/topology-medium.yaml",
  "validationTimeMs": 3456,
  "peakMemoryKB": 148352,
  "validationStatus": "ok",
  "timestamp": "2025-10-13T12:00:00Z"
}
```

**Key fields:**
- `validationTimeMs` - Total wall-clock time (includes container startup)
- `peakMemoryKB` - Peak RSS from `/usr/bin/time -v`
- `validationStatus` - Result from validation (`ok`, `failed`, `error`)

**Interpretation:**
- **Time within threshold, memory high** - Memory leak or large topology
- **Time high, memory low** - I/O bottleneck or slow hhfab
- **Both high** - General performance regression

---

## Triage Checklist

When investigating a performance regression:

- [ ] **Reproduce locally** - Can you reproduce on your machine?
- [ ] **Check hhfab version** - Did hhfab version change recently?
- [ ] **Compare with baseline** - Is this a new regression or existing issue?
- [ ] **Profile the slow path** - Use `perf` or `bash -x` to identify bottleneck
- [ ] **Check resource limits** - Are we hitting memory/CPU limits?
- [ ] **Review topology** - Did topology complexity increase?
- [ ] **Check runner variance** - Is this a one-time spike or sustained?
- [ ] **Bisect commits** - Use `git bisect` to find regression

---

## Example Profiling Session

```bash
# 1. Run validation with profiling
/usr/bin/time -v docker run --rm \
  --network=none \
  --read-only \
  --tmpfs /tmp:rw \
  --memory 2g \
  --cpus 2 \
  -e HHFAB_MATRIX="samples/perf/topology-large.yaml" \
  -v "$PWD:/workspace:ro" \
  -v "$PWD/.artifacts:/workspace/.artifacts" \
  -w /workspace \
  "$HHFAB_IMAGE_DIGEST" \
  'scripts/hhfab-validate.sh' \
  2>&1 | tee perf-large.log

# 2. Extract metrics
PEAK_MEM=$(grep "Maximum resident set size" perf-large.log | awk '{print $NF}')
ELAPSED=$(grep "Elapsed.*wall clock" perf-large.log | awk '{print $8}')

echo "Elapsed: $ELAPSED"
echo "Peak Memory: $((PEAK_MEM / 1024))MB"

# 3. Check against thresholds
python3 scripts/check-perf-thresholds.py \
  --thresholds docs/performance-thresholds.json \
  --result .artifacts/perf-large-result.json \
  --tier large

# 4. If failed, profile with perf
perf record -g -- scripts/hhfab-validate.sh
perf report
```

---

## References

- [RFC 0004: Performance Hardening](../rfcs/0004-performance-hardening.md)
- [Performance Thresholds Config](../performance-thresholds.json)
- [GitHub Actions: Performance Test Workflow](../../.github/workflows/perf-test.yml)
- [Issue #65: Performance Hardening](https://github.com/afewell-hh/hoss/issues/65)
- [`/usr/bin/time` manual](https://man7.org/linux/man-pages/man1/time.1.html)
- [`perf` wiki](https://perf.wiki.kernel.org/index.php/Main_Page)

---

## Changelog

- 2025-10-13: Initial version (RFC 0004 implementation)
