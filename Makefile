.PHONY: review-kit review-kit-strict

review-kit:
	@bash scripts/hhfab-validate.sh

review-kit-strict:
	@[ -n "$$HHFAB_IMAGE_DIGEST" ] || (echo "Set HHFAB_IMAGE_DIGEST"; exit 1)
	@mkdir -p .artifacts/review-kit
	docker run --rm --network=none --read-only --user 65532:65532 \
	  --mount type=bind,source="$$PWD/.artifacts",target=/w/.artifacts \
	  -v "$$PWD:/w:ro" -w /w \
	  -e STRICT=1 -e MATRIX="$${MATRIX:-}" \
	  -e HHFAB_IMAGE="$$HHFAB_IMAGE_DIGEST" -e HHFAB_IMAGE_DIGEST="$$HHFAB_IMAGE_DIGEST" \
	  "$$HHFAB_IMAGE_DIGEST" \
	  bash -lc 'set -Eeuo pipefail; hhfab version; bash scripts/hhfab-validate.sh'
