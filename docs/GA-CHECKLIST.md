# HOSS GA Readiness Checklist

**Purpose**: Pre-flight checklist for promoting HOSS from RC to General Availability (GA).

**Status**: 🚧 In Progress (pending Demon workspace mount fix)

---

## Release Criteria

### Core Functionality
- [x] App Pack structure complete and validated
- [x] Container-based validation working (hhfab v0.41.3+)
- [x] ResultEnvelope format with required metrics
- [x] Non-login shell execution (/bin/bash -c)
- [ ] **BLOCKER**: `demonctl run` workspace mount issue resolved (Demon#265)
- [ ] Post-fix validation complete (see plan below)

### Security & Signing
- [x] cosign installed and configured
- [x] Local signing/verification tested (`make app-pack-sign`, `make app-pack-verify`)
- [x] app-pack.yaml signing enabled (`cosign.enabled: true`)
- [ ] GitHub Actions workflow updated with OIDC signing
- [ ] Release workflow uploads signature bundle
- [ ] README includes signature verification instructions

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

---

## RC1 Feedback & Changes for GA

### Known Issues from RC1
1. **Demon workspace mount** (Demon#265)
   - **Status**: Blocked - awaiting Demon fix
   - **Impact**: High - requires manual Docker workaround
   - **Resolution**: Demon team investigating; fix planned for parity wave

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
- [ ] Update release workflow for signature upload
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

### Performance Baseline
- Validation time for sample topologies
- Container startup overhead
- Envelope generation time
- Memory/CPU usage during validation

**Target**: Document baseline metrics before GA

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

### Blocker: Demon Workspace Mount Fix
- **Issue**: Demon#265
- **Dispatch**: Demon#266
- **Impact**: GA cannot proceed until this is resolved
- **Workaround**: Manual Docker execution (documented in RC1)
- **ETA**: Pending Demon team schedule

### Nice-to-Have (Not GA Blockers)
- hossctl CLI wrapper (future enhancement)
- Matrix-based multi-topology validation
- Performance optimizations
- Additional contract fields

---

## Sign-Off

Before GA release, confirm:
- [ ] All core functionality tests pass
- [ ] Demon workspace mount fix merged and validated
- [ ] Signing working in CI
- [ ] Documentation complete and accurate
- [ ] UI integration verified
- [ ] Performance baseline documented
- [ ] Rollback plan reviewed and understood
- [ ] Team approval obtained

**Approved by**: _Pending_
**GA Release Date**: _TBD (after Demon fix)_

---

## References

- **RC1 Release**: https://github.com/afewell-hh/hoss/releases/tag/v0.1.0-rc1
- **RC1 Prep (Issue #51)**: https://github.com/afewell-hh/hoss/issues/51
- **Wave B Dispatch (Issue #53)**: https://github.com/afewell-hh/hoss/issues/53
- **Signing Issue (#52)**: https://github.com/afewell-hh/hoss/issues/52
- **Demon Workspace Mount**: Demon#265, Demon#266
- **Review Kit Runbook**: [./runbooks/review-kit.md](./runbooks/review-kit.md)
