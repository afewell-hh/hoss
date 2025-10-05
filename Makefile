.PHONY: review-kit review-kit-strict bundle/preview bundle/check bundle/verify bundle/keys \
	hossctl hossctl-build hossctl-install hossctl-test \
	app-pack app-pack-build app-pack-sign app-pack-test

review-kit:
	@bash scripts/hhfab-validate.sh

review-kit-strict:
	@[ -n "$$HHFAB_IMAGE_DIGEST" ] || (echo "Set HHFAB_IMAGE_DIGEST"; exit 1)
	@mkdir -p .artifacts/review-kit
	docker run --rm --network=none --read-only --user 65532:65532 \
	  --mount type=bind,source="$$PWD/.artifacts",target=/w/.artifacts \
	  -v "$$PWD:/w:ro" -w /w \
	  -e STRICT=1 -e MATRIX="$$${MATRIX:-}" \
	  -e HHFAB_IMAGE="$$HHFAB_IMAGE_DIGEST" -e HHFAB_IMAGE_DIGEST="$$HHFAB_IMAGE_DIGEST" \
	  "$$HHFAB_IMAGE_DIGEST" \
	  bash -lc 'set -Eeuo pipefail; hhfab version; bash scripts/hhfab-validate.sh'

bundle/preview:
	@mkdir -p .artifacts
	@./scripts/collect-digests.sh \
	  --bundle-out .artifacts/preview-bundle.yaml \
	  --json-out .artifacts/digests.json
	@echo "Wrote .artifacts/preview-bundle.yaml and .artifacts/digests.json"

bundle/check:
	@test -f .artifacts/digests.json || { echo "Run 'make bundle/preview' first"; exit 1; }
	@jq -r '.images|to_entries[]|"\(.key): \(.value)"' .artifacts/digests.json

bundle/verify:
	@mkdir -p .artifacts
	@COSIGN_VERIFY=1 REQUIRE_PINS=1 ./scripts/collect-digests.sh \
	  --bundle-out .artifacts/preview-bundle.yaml \
	  --json-out .artifacts/digests.json
	@echo "✅ Bundle verified with cosign + digest pins enforced"

bundle/keys:
	@test -f .artifacts/digests.json || { echo "Run 'make bundle/preview' first"; exit 1; }
	@jq -r '.images|keys[]' .artifacts/digests.json

# hossctl CLI targets
hossctl: hossctl-build

hossctl-build:
	@echo "Building hossctl..."
	@cd hossctl && go build -o hossctl .
	@echo "✅ Built: hossctl/hossctl"

hossctl-install:
	@echo "Installing hossctl to PATH..."
	@cd hossctl && go install .
	@echo "✅ Installed hossctl"

hossctl-test:
	@echo "Testing hossctl..."
	@cd hossctl && go test -v ./...

hossctl-cross:
	@echo "Cross-compiling hossctl..."
	@mkdir -p .artifacts/hossctl
	@cd hossctl && GOOS=linux GOARCH=amd64 go build -o ../.artifacts/hossctl/hossctl-linux-amd64 .
	@cd hossctl && GOOS=linux GOARCH=arm64 go build -o ../.artifacts/hossctl/hossctl-linux-arm64 .
	@cd hossctl && GOOS=darwin GOARCH=amd64 go build -o ../.artifacts/hossctl/hossctl-darwin-amd64 .
	@cd hossctl && GOOS=darwin GOARCH=arm64 go build -o ../.artifacts/hossctl/hossctl-darwin-arm64 .
	@cd hossctl && GOOS=windows GOARCH=amd64 go build -o ../.artifacts/hossctl/hossctl-windows-amd64.exe .
	@echo "✅ Cross-compiled binaries in .artifacts/hossctl/"

# App Pack targets
app-pack: app-pack-build

app-pack-build:
	@echo "Building HOSS App Pack..."
	@mkdir -p .artifacts
	@tar -czf .artifacts/hoss-app-pack-v0.1.0.tar.gz app-pack/
	@echo "✅ Built: .artifacts/hoss-app-pack-v0.1.0.tar.gz"

app-pack-sign:
	@echo "Signing HOSS App Pack with cosign..."
	@test -f .artifacts/hoss-app-pack-v0.1.0.tar.gz || { echo "Run 'make app-pack-build' first"; exit 1; }
	@cosign sign-blob --yes .artifacts/hoss-app-pack-v0.1.0.tar.gz \
	  --output-signature .artifacts/hoss-app-pack-v0.1.0.tar.gz.sig \
	  --output-certificate .artifacts/hoss-app-pack-v0.1.0.tar.gz.cert
	@echo "✅ Signed: .artifacts/hoss-app-pack-v0.1.0.tar.gz.sig"

app-pack-verify:
	@echo "Verifying HOSS App Pack signature..."
	@test -f .artifacts/hoss-app-pack-v0.1.0.tar.gz.sig || { echo "Run 'make app-pack-sign' first"; exit 1; }
	@cosign verify-blob .artifacts/hoss-app-pack-v0.1.0.tar.gz \
	  --signature .artifacts/hoss-app-pack-v0.1.0.tar.gz.sig \
	  --certificate .artifacts/hoss-app-pack-v0.1.0.tar.gz.cert \
	  --certificate-identity-regexp="^https://github.com/.+/.+@" \
	  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
	@echo "✅ Signature verified"

app-pack-test:
	@echo "Testing HOSS App Pack structure..."
	@test -f app-pack/app-pack.yaml || { echo "Missing app-pack.yaml"; exit 1; }
	@test -f app-pack/contracts/hoss/validate.request.json || { echo "Missing validate.request.json"; exit 1; }
	@test -f app-pack/contracts/hoss/validate.result.json || { echo "Missing validate.result.json"; exit 1; }
	@test -f app-pack/capsules/hhfab/scripts/hhfab-validate.sh || { echo "Missing hhfab-validate.sh"; exit 1; }
	@test -x app-pack/capsules/hhfab/scripts/hhfab-validate.sh || { echo "hhfab-validate.sh not executable"; exit 1; }
	@test -f app-pack/rituals/hoss-validate.yaml || { echo "Missing hoss-validate.yaml"; exit 1; }
	@test -f app-pack/ui/cards/hoss-validate.card.yaml || { echo "Missing hoss-validate.card.yaml"; exit 1; }
	@echo "✅ App Pack structure validated"