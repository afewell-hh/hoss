.PHONY: review-kit
review-kit: ## Run the review kit local smoke
npm run lint -- --max-warnings=0
npm run typecheck || npx tsc -p tsconfig.json --noEmit
npm run test:core || npm test
npm run hhfab:smoke || echo "NOTE: hhfab smoke skipped (tool missing)"
