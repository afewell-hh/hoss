## Summary
-

## Testing
-

## Checklist
- [ ] I ran strict locally (or confirmed the strict job ran in CI) for hhfab-sensitive paths and reviewed `.artifacts/review-kit/summary.json`.

### Review Kit (PR #13 pattern)
Please follow **REVIEW_KIT_PR13.md** before requesting merge:

- [ ] Lint/type/tests green
- [ ] ONF alignment quick-probes completed
- [ ] Goldens + `hhfab validate` smoke present (or tracked as follow-ups)
- [ ] I ran `make review-kit` locally and it passed
- [ ] I attached hhfab logs if any validations failed