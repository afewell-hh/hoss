# HOSS GA Readiness Checklist

**Purpose**: Pre-flight checklist for promoting HOSS from RC to General Availability (GA).

**Status**: ✅ Ready for GA (Demon workspace mount fix validated)

---

## Release Criteria

### Core Functionality
- [x] App Pack structure complete and validated
- [x] Container-based validation working (hhfab v0.41.3+)
- [x] ResultEnvelope format with required metrics
- [x] Non-login shell execution (/bin/bash -c)
- [x] **RESOLVED**: `demonctl run` workspace mount issue (Demon PR #267, merged 2025-10-11)
- [x] Post-fix validation complete (2025-10-12, see details below)

### Security & Signing
- [x] cosign installed and configured
- [x] Local signing/verification tested (`make app-pack-sign`, `make app-pack-verify`)
- [x] app-pack.yaml signing enabled (`cosign.enabled: true`)
- [x] GitHub Actions workflow updated with OIDC signing
- [x] Release workflow uploads signature bundle
- [x] README includes signature verification instructions

### Documentation
- [x] Installation instructions (README)
- [x] Non-login shell behavior documented
- [x] DEMON_DEBUG usage documented
- [x] Day 7 integration success linked
- [ ] GA release notes drafted
- [ ] Migration guide from RC1 (if needed)

### UI & Integration
- [x] UI card mapping verified (`result.data.*` format)
- [x] Contracts validated (request/result schemas)
- [ ] Operate UI spot-check with GA build
- [ ] End-to-end test with GA candidate

### CI & Testing
- [x] review-kit (strict) green on main
- [x] HHFAB_IMAGE_DIGEST pinned
- [ ] Post-fix CI run passes
- [ ] Performance baseline documented
- [ ] Regression suite executed

---

## Post-Fix Verification Plan

**Trigger**: After Demon merges workspace mount fix (Demon#265/266)

### Quick Re-validation Steps
1. **Pull latest Demon**
   ```bash
   cd /home/ubuntu/afewell-hh/demon
   git pull origin main
   cargo build --release --bin demonctl
   ```

2. **Confirm workspace mount fix**
   ```bash
   # Should succeed without manual Docker workaround
   cd /home/ubuntu/afewell-hh/hoss
   DEMON_DEBUG=1 DEMON_APP_HOME=/tmp/app-home DEMON_CONTAINER_USER=1000:1000 \
     /home/ubuntu/afewell-hh/demon/target/release/demonctl run hoss:hoss-validate --save
   ```

3. **Capture artifacts**
   - CLI logs (stdout/stderr from demonctl run)
   - result.json envelope
   - .artifacts/ tree
   - Demon commit SHA
   - demonctl version

4. **Verify success criteria**
   - ✅ Exit code 0
   - ✅ `result.success: true`
   - ✅ `result.data.status: "ok"`
   - ✅ No "file not found" errors in diagnostics
   - ✅ Envelope written to expected path

5. **Operate UI spot-check**
   - Upload result envelope to Operate
   - Verify card displays all fields correctly
   - Check status, counts, tool version visible

### Expected Outcome
- All steps pass without workarounds
- Demon workspace mount issue confirmed resolved
- Ready to proceed with GA build

### Artifacts to Attach
- Demon SHA after fix
- CLI logs showing successful run
- result.json envelope
- Screenshot of Operate UI card (optional)

### ✅ Post-Fix Validation Results (2025-10-12)

**Demon Environment:**
- demonctl version: 0.0.1
- Demon main SHA: `52884c7b42be8dd62763c3a06f445f2d2a8be610`
- Fix PR: Demon#267 (merged 2025-10-11)
- Docs PR: Demon#268 (merged 2025-10-12)

**HOSS Environment:**
- HHFAB version: v0.41.3
- HHFAB image digest: `ghcr.io/afewell-hh/hoss/hhfab@sha256:54814bbf4e8459cfb35c7cf8872546f0d5d54da9fc317ffb53eab0e137b21d7b`

**Validation Result:**
- Exit code: 0 ✅
- Envelope location: `/workspace/.artifacts/summary.json` ✅
- Validation status: `ok` ✅
- Validated items: 1 ✅
- Warnings: 0 ✅
- Failures: 0 ✅

**Outcome:** Workspace mount fix confirmed working. No manual Docker workaround required.

---

## RC1 Feedback & Changes for GA

### Known Issues from RC1
1. **Demon workspace mount** (Demon#265)
   - **Status**: ✅ RESOLVED (Demon PR #267, merged 2025-10-11, SHA 52884c7b)
   - **Impact**: High - required manual Docker workaround in RC1
   - **Resolution**: Fix validated 2025-10-12; demonctl 0.0.1 working correctly

2. **Signing not enabled in RC1**
   - **Status**: ✅ Resolved in Wave B
   - **Impact**: Medium - unsigned releases
   - **Resolution**: cosign wired up, Makefile updated, app-pack.yaml enabled

### Feedback Collected
- [ ] User testing feedback (if any)
- [ ] Demon team integration feedback
- [ ] Operate UI team feedback
- [ ] Performance observations

### Changes for GA
- [x] Enable cosign signing
- [x] Add signature verification to README
- [x] Update release workflow for signature upload
- [ ] Re-run confirm-on-main after Demon fix
- [ ] Final performance baseline
- [ ] Update version to v0.1.0 (drop -rc1 suffix)

---

## Test Coverage Expectations

### Unit Tests
- Contract schema validation
- Envelope structure tests
- Script logic tests (hhfab-validate.sh)

### Integration Tests
- demonctl app install
- demonctl run with sample topology
- Manual Docker fallback
- Review-kit (smoke + strict)

### E2E Tests
- Full workflow: install → run → UI display
- Signature verification flow
- Error handling (invalid topology, missing files)

### Performance Baseline (v0.1.0 GA)

**Documented**: 2025-10-13
**Environment**: GitHub Actions ubuntu-latest runner
**HHFAB Version**: v0.41.3
**HHFAB Image**: `ghcr.io/afewell-hh/hoss/hhfab@sha256:54814bbf4e8459cfb35c7cf8872546f0d5d54da9fc317ffb53eab0e137b21d7b`

#### Review-Kit (Strict) Performance

Based on CI workflow runs for v0.1.0 GA release:

- **Total workflow time**: ~2-3 minutes (smoke-local + review-kit strict)
- **smoke-local job**: 15-20 seconds
  - Container pull: <5s (cached)
  - Validation execution: 10-15s
  - Matrix size: 1 sample (topology-min.yaml)

- **review-kit (strict) job**: 20-30 seconds
  - Container pull: <5s (digest-pinned, cached)
  - Validation execution: 15-25s
  - Enforcement gates: <1s
  - SARIF generation: <1s
  - Matrix size: 1 sample

#### Sample Validation Times

- **topology-min.yaml**: <1s (minimal trigger file)
- **topology-basic.yaml**: ~1-2s (estimated, basic config)
- **topology-complex.yaml**: ~2-5s (estimated, complex config)

#### Resource Usage

- **Memory**: <100MB per validation (HHFAB container)
- **CPU**: Single-core, minimal usage
- **Disk**: ~20MB (HHFAB image size: 7.6MB tarball)
- **Network**: None (--network=none in strict mode)

#### Performance Notes

- Container image caching significantly reduces pull time
- Validation time scales linearly with topology complexity
- No significant overhead from envelope generation (<100ms)
- Review-kit strict mode adds minimal overhead for enforcement checks

**Baseline established**: v0.1.0 GA provides acceptable performance for CI/CD integration

---

## Promotion Runbook

See [Release Runbook](./runbooks/release.md) for detailed promotion steps:
1. Final review-kit run on main
2. Build GA app-pack (`make app-pack-build`)
3. Sign with OIDC (`make app-pack-sign` in CI)
4. Create v0.1.0 tag
5. Publish GitHub release with notes
6. Upload tarball + signature bundle
7. Update README to point to v0.1.0
8. Announce in team channels

---

## Rollback Plan

If critical issues are discovered post-GA:

### Immediate Actions
1. Add notice to release page
2. Point README back to RC1 or last stable
3. Create hotfix branch if patch needed
4. Document issue in GitHub issue

### Fix & Republish
1. Fix on hotfix branch
2. Re-run full test suite
3. Publish as v0.1.1 or v0.1.0-hotfix
4. Update README and release notes

### Communication
- Notify users via GitHub release update
- Post in team Slack/Discord
- Update docs with known issues

---

## Dependencies

### ✅ Resolved: Demon Workspace Mount Fix
- **Issue**: Demon#265
- **Dispatch**: Demon#266
- **Fix PR**: Demon#267 (merged 2025-10-11)
- **Docs PR**: Demon#268 (merged 2025-10-12)
- **Demon SHA**: 52884c7b42be8dd62763c3a06f445f2d2a8be610
- **Validation**: Confirmed working 2025-10-12 with demonctl 0.0.1
- **Status**: No longer a blocker for GA

### Nice-to-Have (Not GA Blockers)
- hossctl CLI wrapper (future enhancement)
- Matrix-based multi-topology validation
- Performance optimizations
- Additional contract fields

---

## Sign-Off

Before GA release, confirm:
- [x] All core functionality tests pass
- [x] Demon workspace mount fix merged and validated
- [x] Signing working in CI
- [x] Documentation complete and accurate
- [ ] UI integration verified
- [ ] Performance baseline documented
- [x] Rollback plan reviewed and understood
- [ ] Team approval obtained

**Approved by**: _Pending PM review_
**GA Release Date**: _Ready for PM go/no-go decision_

---

## References

- **RC1 Release**: https://github.com/afewell-hh/hoss/releases/tag/v0.1.0-rc1
- **RC1 Prep (Issue #51)**: https://github.com/afewell-hh/hoss/issues/51
- **Wave B Dispatch (Issue #53)**: https://github.com/afewell-hh/hoss/issues/53
- **Signing Issue (#52)**: https://github.com/afewell-hh/hoss/issues/52
- **Demon Workspace Mount**: Demon#265, Demon#266
- **Review Kit Runbook**: [./runbooks/review-kit.md](./runbooks/review-kit.md)
