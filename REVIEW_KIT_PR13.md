# HOSS PR #13 — Quick Review Kit

This checklist captures the review guardrails requested for pull request [afewell-hh/hoss#13](https://github.com/afewell-hh/hoss/pull/13). Work through each section in order.

## 1. Fetch & Sanity Checks
- [ ] Fetch PR metadata
  ```sh
  gh pr view afewell-hh/hoss#13 --json title,author,headRefName,baseRefName,mergeStateStatus,additions,deletions,changedFiles,labels
  ```
- [ ] Checkout the PR head
  ```sh
  gh pr checkout 13
  ```
- [ ] Ensure no vendored dependencies are tracked
  ```sh
  git status --porcelain | grep -E '^?? node_modules/' && echo "ERROR: node_modules tracked" || echo "OK: no node_modules tracked"
  ```
- [ ] Verify lockfile consistency (use the project package manager)
  ```sh
  npm ci
  ```

## 2. Lint, Type, and Unit Tests
- [ ] Lint (fail on warnings)
  ```sh
  npm run lint -- --max-warnings=0
  ```
- [ ] Typecheck
  ```sh
  npm run typecheck || npx tsc -p tsconfig.json --noEmit
  ```
- [ ] Core/unit test suite
  ```sh
  npm run test:core -w
  ```

## 3. ONF Spec Alignment Quick Probes
Grounded in research tickets #1–#9.

- [ ] Generate a known-valid virtual lab (control)
  ```sh
  hhfab vlab gen --out /tmp/hoss_vlab_ctrl.yaml
  ```
- [ ] Produce a WiringDiagram CR from the PR branch
  ```sh
  npm run cli:generate -- --profile ds2000 --spines 2 --leaves 4 --endpoints 48 --out /tmp/hoss_pr_wiring.yaml
  ```
- [ ] Validate with hhfab
  ```sh
  hhfab validate --in /tmp/hoss_pr_wiring.yaml
  ```
- [ ] Breakout child-port naming spot check
  ```sh
  grep -E '(^|[^A-Za-z0-9])49(/1|/2|/3|/4)' /tmp/hoss_pr_wiring.yaml || echo "WARN: expected breakout child names not found"
  ```
- [ ] Switch profile sanity count
  ```sh
  grep -E 'model:\s*(DS2000|DS3000|<list the 14 you support>)' -c /tmp/hoss_pr_wiring.yaml
  ```

## 4. Golden Samples & Story Requirements
Confirm the PR includes:
- [ ] Golden WiringDiagram CRs under `samples/` (virtual + physical with breakouts)
- [ ] README describing assumptions and deltas
- [ ] Automated test invoking `hhfab validate` on the goldens (smoke)
- [ ] Matrix test that covers at least one breakout-capable switch profile

## 5. Review Comment Skeleton
Paste this checklist into the PR review comment and tick items as you verify them.
```
**Scope & Risk**
- [ ] No vendored deps or node_modules committed
- [ ] Lockfile in sync (npm ci passes)
- [ ] Lint/type/tests green

**ONF Alignment (per research tickets #1–#9)**
- [ ] Breakout naming matches GetAPI2NOSPortsFor() (child port scheme verified)
- [ ] Port compatibility validated (speed/capacity, no server on uplink ranges)
- [ ] Topology rules OK (spine/leaf counts, LAG/MC-LAG constraints)

**Artifacts**
- [ ] Golden CRs added under samples/ (virtual + physical w/ breakouts)
- [ ] hhfab validate smoke included in CI
- [ ] README notes deltas vs `hhfab vlab gen`

**Follow-ups**
- [ ] Open a tech-debt issue if any //TODO or relaxed check remains
```

## 6. Optional CI Guardrails to Backport
If not already present, stage these in a separate maintenance PR:
- [ ] `validate:hhfab` npm script that shells out to `hhfab validate` for CRs under `samples/`
- [ ] GitHub Action job `hhfab-validate` running the script on PRs
- [ ] WASM or bundle size guard (if applicable) to catch bloat

## 7. Merge Gate
Before approving, ensure:
- [ ] Lint, typecheck, and core tests are green
- [ ] `hhfab validate` passes on golden CRs
- [ ] Breakout naming spot-checks succeed
- [ ] Reviewer checklist items are all confirmed

Document completion notes or follow-ups in your review summary.
