###############################################################################
# Azure Workload Identity Federation for GitHub Actions
#
# Allows GitHub Actions to authenticate against Azure without stored credentials.
# GitHub presents a short-lived OIDC JWT → Azure AD validates it → issues a token
# bound to a Service Principal.
#
# Reference: https://learn.microsoft.com/en-us/azure/active-directory/workload-identities/workload-identity-federation
###############################################################################

data "azurerm_subscription" "current" {}
data "azuread_client_config" "current" {}

# --- Azure AD Application ---

resource "azuread_application" "github_actions" {
  display_name = "${var.project_prefix}-github-actions"
  owners       = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "github_actions" {
  client_id = azuread_application.github_actions.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

# --- Federated Identity Credential (OIDC) ---
#
# This is the key resource: it tells Azure AD to trust JWTs from GitHub Actions
# for the specified repository and branch.

resource "azuread_application_federated_identity_credential" "github_main" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-main-branch"
  description    = "GitHub Actions OIDC — main branch deploys"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:ref:refs/heads/${var.github_branch}"
}

# Allow environment-scoped jobs (e.g. environment: production in apply jobs)
resource "azuread_application_federated_identity_credential" "github_environment" {
  for_each       = toset(var.github_environments)
  application_id = azuread_application.github_actions.id
  display_name   = "github-env-${each.key}"
  description    = "GitHub Actions OIDC — environment: ${each.key}"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:environment:${each.key}"
}

# Also allow PRs to authenticate (for plan-only)
resource "azuread_application_federated_identity_credential" "github_pr" {
  application_id = azuread_application.github_actions.id
  display_name   = "github-pull-requests"
  description    = "GitHub Actions OIDC — pull request plans"
  audiences      = ["api://AzureADTokenExchange"]
  issuer         = "https://token.actions.githubusercontent.com"
  subject        = "repo:${var.github_repo}:pull_request"
}

# --- IAM: grant Service Principal Contributor on subscription ---

resource "azurerm_role_assignment" "contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azuread_service_principal.github_actions.object_id
}

# --- Variables ---

variable "project_prefix" { type = string }
variable "github_repo" {
  description = "GitHub repo in org/repo format (e.g. LucasNic/multi-cloud-resilience-platform)"
  type        = string
}
variable "github_branch" {
  type    = string
  default = "main"
}

variable "github_environments" {
  description = "GitHub Actions environments that need OIDC access (e.g. [\"production\"])"
  type        = list(string)
  default     = []
}

# --- Outputs ---

output "client_id" {
  description = "Azure AD Application client ID — used in GitHub Actions workflow"
  value       = azuread_application.github_actions.client_id
}

output "tenant_id" {
  description = "Azure AD tenant ID — used in GitHub Actions workflow"
  value       = data.azuread_client_config.current.tenant_id
}

output "subscription_id" {
  description = "Azure subscription ID — used in GitHub Actions workflow"
  value       = data.azurerm_subscription.current.subscription_id
}
