.PHONY: review-kit review-kit-strict

review-kit:
	@bash scripts/hhfab-validate.sh

review-kit-strict:
	@[ -n "$$HHFAB_IMAGE_DIGEST" ] || (echo "Set HHFAB_IMAGE_DIGEST"; exit 1)
	docker run --rm --network=none --read-only --user 65532:65532 \
	  -v "$$PWD:/w" -w /w "$$HHFAB_IMAGE_DIGEST" \
	  bash -lc 'set -Eeuo pipefail; hhfab version; bash scripts/hhfab-validate.sh'
