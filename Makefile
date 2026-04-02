.PHONY: help plan apply destroy fmt lint security cost clean

CLOUD ?= aws
ENV ?= dev

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-18s\033[0m %s\n", $$1, $$2}'

plan: ## Terragrunt plan (CLOUD=aws|azure)
	cd live/$(CLOUD) && terragrunt run-all plan --terragrunt-non-interactive

apply: ## Terragrunt apply
	cd live/$(CLOUD) && terragrunt run-all apply --terragrunt-non-interactive

destroy: ## Terragrunt destroy
	cd live/$(CLOUD) && terragrunt run-all destroy --terragrunt-non-interactive

plan-all: ## Plan both clouds
	cd live && terragrunt run-all plan --terragrunt-non-interactive

fmt: ## Format Terraform
	terraform fmt -recursive modules/

lint: ## TFLint all modules
	@find modules -name "*.tf" -exec dirname {} \; | sort -u | while read d; do tflint --chdir="$$d" || true; done

security: ## Checkov scan
	checkov -d modules/ --framework terraform --soft-fail

cost: ## Infracost estimate
	infracost breakdown --path=live/ --terraform-binary=terragrunt

ci-local: fmt lint security ## Full local CI

plan-eks: ## Plan EKS only
	$(MAKE) plan CLOUD=aws

plan-aks: ## Plan AKS only
	$(MAKE) plan CLOUD=azure

failover-test: ## Simulate failover (disable EKS health check)
	@echo "Disabling EKS health check to trigger Route53 failover..."
	@echo "aws route53 update-health-check --health-check-id HC_ID --disabled"

clean: ## Remove caches
	find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
